#!/usr/bin/env bash
set -euo pipefail

# mount_bitlocker.sh - decrypt & mount a BitLocker partition using dislocker
# Usage examples:
#   ./mount_bitlocker.sh -d /dev/sdb1
#   ./mount_bitlocker.sh -d /dev/sdb1 -u "MyPassword"
#   ./mount_bitlocker.sh -d /dev/sdb1 -p "111111-222222-..." -m /mnt/win
#   ./mount_bitlocker.sh -d /dev/sdb1 -k /path/to/BEKfile
#   ./mount_bitlocker.sh --unmount -d /dev/sdb1

PROG="$(basename "$0")"

usage() {
  cat <<EOF
$PROG - mount a BitLocker-encrypted device on Linux (requires dislocker)

Options:
  -d, --device DEVICE        Block device (e.g. /dev/sdb1)  (required)
  -m, --mount DIR            Mount point for the decrypted filesystem (default: /mnt/bitlocker_<devname>)
  -r, --raw DIR              dislocker raw output directory (default: /mnt/bitlocker_raw_<devname>)
  -u, --password PASSWORD    Unlock with user password
  -p, --recovery PASSWORD    Unlock with 48-digit recovery password (use quotes or no-dashes)
  -k, --bek FILE             Unlock with BEK file (path)
  --readonly                 Mount the filesystem read-only
  --unmount                  Unmount and cleanup (reverse of mount)
  -h, --help                 Show this help
EOF
  exit 1
}

DEVICE=""
MOUNT_DIR=""
RAW_DIR=""
PASSWORD=""
RECOVERY=""
BEK=""
READONLY=false
ACTION="mount"

while [[ $# -gt 0 ]]; do
  case "$1" in
    -d|--device) DEVICE="$2"; shift 2;;
    -m|--mount) MOUNT_DIR="$2"; shift 2;;
    -r|--raw) RAW_DIR="$2"; shift 2;;
    -u|--password) PASSWORD="$2"; shift 2;;
    -p|--recovery) RECOVERY="$2"; shift 2;;
    -k|--bek) BEK="$2"; shift 2;;
    --readonly) READONLY=true; shift;;
    --unmount) ACTION="unmount"; shift;;
    -h|--help) usage;;
    *) echo "Unknown arg: $1"; usage;;
  esac
done

if [[ -z "$DEVICE" ]]; then
  echo "Error: device is required (-d /dev/sdXn)"; usage
fi

if [[ ! -b "$DEVICE" ]]; then
  echo "Error: device does not exist or is not a block device: $DEVICE"; exit 2
fi

DEVNAME="$(basename "$DEVICE" | tr -cd '[:alnum:]_')"
: "${RAW_DIR:=/mnt/bitlocker_raw_${DEVNAME}}"
: "${MOUNT_DIR:=/mnt/bitlocker_${DEVNAME}}"

log(){ printf '%s %s\n' "$(date +'%Y-%m-%dT%H:%M:%S')" "$*"; }

ensure_dislocker(){
  if ! command -v dislocker >/dev/null 2>&1; then
    log "dislocker not found. Attempting to install (apt/dnf)..."
    if command -v apt >/dev/null 2>&1; then
      sudo apt update && sudo apt install -y dislocker
    elif command -v dnf >/dev/null 2>&1; then
      sudo dnf install -y dislocker
    else
      log "Package manager not detected. Please install 'dislocker' manually."
      exit 3
    fi
  fi
}

cleanup_mounts(){
  if mountpoint -q "$MOUNT_DIR"; then
    log "Unmounting $MOUNT_DIR"
    sudo umount "$MOUNT_DIR" || sudo fusermount -uz "$MOUNT_DIR" || true
  fi
  if mountpoint -q "$RAW_DIR"; then
    log "Unmounting dislocker (raw) at $RAW_DIR"
    sudo fusermount -u "$RAW_DIR" || sudo umount "$RAW_DIR" || true
  fi
  if [[ "$RAW_DIR" == /mnt/* ]]; then sudo rmdir --ignore-fail-on-non-empty "$RAW_DIR" 2>/dev/null || true; fi
  if [[ "$MOUNT_DIR" == /mnt/* ]]; then sudo rmdir --ignore-fail-on-non-empty "$MOUNT_DIR" 2>/dev/null || true; fi
}

trap 'log "Interrupted, cleaning up..."; cleanup_mounts; exit 1' INT TERM

if [[ "$ACTION" == "unmount" ]]; then
  log "Unmount action requested for $DEVICE -> raw:$RAW_DIR mount:$MOUNT_DIR"
  cleanup_mounts
  log "Unmount/cleanup complete."
  exit 0
fi

ensure_dislocker

if [[ -n "$PASSWORD" ]]; then
  DISLOCKER_CMD=(dislocker -V "$DEVICE" -u"$PASSWORD" -- "$RAW_DIR")
elif [[ -n "$RECOVERY" ]]; then
  CLEAN_RECOVERY="${RECOVERY//-/}"
  DISLOCKER_CMD=(dislocker -V "$DEVICE" -p"$CLEAN_RECOVERY" -- "$RAW_DIR")
elif [[ -n "$BEK" ]]; then
  if [[ ! -f "$BEK" ]]; then
    echo "BEK file not found: $BEK"; exit 4
  fi
  DISLOCKER_CMD=(dislocker -V "$DEVICE" -k "$BEK" -- "$RAW_DIR")
else
  read -r -s -p "Enter BitLocker password: " PASSWORD
  echo
  DISLOCKER_CMD=(dislocker -V "$DEVICE" -u"$PASSWORD" -- "$RAW_DIR")
fi

sudo mkdir -p "$RAW_DIR" "$MOUNT_DIR"
sudo chown "$USER":"$USER" "$RAW_DIR" "$MOUNT_DIR"

if mountpoint -q "$RAW_DIR"; then
  log "Raw dir $RAW_DIR already mounted"
else
  log "Running: ${DISLOCKER_CMD[*]}"
  sudo "${DISLOCKER_CMD[@]}" &
  sleep 1
fi

DISLOCKER_FILE="$RAW_DIR/dislocker-file"
if [[ ! -e "$DISLOCKER_FILE" ]]; then
  for i in {1..8}; do
    if [[ -e "$DISLOCKER_FILE" ]]; then break; fi
    sleep 1
  done
fi

if [[ ! -e "$DISLOCKER_FILE" ]]; then
  echo "Error: dislocker did not create '$DISLOCKER_FILE'. Check logs and credentials." >&2
  exit 5
fi

MOUNT_OPTS="-o loop"
if [[ "$READONLY" == true ]]; then MOUNT_OPTS="$MOUNT_OPTS,ro"; fi

if mountpoint -q "$MOUNT_DIR"; then
  log "$MOUNT_DIR already mounted"
else
  log "Mounting decrypted filesystem ($DISLOCKER_FILE) -> $MOUNT_DIR"
  sudo mount $MOUNT_OPTS "$DISLOCKER_FILE" "$MOUNT_DIR"
fi

log "Mount successful. Access your files at: $MOUNT_DIR"
log "To unmount: sudo $PROG --unmount -d $DEVICE"
