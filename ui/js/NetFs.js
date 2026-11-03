.pragma library

// One shared list of network filesystem types for Cloud.js and the Rust netfs module.
// Sample input: "fuse.sshfs" trues, "ext4" falses, "NFS4" trues, "fuse.portal" falses.
function isNetworkFstype(fstype) {
    if (isCifsFstype(fstype))
        return true
    switch (String(fstype || "").toLowerCase()) {
    case "nfs": case "nfs4": case "9p": case "afs":
    case "ceph": case "davfs": case "fuse.sshfs": case "fuse.rclone": case "fuse.s3fs":
    case "fuse.gcsfuse": case "fuse.curlftpfs": case "fuse.juicefs": case "fuse.glusterfs":
    case "fuse.ceph-fuse": case "fuse.smbnetfs": case "fuse.davfs2": case "fuse.gvfsd-fuse":
    case "fuse.protondrive":
        return true
    }
    return false
}

// RailEject callout 2: SMB-family fstypes draw the mark, the rest keep their square.
function isCifsFstype(fstype) {
    switch (String(fstype || "").toLowerCase()) {
    case "cifs": case "smb2": case "smb3": case "smbfs":
        return true
    }
    return false
}
