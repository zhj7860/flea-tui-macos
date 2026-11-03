// One shared list of network filesystem types for extclass, jump, iomount and ui/js/NetFs.js.
// Sample input: "fuse.sshfs" trues, "ext4" falses, "NFS4" trues, "fuse.portal" falses.
const NETWORK_FSTYPES: &[&str] = &[
    "nfs", "nfs4", "cifs", "smb2", "smb3", "smbfs", "9p", "afs", "ceph", "davfs",
    "fuse.sshfs", "fuse.rclone", "fuse.s3fs", "fuse.gcsfuse", "fuse.curlftpfs",
    "fuse.juicefs", "fuse.glusterfs", "fuse.ceph-fuse", "fuse.smbnetfs",
    "fuse.davfs2", "fuse.gvfsd-fuse", "fuse.protondrive",
];

pub fn is_network_fstype(fstype: &str) -> bool {
    // Exact matches only, so local FUSE mounts and the server proc never read as remote.
    NETWORK_FSTYPES.iter().any(|kind| kind.eq_ignore_ascii_case(fstype))
}

// A filesystem whose stat can wedge: the shared network list plus any FUSE mount, block-backed fuseblk (ntfs-3g) included.
pub fn can_wedge(kind: &str) -> bool {
    is_network_fstype(kind) || kind == "fuse" || kind == "fuseblk" || kind.starts_with("fuse.")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_shared_list_names_each_network_kind_once() {
        for fstype in ["nfs", "nfs4", "NFS", "cifs", "smb2", "smb3", "smbfs", "9p", "afs", "ceph", "davfs", "fuse.sshfs", "fuse.rclone", "fuse.s3fs", "fuse.gcsfuse", "fuse.curlftpfs", "fuse.juicefs", "fuse.glusterfs", "fuse.ceph-fuse", "fuse.smbnetfs", "fuse.davfs2", "fuse.gvfsd-fuse", "fuse.protondrive"] {
            assert!(is_network_fstype(fstype), "{} is network", fstype);
        }
        for fstype in ["ext4", "btrfs", "xfs", "vfat", "exfat", "ntfs", "ntfs3", "tmpfs", "overlay", "fuse", "fuseblk", "fuse.portal", "fuse.mergerfs", "fuse.gocryptfs", "fuse.bindfs", "fuse.squashfuse", "fuse.lxcfs", "nfsd", "sshfs", "s3fs", "davfs2", "glusterfs", "iso9660", "udf", ""] {
            assert!(!is_network_fstype(fstype), "{} stays local", fstype);
        }
    }

    // Sample input: `case "nfs":` labels, one per line or several per line, lower or any case.
    fn netfs_js_labels(text: &str) -> Vec<String> {
        let mut out = Vec::new();
        for chunk in text.split("case ") {
            let label = chunk.trim_start().strip_prefix('"').and_then(|rest| rest.split('"').next());
            if let Some(label) = label {
                if !label.is_empty() {
                    out.push(label.to_ascii_lowercase());
                }
            }
        }
        out.sort();
        out.dedup();
        out
    }

    // Sample input: "fuseblk" is ntfs-3g's daemon on a local disk, whose hang wedges a stat like any FUSE daemon's.
    #[test]
    fn any_fuse_daemon_can_wedge_and_a_kernel_filesystem_cannot() {
        for kind in ["fuse", "fuseblk", "fuse.mergerfs", "fuse.portal", "nfs4", "cifs"] {
            assert!(can_wedge(kind), "{} can wedge", kind);
        }
        for kind in ["ext4", "btrfs", "vfat", "exfat", "ntfs3", "tmpfs", "nfsd", "fusectl", ""] {
            assert!(!can_wedge(kind), "{} stays inline", kind);
        }
    }

    #[test]
    fn the_js_list_matches_the_rust_list() {
        let js = netfs_js_labels(include_str!("../../ui/js/NetFs.js"));
        let mut rust: Vec<String> = NETWORK_FSTYPES.iter().map(|kind| kind.to_string()).collect();
        rust.sort();
        assert_eq!(js, rust, "ui/js/NetFs.js case labels drifted from netfs.rs");
    }
}
