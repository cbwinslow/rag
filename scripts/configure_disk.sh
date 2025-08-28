#!/usr/bin/env bash
set -euo pipefail

# configure_disk.sh
# Safely assist with configuring a disk for use as a physical disk, an LVM PV (and optionally VG/LV), or create a filesystem and mount it.
# The script is interactive by default and does a dry-run unless --apply is passed.

usage(){
  cat <<EOF
Usage: $0 [options]

Options:
  --host <host>           Remote SSH host (if omitted, runs locally)
  --user <user>           SSH user for remote (default current user)
  --ssh-key <path>        SSH private key for remote connection
  --disk /dev/sdX         Target whole-disk device to configure (required)
  --vg-name NAME          Name of VG to create or extend
  --lv-name NAME          Name of LV to create (optional)
  --lv-size SIZE          Size for new LV (eg 50G). Required when --lv-name used
  --mount-point PATH      Mount point for filesystem (defaults to /mnt/<lv|disk>)
  --fs-type TYPE          Filesystem type (xfs|ext4) default xfs
  --wipe                  Wipe existing signatures on disk (destructive) - requires --apply
  --apply                 Actually perform actions (otherwise prints planned commands)
  -h, --help              Show this help

Examples:
  # Dry-run show commands to create PV and VG on /dev/sdb locally
  ./scripts/configure_disk.sh --disk /dev/sdb --vg-name data

  # Create LV 100G, format as xfs and mount when ready (must pass --apply)
  ./scripts/configure_disk.sh --disk /dev/sdc --vg-name data --lv-name data01 --lv-size 100G --mount-point /data/data01 --apply

Remote usage (SSH):
  ./scripts/configure_disk.sh --host 10.147.17.42 --user root --ssh-key ~/.ssh/id_rsa --disk /dev/sdb --vg-name data --apply

This script is potentially destructive. Read the printed plan carefully before using --apply.
EOF
}

HOST=""
USER=""
SSH_KEY=""
DISK=""
VG_NAME=""
LV_NAME=""
LV_SIZE=""
MOUNT_POINT=""
FS_TYPE="xfs"
WIPE=false
APPLY=false
ANSIBLE=false
INVENTORY=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --host) HOST="$2"; shift 2;;
    --user) USER="$2"; shift 2;;
    --ssh-key) SSH_KEY="$2"; shift 2;;
    --disk) DISK="$2"; shift 2;;
    --vg-name) VG_NAME="$2"; shift 2;;
    --lv-name) LV_NAME="$2"; shift 2;;
    --lv-size) LV_SIZE="$2"; shift 2;;
    --mount-point) MOUNT_POINT="$2"; shift 2;;
    --fs-type) FS_TYPE="$2"; shift 2;;
    --wipe) WIPE=true; shift;;
    --apply) APPLY=true; shift;;
  --ansible) ANSIBLE=true; shift;;
    -h|--help) usage; exit 0;;
    *) echo "Unknown arg: $1"; usage; exit 2;;
  esac
done

if [ -z "$DISK" ]; then
  echo "Error: --disk is required" >&2; usage; exit 2
fi

if [ -n "$HOST" ] && [ -z "$USER" ]; then USER=$(whoami); fi

SSH_OPTS="-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null"
if [ -n "$SSH_KEY" ]; then SSH_OPTS="$SSH_OPTS -i $SSH_KEY"; fi

run(){
  cmd="$1"
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
  if [ -z "$HOST" ]; then echo "--ansible requires --host to target"; exit 2; fi
  INV=$(mktemp)
  echo "$HOST" > "$INV"
  EXTRA_VARS=("target_disk=$DISK")
  if [ -n "$VG_NAME" ]; then EXTRA_VARS+=("vg_name=$VG_NAME"); fi
  if [ -n "$LV_NAME" ]; then EXTRA_VARS+=("lv_name=$LV_NAME" "lv_size=$LV_SIZE"); fi
  if [ "$APPLY" = true ]; then EXTRA_VARS+=("do_apply=true"); fi
  ansible-playbook -i "$INV," scripts/ansible/configure_disk.yaml --extra-vars "${EXTRA_VARS[*]}"
  rm -f "$INV"
  exit 0
fi

echo "Preparing plan for disk: $DISK"

# Basic validations
run "lsblk -o NAME,SIZE,TYPE,MOUNTPOINT $DISK || true"

PLAN=()

if [ "$WIPE" = true ]; then
  PLAN+=("sgdisk --zap-all $DISK   # wipes partition table and signatures (destructive)")
  PLAN+=("wipefs -a $DISK          # remove filesystem signatures")
fi

# create PV
PLAN+=("pvcreate -ff -y $DISK")

if [ -n "$VG_NAME" ]; then
  # check if VG exists remotely
  if [ -n "$HOST" ]; then
    vg_exists=$(ssh $SSH_OPTS "$USER@$HOST" "vgs --noheadings -o vg_name 2>/dev/null | grep -w $VG_NAME || true")
  else
    vg_exists=$(vgs --noheadings -o vg_name 2>/dev/null | grep -w "$VG_NAME" || true)
  fi
  if [ -z "$vg_exists" ]; then
    PLAN+=("vgcreate $VG_NAME $DISK")
  else
    PLAN+=("vgextend $VG_NAME $DISK")
  fi
fi

if [ -n "$LV_NAME" ]; then
  if [ -z "$LV_SIZE" ]; then
    echo "--lv-size is required when creating --lv-name" >&2; exit 2
  fi
  PLAN+=("lvcreate -n $LV_NAME -L $LV_SIZE $VG_NAME")
  # create filesystem and mount
  if [ -z "$MOUNT_POINT" ]; then
    MOUNT_POINT="/mnt/$LV_NAME"
  fi
  if [ "$FS_TYPE" = "xfs" ]; then
    PLAN+=("mkfs.xfs /dev/$VG_NAME/$LV_NAME")
  else
    PLAN+=("mkfs.ext4 /dev/$VG_NAME/$LV_NAME")
  fi
  PLAN+=("mkdir -p $MOUNT_POINT && mount /dev/$VG_NAME/$LV_NAME $MOUNT_POINT")
  PLAN+=("echo '/dev/$VG_NAME/$LV_NAME $MOUNT_POINT $FS_TYPE defaults 0 0' >> /etc/fstab")
else
  # If no LV, create filesystem directly on disk and mount
  if [ -z "$MOUNT_POINT" ]; then
    MOUNT_POINT="/mnt/$(basename $DISK)"
  fi
  if [ "$FS_TYPE" = "xfs" ]; then
    PLAN+=("mkfs.xfs -f $DISK")
  else
    PLAN+=("mkfs.ext4 -F $DISK")
  fi
  PLAN+=("mkdir -p $MOUNT_POINT && mount $DISK $MOUNT_POINT")
  PLAN+=("echo '$DISK $MOUNT_POINT $FS_TYPE defaults 0 0' >> /etc/fstab")
fi

echo "Planned actions (dry-run):"
for c in "${PLAN[@]}"; do echo "  $c"; done

if [ "$APPLY" != true ]; then
  echo "\nNo changes applied. Re-run with --apply to execute the plan (this is destructive)."
  exit 0
fi

echo "Applying plan..."
for c in "${PLAN[@]}"; do
  echo "Running: $c"
  run "$c"
done

echo "Done. Verify with: lsblk; pvs; vgs; lvs; df -h"

exit 0
