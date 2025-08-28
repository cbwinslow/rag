Disk report helper

This script helps collect storage/disk/partition information from a local or remote host (via SSH). It's useful for proxmox or other servers where you need to decide which drive has spare/unpartitioned space.

scripts/disk_report.sh usage:

```bash
chmod +x scripts/disk_report.sh
./scripts/disk_report.sh --host <ZEROTIER_IP> --user root --ssh-key ~/.ssh/id_rsa --output /tmp/proxmox-disk-report.txt
```

What it collects:
- `lsblk` (JSON + plain)
- `df -hT`
- `blkid`
- `parted unit B print free` per disk
- `pvs`, `vgs`, `lvs` for LVM
- `zpool status` and `zpool list` for ZFS
- Top-level `du -shx /*` summary
- `smartctl -H` per disk (if smartctl present)
- A candidate disk list showing disks with zero partitions (likely free) and their sizes

Notes:
- The script uses SSH and rsync options that disable strict host key checking for convenience; remove those if you want stricter SSH handling.
- It excludes large dataset files from rsync in the repo-deploy flows to avoid copying big files.
