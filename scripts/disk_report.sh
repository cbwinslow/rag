#!/usr/bin/env bash
set -euo pipefail

# disk_report.sh
# Collect storage and disk configuration details from local or remote host (via SSH)
# Produces a plain-text report and attempts a small summary of candidate disks with spare/unpartitioned space

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
OUT_DIR="$(pwd)"

show_help(){
  cat <<EOF
Usage: $0 [options]

Options:
  --host <host>            Remote host (IP or hostname). If omitted, runs locally.
  --user <user>            SSH user (default: current user)
  --ssh-key <path>         SSH private key to use
  --port <port>            SSH port (default 22)
  --output <file>         Output report filename (defaults to disk-report-<host|local>-TIMESTAMP.txt)
  -h, --help               Show this help

Example (Zerotier IP):
  ./scripts/disk_report.sh --host 10.147.17.42 --user root --ssh-key ~/.ssh/id_rsa --output /tmp/remote-disk-report.txt

The script runs several commands remotely (or locally) to collect: lsblk, df, parted (free), LVM status, ZFS pools, top-level du summary, and device IDs.
EOF
}

HOST=""
USER=""
SSH_KEY=""
PORT=22
OUTFILE=""
ANSIBLE=false
INVENTORY_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --user) USER="$2"; shift 2;;
    --ssh-key) SSH_KEY="$2"; shift 2;;
    --port) PORT="$2"; shift 2;;
    --output) OUTFILE="$2"; shift 2;;
    --ansible) ANSIBLE=true; shift;;
    -h|--help) show_help; exit 0;;
    *) echo "Unknown arg: $1"; show_help; exit 2;;
  esac
done

TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LABEL="local"
if [ -n "$HOST" ]; then LABEL="$HOST"; fi
if [ -z "$OUTFILE" ]; then OUTFILE="$OUT_DIR/disk-report-$LABEL-$TIMESTAMP.txt"; fi

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -p $PORT"
if [ -n "$SSH_KEY" ]; then SSH_OPTS="$SSH_OPTS -i $SSH_KEY"; fi

SSH_PREFIX=""
if [ -n "$HOST" ]; then
  if [ -z "$USER" ]; then USER=$(whoami); fi
  SSH_PREFIX=(ssh $SSH_OPTS "$USER@$HOST")
fi

echo "Generating disk report for ${HOST:-local} -> $OUTFILE"

TMPOUT=$(mktemp)
cleanup(){ rm -f "$TMPOUT" || true; }
trap cleanup EXIT

run_remote_cmd(){
  local cmd="$1"
  if [ -n "$HOST" ]; then
    ssh $SSH_OPTS "$USER@$HOST" "$cmd"
  else
    bash -c "$cmd"
  fi
}

if [ "$ANSIBLE" = true ]; then
  if ! command -v ansible-playbook >/dev/null 2>&1; then
    echo "ansible-playbook not found; please install ansible-core" >&2
    exit 2
  fi
  # Prepare inventory
  if [ -n "$HOST" ]; then
    INVENTORY_FILE=$(mktemp)
    echo "$HOST" > "$INVENTORY_FILE"
    echo "Running ansible disk report against $HOST"
    ansible-playbook -i "$INVENTORY_FILE," scripts/ansible/disk_report.yaml
    rm -f "$INVENTORY_FILE"
  else
    echo "ANSIBLE mode requires --host to target a remote host" >&2
    exit 2
  fi
  echo "Ansible playbook completed. Reports (if any) will be in the repo under ./reports/ or /tmp on the remote host." 
  exit 0
fi

cat > "$TMPOUT" <<'EOF'
===SYSTEM===
$(uname -a 2>/dev/null || true)

===LSBLK_JSON===
$(lsblk -b -J 2>/dev/null || true)

===LSBLK_PLAIN===
$(lsblk -o NAME,KNAME,SIZE,TYPE,MOUNTPOINT,MODEL,SERIAL,ROTA 2>/dev/null || true)

===DF===
$(df -hT 2>/dev/null || true)

===BLKID===
$(blkid 2>/dev/null || true)

===PARTED_FREE_SUMMARY===
EOF

# Run parted free for each disk (detect disk names)
if [ -n "$HOST" ]; then
  DISK_NAMES=$(ssh $SSH_OPTS "$USER@$HOST" "lsblk -dn -o NAME,TYPE | awk '\$2==\"disk\"{print \$1}'" 2>/dev/null || true)
else
  DISK_NAMES=$(lsblk -dn -o NAME,TYPE | awk '$2=="disk"{print $1}' 2>/dev/null || true)
fi

for d in $DISK_NAMES; do
  echo "--- parted free on /dev/$d ---" >> "$TMPOUT"
  if [ -n "$HOST" ]; then
    ssh $SSH_OPTS "$USER@$HOST" "parted -s /dev/$d unit B print free" 2>/dev/null >> "$TMPOUT" || true
  else
    parted -s /dev/$d unit B print free 2>/dev/null >> "$TMPOUT" || true
  fi
done

cat >> "$TMPOUT" <<'EOF'

===LVM===
$(pvs 2>/dev/null || true)
$(vgs 2>/dev/null || true)
$(lvs 2>/dev/null || true)

===ZPOOL_STATUS===
$(zpool status 2>/dev/null || true)
$(zpool list 2>/dev/null || true)

===TOP_LEVEL_DU===
$(du -shx /* 2>/dev/null | sort -hr | head -n 40)

===SMARTCTL_SUMMARY===
EOF

# collect smartctl info for disks if available
for d in $DISK_NAMES; do
  echo "--- smartctl -H /dev/$d ---" >> "$TMPOUT"
  if command -v smartctl >/dev/null 2>&1; then
    if [ -n "$HOST" ]; then
      ssh $SSH_OPTS "$USER@$HOST" "smartctl -H /dev/$d" 2>/dev/null >> "$TMPOUT" || true
    else
      smartctl -H /dev/$d 2>/dev/null >> "$TMPOUT" || true
    fi
  else
    echo "smartctl not installed" >> "$TMPOUT"
  fi
done

# Candidate disk analysis: look for disks with no partitions and large size
echo "\n===CANDIDATE_DISKS===\n" >> "$TMPOUT"
for d in $DISK_NAMES; do
  if [ -n "$HOST" ]; then
    info=$(ssh $SSH_OPTS "$USER@$HOST" "lsblk -b -dn -o NAME,SIZE,TYPE,MOUNTPOINT /dev/$d 2>/dev/null | awk '{print \$2, \$3, \$4}'" 2>/dev/null || true)
  else
    info=$(lsblk -b -dn -o NAME,SIZE,TYPE,MOUNTPOINT /dev/$d 2>/dev/null | awk '{print $2, $3, $4}' || true)
  fi
  size=$(echo "$info" | awk '{print $1}')
  type=$(echo "$info" | awk '{print $2}')
  mnt=$(echo "$info" | awk '{print $3}')
  parts_count=0
  if [ -n "$HOST" ]; then
    parts_count=$(ssh $SSH_OPTS "$USER@$HOST" "lsblk -n /dev/$d -o TYPE | grep -c part" 2>/dev/null || true)
  else
    parts_count=$(lsblk -n /dev/$d -o TYPE | grep -c part 2>/dev/null || true)
  fi
  # Consider candidate if no partitions and size > 50GB
  if [ "$parts_count" -eq 0 ]; then
    human_size=$(numfmt --to=iec-i --suffix=B $size 2>/dev/null || echo "$size")
    echo "/dev/$d size=$human_size partitions=$parts_count mount=$mnt" >> "$TMPOUT"
  fi
done

# final: append some runtime facts
cat >> "$TMPOUT" <<EOF

===RUNTIME_NOTES===
Report generated: $TIMESTAMP
Host: ${HOST:-local}
EOF

# move temporary to final
mv "$TMPOUT" "$OUTFILE"

echo "Report written to $OUTFILE"

exit 0