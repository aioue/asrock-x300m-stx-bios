#!/usr/bin/env bash
# Measure DeskMini idle plug power and host state for power-tuning cycles.
# See POWER-TUNING-RUNBOOK.md and ../results/power-tuning.csv
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CSV_FILE="${CSV_FILE:-${REPO_ROOT}/results/power-tuning.csv}"

HA_URL="${HA_URL:-https://ha.home.aioue.net}"
HA_ENTITY="${HA_ENTITY:-sensor.plug2_ikea_energy_power}"
HA_SSH="${HA_SSH:-hassio@192.168.1.240}"
HA_SSH_OPTS=(-o ControlMaster=no -o ConnectTimeout=15)

PVE_HOST="${PVE_HOST:-192.168.1.10}"
PVE_SSH_OPTS=(-o ControlMaster=no -o ConnectTimeout=15)

PLUG_SAMPLES="${PLUG_SAMPLES:-5}"
PLUG_INTERVAL="${PLUG_INTERVAL:-12}"
SETTLE_CHECKS="${SETTLE_CHECKS:-3}"
SETTLE_INTERVAL="${SETTLE_INTERVAL:-60}"
LOAD_MAX="${LOAD_MAX:-2.0}"
QUICK_LOAD_MAX="${QUICK_LOAD_MAX:-1.0}"
QUICK_LOAD_CHECKS="${QUICK_LOAD_CHECKS:-2}"
QUICK_LOAD_INTERVAL="${QUICK_LOAD_INTERVAL:-30}"
PLUG_STABLE_W="${PLUG_STABLE_W:-15}"

TIME_TO_SSH_S=""
TIME_TO_SETTLED_S=""

usage() {
  cat <<'EOF'
Usage: measure-idle-power.sh --baseline --label NAME [--note TEXT]
       measure-idle-power.sh --measure --label NAME [--note TEXT]
       measure-idle-power.sh --measure --wait-idle --label NAME
       measure-idle-power.sh --reboot --label NAME [--note TEXT]
       measure-idle-power.sh --diff LABEL_A LABEL_B
       measure-idle-power.sh --wait-settle

Environment:
  HA_TOKEN          Bearer token for HA REST API (preferred)
  HA_URL            Default https://ha.home.aioue.net (Caddy); fallback http://192.168.1.240:8123
  PLUG_SOURCE       ha|z2m|auto (default auto)
  PVE_HOST          Default 192.168.1.10
  CSV_FILE          Default ../results/power-tuning.csv
  QUICK_LOAD_MAX    Max loadavg[0] for --quick post-reboot wait (default 1.0)
  QUICK_LOAD_CHECKS Consecutive low-load samples required (default 2)
  QUICK_LOAD_INTERVAL Seconds between load checks (default 30)
  LOAD_MAX          Max loadavg[0] for full --wait-settle (default 2.0)
EOF
}

log() { printf '[%s] %s\n' "$(date '+%H:%M:%S')" "$*" >&2; }
die() { log "ERROR: $*"; exit 1; }

median_float() {
  python3 - "$@" <<'PY'
import statistics, sys
vals = [float(x) for x in sys.argv[1:] if x]
if not vals:
    raise SystemExit(1)
print(f"{statistics.median(vals):.2f}")
PY
}

plug_sample_ha() {
  local state
  state="$(curl -fsS -H "Authorization: Bearer ${HA_TOKEN}" \
    "${HA_URL}/api/states/${HA_ENTITY}" 2>/dev/null)" || return 1
  python3 -c 'import json,sys; print(json.load(sys.stdin)["state"])' <<<"${state}"
}

plug_sample_z2m() {
  local topic="plug2_ikea_energy"
  ssh "${HA_SSH_OPTS[@]}" "${HA_SSH}" \
    "grep -h '${topic}' /config/zigbee2mqtt/log/*/log.log 2>/dev/null | tail -1" \
    | python3 -c "import json,re,sys; line=sys.stdin.read(); m=re.search(r\"payload '(\{.*\})'\", line); sys.exit(1) if not m else print(json.loads(m.group(1)).get('power',''))"
}

sample_plug_once() {
  local source="${PLUG_SOURCE:-auto}"
  if [[ "${source}" == auto ]]; then
    if [[ -n "${HA_TOKEN:-}" ]]; then
      source=ha
    else
      source=z2m
    fi
  fi
  case "${source}" in
    ha) plug_sample_ha ;;
    z2m) plug_sample_z2m ;;
    *) die "Unknown PLUG_SOURCE=${source}" ;;
  esac
}

sample_plug_median() {
  local -a samples=()
  local i val
  for ((i = 1; i <= PLUG_SAMPLES; i++)); do
    if val="$(sample_plug_once 2>/dev/null)"; then
      samples+=("${val}")
      log "Plug sample ${i}/${PLUG_SAMPLES}: ${val} W"
    else
      log "Plug sample ${i}/${PLUG_SAMPLES}: failed"
    fi
    (( i < PLUG_SAMPLES )) && sleep "${PLUG_INTERVAL}"
  done
  ((${#samples[@]} > 0)) || die "No plug samples collected"
  median_float "${samples[@]}"
}

pve_ssh() {
  ssh "${PVE_SSH_OPTS[@]}" "root@${PVE_HOST}" "$@"
}

# Print ZFS/maintenance blockers on the host (one per line). Empty output = idle.
host_zfs_blockers() {
  pve_ssh 'bash -s' <<'EOS'
set -euo pipefail
reasons=()

# Scrub/resilver/trim still running on any pool
if zpool status 2>/dev/null | grep -qiE 'scan:[[:space:]]*(scrub|resilver|initialize|trim).*progress'; then
  reasons+=("zpool scan in progress")
fi

# Explicit scrub/send/recv processes (cron scrubs on fast/slow, zrepl streams)
if ps -eo args= 2>/dev/null | grep -qE '[[:space:]]zpool scrub[[:space:]]'; then
  reasons+=("zpool scrub process")
fi
if ps -eo args= 2>/dev/null | grep -qE '[[:space:]]zfs (send|receive)[[:space:]]'; then
  reasons+=("zfs send/recv active")
fi

# systemd maintenance (scrub@, import@, zfs-health, backup-cache timers)
if systemctl list-jobs --no-legend 2>/dev/null | grep -qE 'scrub@|zfs-|import@|export@|zfs-backup'; then
  reasons+=("systemd ZFS job running")
fi

# zrepl replication/pruning only when a step is actively in flight (not idle/error structs)
if command -v zrepl >/dev/null && command -v python3 >/dev/null; then
  blocker="$(python3 <<'PY'
import subprocess, sys
try:
    import yaml
except ImportError:
    sys.exit(0)

ACTIVE_REP = {"sync", "stepping", "send", "recv", "running"}
ACTIVE_PRUNE = {"running", "sync", "stepping"}
ZERO_TIME = "0001-01-01"

def unfinished(t):
    return not t or str(t).startswith(ZERO_TIME)

try:
    raw = subprocess.check_output(["zrepl", "status", "--mode", "raw"], text=True)
except (subprocess.CalledProcessError, FileNotFoundError):
    sys.exit(0)

d = yaml.safe_load(raw) or {}
for name, job in (d.get("Jobs") or {}).items():
    if name.startswith("_"):
        continue
    t = job.get("type")
    if t == "pull":
        p = job.get("pull") or {}
        rep = p.get("Replication")
        if isinstance(rep, dict) and unfinished(rep.get("FinishAt")):
            for att in rep.get("Attempts") or []:
                state = (att.get("State") or "").lower()
                if state in ACTIVE_REP and unfinished(att.get("FinishAt")):
                    print(f"zrepl {name} replication {state}")
                    sys.exit(0)
        for k in ("PruningSender", "PruningReceiver"):
            block = p.get(k)
            if isinstance(block, dict):
                state = (block.get("State") or "").lower()
                if state in ACTIVE_PRUNE:
                    print(f"zrepl {name} {k} {state}")
                    sys.exit(0)
    elif t == "snap":
        s = job.get("snap") or {}
        prune = s.get("Pruning")
        if isinstance(prune, dict):
            state = (prune.get("State") or "").lower()
            if state in ACTIVE_PRUNE:
                print(f"zrepl {name} pruning {state}")
                sys.exit(0)
        snap = s.get("Snapshotting") or {}
        for mode in ("Periodic", "Cron", "Manual"):
            block = snap.get(mode)
            if isinstance(block, dict) and block.get("Progress") is not None:
                print(f"zrepl {name} snapshot {mode} active")
                sys.exit(0)
PY
)"
  [[ -n "${blocker}" ]] && reasons+=("${blocker}")
fi

printf '%s\n' "${reasons[@]}"
EOS
}

# load + ZFS idle check. Returns 0 when safe to sample plug power.
idle_check_pass() {
  local load_max="$1"
  local load
  local -a zfs_blockers=()

  load="$(pve_ssh "awk '{print \$1}' /proc/loadavg" 2>/dev/null || echo 99)"
  if ! awk -v l="${load}" -v m="${load_max}" 'BEGIN { exit !(l < m) }'; then
    log "Idle check: load=${load} (need < ${load_max})"
    return 1
  fi

  while IFS= read -r line; do
    [[ -n "${line}" ]] && zfs_blockers+=("${line}")
  done < <(host_zfs_blockers 2>/dev/null || true)

  if ((${#zfs_blockers[@]} > 0)); then
    log "Idle check: ${zfs_blockers[0]}"
    return 1
  fi

  return 0
}

guest_inventory_hash() {
  pve_ssh 'qm config 101; qm config 102; pct config 200' | sha256sum | awk '{print substr($1,1,16)}'
}

cpuidle_max() {
  pve_ssh 'for s in /sys/devices/system/cpu/cpu0/cpuidle/state*/name; do cat "$s"; done' | tail -1
}

host_metrics_json() {
  pve_ssh "bash -s" <<'EOS'
set -euo pipefail
python3 <<'PY'
import json, pathlib
cmdline = pathlib.Path("/proc/cmdline").read_text().replace("\x00", " ").strip()
load = pathlib.Path("/proc/loadavg").read_text().split()[0]
mem_sleep = pathlib.Path("/sys/power/mem_sleep").read_text().strip() if pathlib.Path("/sys/power/mem_sleep").exists() else "n/a"
aspm = pathlib.Path("/sys/module/pcie_aspm/parameters/policy").read_text().strip() if pathlib.Path("/sys/module/pcie_aspm/parameters/policy").exists() else "n/a"
import subprocess
bios = subprocess.check_output(["dmidecode", "-s", "bios-version"], text=True).strip()
zpools = ",".join(subprocess.check_output(["zpool", "list", "-H"], text=True).splitlines()) if True else ""
wd60 = 1 if any("wd60" in x.name.lower() for x in pathlib.Path("/dev/disk/by-id").iterdir()) else 0
print(json.dumps({"cmdline": cmdline, "loadavg1": load, "mem_sleep": mem_sleep, "aspm_policy": aspm, "bios": bios, "zpools": zpools, "wd60_present": wd60}))
PY
EOS
}

guest_status_line() {
  pve_ssh 'printf "101:%s 102:%s 200:%s\n" "$(qm status 101 --verbose 0 2>/dev/null | awk "{print \$2}")" "$(qm status 102 --verbose 0 2>/dev/null | awk "{print \$2}")" "$(pct status 200 2>/dev/null | awk "{print \$2}")"'
}

ha_entity_ok() {
  if [[ -z "${HA_TOKEN:-}" ]]; then
    ssh "${HA_SSH_OPTS[@]}" "${HA_SSH}" 'test -d /config/zigbee2mqtt/log'
    return
  fi
  local code
  code="$(curl -s -o /dev/null -w '%{http_code}' -H "Authorization: Bearer ${HA_TOKEN}" \
    "${HA_URL}/api/states/${HA_ENTITY}")"
  [[ "${code}" == "200" ]]
}

wait_settled() {
  local start_ts=$(( $(date +%s) ))
  local ssh_ts=0
  local ok_streak=0
  local -a plug_last=()

  log "Waiting for settle (${SETTLE_CHECKS} checks, ${SETTLE_INTERVAL}s apart)..."

  while (( ok_streak < SETTLE_CHECKS )); do
    local ok=true

    if pve_ssh 'true' 2>/dev/null; then
      if (( ssh_ts == 0 )); then
        ssh_ts=$(( $(date +%s) - start_ts ))
        log "SSH up at ${ssh_ts}s"
      fi
    else
      ok=false
      log "Settle: SSH not ready"
    fi

    if ! pve_ssh 'qm status 101 | grep -q running && qm status 102 | grep -q running && pct status 200 | grep -q running' 2>/dev/null; then
      ok=false
      log "Settle: guests not all running"
    fi

    if idle_check_pass "${LOAD_MAX}"; then
      :
    else
      ok=false
    fi

    if ! ha_entity_ok 2>/dev/null; then
      ok=false
      log "Settle: plug entity / z2m not ready"
    fi

    local plug
    if plug="$(sample_plug_once 2>/dev/null)"; then
      plug_last+=("${plug}")
      if ((${#plug_last[@]} > 3)); then
        plug_last=("${plug_last[@]: -3}")
      fi
      if ((${#plug_last[@]} == 3)); then
        local spread
        spread="$(python3 - "${plug_last[@]}" <<'PY'
import sys
vals=[float(x) for x in sys.argv[1:]]
print(max(vals)-min(vals))
PY
)"
        if awk -v s="${spread}" -v m="${PLUG_STABLE_W}" 'BEGIN { exit !(s <= m) }'; then
          :
        else
          ok=false
          log "Settle: plug spread ${spread}W > ${PLUG_STABLE_W}W"
        fi
      else
        ok=false
      fi
    else
      ok=false
      log "Settle: plug sample failed"
    fi

    if ${ok}; then
      ok_streak=$((ok_streak + 1))
      log "Settle check ${ok_streak}/${SETTLE_CHECKS} OK"
    else
      ok_streak=0
    fi

    (( ok_streak < SETTLE_CHECKS )) && sleep "${SETTLE_INTERVAL}"
  done

  TIME_TO_SETTLED_S=$(( $(date +%s) - start_ts ))
  TIME_TO_SSH_S="${ssh_ts}"
  log "Settled at ${TIME_TO_SETTLED_S}s (SSH at ${ssh_ts}s)"
}

ensure_csv_header() {
  mkdir -p "$(dirname "${CSV_FILE}")"
  if [[ ! -f "${CSV_FILE}" ]]; then
    echo 'timestamp,label,plug_w_median,loadavg1,time_to_ssh_s,time_to_settled_s,guest_hash,cpuidle_max,mem_sleep,aspm_policy,bios,notes' >>"${CSV_FILE}"
  fi
}

append_csv_row() {
  local label="$1"
  local plug="$2"
  local note="${3:-}"
  local metrics hash idle load mem aspm bios
  metrics="$(host_metrics_json)"
  hash="$(guest_inventory_hash)"
  idle="$(cpuidle_max)"
  load="$(pve_ssh "awk '{print \$1}' /proc/loadavg")"
  mem="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("mem_sleep","").strip())' <<<"${metrics}")"
  aspm="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("aspm_policy","").strip())' <<<"${metrics}")"
  bios="$(python3 -c 'import json,sys; print(json.loads(sys.stdin.read()).get("bios","").strip())' <<<"${metrics}")"
  ensure_csv_header
  echo "$(date -u '+%Y-%m-%dT%H:%M:%SZ'),${label},${plug},${load},${TIME_TO_SSH_S},${TIME_TO_SETTLED_S},${hash},${idle},${mem},${aspm},${bios},$(printf '%s' "${note}" | sed 's/,/;/g')" >>"${CSV_FILE}"
  log "Appended CSV: ${label} plug=${plug}W hash=${hash} cpuidle_max=${idle}"
  guest_status_line | sed 's/^/[guests] /'
}

run_measure() {
  local label="$1"
  local note="${2:-}"
  local plug
  plug="$(sample_plug_median)"
  append_csv_row "${label}" "${plug}" "${note}"
  echo "RESULT label=${label} plug_median=${plug}W"
}

diff_labels() {
  local a="$1" b="$2"
  [[ -f "${CSV_FILE}" ]] || die "CSV not found: ${CSV_FILE}"
  python3 - "$a" "$b" "${CSV_FILE}" <<'PY'
import csv, sys
a, b, path = sys.argv[1:4]
rows = {}
with open(path, newline="") as f:
    for row in csv.DictReader(f):
        rows[row["label"]] = row
for label in (a, b):
    if label not in rows:
        raise SystemExit(f"label not found: {label}")
wa = float(rows[a]["plug_w_median"])
wb = float(rows[b]["plug_w_median"])
print(f"{a}: {wa} W")
print(f"{b}: {wb} W")
print(f"delta ({b} - {a}): {wb - wa:+.2f} W")
if rows[a]["guest_hash"] != rows[b]["guest_hash"]:
    print(f"WARNING: guest_hash differs {rows[a]['guest_hash']} vs {rows[b]['guest_hash']}")
PY
}

wait_for_load() {
  local start_ts=$(( $(date +%s) ))
  local ssh_ts=0
  local load_max="${1:-${QUICK_LOAD_MAX}}"
  local interval="${QUICK_LOAD_INTERVAL}"
  local need="${QUICK_LOAD_CHECKS}"
  local ok_streak=0

  log "Wait for SSH, guests, then ${need}x consecutive idle checks (load < ${load_max}, no ZFS maintenance; ${interval}s apart)..."
  until pve_ssh 'true' 2>/dev/null; do sleep 10; done
  ssh_ts=$(( $(date +%s) - start_ts ))
  until pve_ssh 'qm status 101 | grep -q running && qm status 102 | grep -q running && pct status 200 | grep -q running' 2>/dev/null; do
    sleep 10
  done

  while (( ok_streak < need )); do
    if idle_check_pass "${load_max}"; then
      ok_streak=$((ok_streak + 1))
      log "Idle check ${ok_streak}/${need} OK"
    else
      if (( ok_streak > 0 )); then
        log "Idle check reset (load or ZFS/maintenance burst)"
      fi
      ok_streak=0
    fi
    (( ok_streak < need )) && sleep "${interval}"
  done

  TIME_TO_SSH_S="${ssh_ts}"
  TIME_TO_SETTLED_S=$(( $(date +%s) - start_ts ))
  log "Idle settled at ${TIME_TO_SETTLED_S}s (SSH at ${ssh_ts}s, ${need}x load+ZFS idle)"
}

main() {
  local mode="" label="" note="" reboot=false quick=false wait_idle=false
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --baseline|--measure) mode="${1#--}"; shift ;;
      --reboot) reboot=true; shift ;;
      --wait-settle) mode=wait-settle; shift ;;
      --wait-idle) wait_idle=true; shift ;;
      --diff) diff_labels "$2" "$3"; exit 0 ;;
      --quick) quick=true; shift ;;
      --label) label="$2"; shift 2 ;;
      --note) note="$2"; shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) die "Unknown arg: $1" ;;
    esac
  done

  case "${mode}" in
    wait-settle) wait_settled; exit 0 ;;
    baseline|measure)
      [[ -n "${label}" ]] || die "--label required"
      if ${reboot}; then
        log "Rebooting ${PVE_HOST}..."
        local t0
        t0=$(date +%s)
        pve_ssh 'nohup systemctl reboot >/dev/null 2>&1 &' || true
        sleep 30
        if ${quick}; then
          wait_for_load "${QUICK_LOAD_MAX}"
        else
          wait_settled
        fi
        TIME_TO_SETTLED_S=$(( $(date +%s) - t0 ))
      fi
      if ${wait_idle}; then
        wait_for_load "${QUICK_LOAD_MAX}"
      fi
      run_measure "${label}" "${note}"
      ;;
    "")
      usage; exit 1 ;;
    *)
      die "Unknown mode: ${mode}" ;;
  esac
}

main "$@"
