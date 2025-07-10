# Longhorn Node Re-integration: What Worked and What Didn't

## Issues Identified
- Node CR for `k3s1` remained present in Longhorn after stuck volumes/finalizers were removed.
- Node CR had empty disk UUIDs and lingering scheduled replicas.
- Previous attempts at removal (finalizer patch, manager restart) did not succeed.
- Disk wipe commands failed initially due to disks being busy/mounted.

## What Didn't Work
- Removing the finalizer from the Node CR (`kubectl patch ...`) did not remove the node.
- Restarting the Longhorn manager pod did not remove the node.
- Disk wipe commands failed while disks were still mounted or in use.
- Attempting to format a partition before creating it resulted in errors.

## What Worked
- Deleting all stuck Longhorn volumes and removing their finalizers.
- Forcibly deleting the Node CR (`kubectl delete --force --grace-period=0 ...`) finally removed the node from Longhorn.
- Unmounting disks and running `partprobe` before wiping allowed for successful disk zapping and re-partitioning.
- Creating a new GPT partition and primary partition with `parted` before formatting.
- Formatting partitions as ext4 and mounting them to the correct mount points.
- Creating a valid `longhorn-disk.cfg` containing `{}` on each disk.

## Lessons Learned
- Node CR removal may require force deletion even after all volumes and finalizers are gone.
- Always unmount disks and run `partprobe` before attempting to wipe or re-partition.
- Partition creation must precede formatting.
- GitOps-driven re-addition is only reliable after a truly clean node and disk state.

## Next Steps
- Re-add Node CR YAML in Git and let Flux/Longhorn re-register the node and disks.
- Verify disk UUIDs and healthy volume attachment.
