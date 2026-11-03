// Which disks the system, a swap and a mount rest on, resolved through sysfs in the shapes a real box has.
use crate::backend::flasheligible::{list_drives, Roots};
use crate::backend::flashfake::*;

const GIB: u64 = 1024 * 1024 * 1024;

fn names(f: &Fake, mountinfo: &str, swaps: &str) -> Vec<String> {
    let (exe, ui) = roots();
    let r = Roots { sys: &f.sys, dev: &f.dev, exe: &exe, ui: &ui, loop_root: None };
    list_drives(&r, mountinfo, swaps, None, None).into_iter().map(|d| d.dev).collect()
}

// The system disk made a candidate by its flags, so only the chain under test can hide it.
fn removable_system(f: &Fake) {
    system(&f.sys);
    std::fs::write(f.sys.join("block/nvme0n1/removable"), "1\n").unwrap();
    part(&f.sys, "nvme0n1", "nvme0n1p2", "259:2");
}

fn usb_disk(f: &Fake, dev: &str, part_name: &str, majmin: &str, seq: &str) {
    disk(&f.sys, dev, "1\n", "0\n", 8 * GIB, seq, &format!("/usb3/3-{seq}"));
    identity(&f.sys, dev, "Vendor", "Stick", "");
    if !part_name.is_empty() {
        part(&f.sys, dev, part_name, majmin);
    }
}

#[test]
fn c1_a_btrfs_root_with_an_anonymous_majmin_excludes_its_disk() {
    let f = fake("disk-btrfs");
    removable_system(&f);
    stick(&f.sys);
    mapped(&f, "root", "dm-0", "253:0", &["nvme0n1p2"]);
    let info = "28 1 0:25 /@ / rw - btrfs /dev/mapper/root rw\n";
    assert_eq!(names(&f, info, NO_SWAPS), ["sda"], "the mount source, not the 0:25 anonymous device, names the disk");
}

#[test]
fn c2_lvm_on_luks_follows_every_hop_to_the_disk() {
    let f = fake("disk-lvm");
    removable_system(&f);
    stick(&f.sys);
    mapped(&f, "cryptlvm", "dm-0", "253:0", &["nvme0n1p2"]);
    mapped(&f, "vg-root", "dm-1", "253:1", &["dm-0"]);
    let info = "28 1 253:1 / / rw - ext4 /dev/mapper/vg-root rw\n";
    assert_eq!(names(&f, info, NO_SWAPS), ["sda"], "dm-1 on dm-0 on nvme0n1p2 resolves to nvme0n1");
}

#[test]
fn c2_luks_on_a_whole_mmcblk_excludes_it() {
    let f = fake("disk-mmc");
    system(&f.sys);
    disk(&f.sys, "mmcblk0", "1\n", "0\n", 8 * GIB, "4\n", "/pci0000:00/mmc_host/mmc0");
    identity(&f.sys, "mmcblk0", "", "Card", "");
    stick(&f.sys);
    mapped(&f, "root", "dm-0", "253:0", &["mmcblk0"]);
    let info = "28 1 253:0 / / rw - ext4 /dev/mapper/root rw\n";
    assert_eq!(names(&f, info, NO_SWAPS), ["sda"], "a whole-disk slave is the disk itself, not a trimmed prefix");
}

#[test]
fn c20_a_slave_named_sdp2_resolves_to_sdp() {
    let f = fake("disk-sdp");
    system(&f.sys);
    usb_disk(&f, "sdp", "sdp2", "65:242", "5\n");
    stick(&f.sys);
    mapped(&f, "root", "dm-0", "253:0", &["sdp2"]);
    let info = "28 1 253:0 / / rw - ext4 /dev/mapper/root rw\n";
    assert_eq!(names(&f, info, NO_SWAPS), ["sda"], "sdp2 belongs to sdp, so sdp is the system disk");
}

#[test]
fn c3_a_swap_on_dm_excludes_the_disk_beneath() {
    let f = fake("disk-swapdm");
    system(&f.sys);
    usb_disk(&f, "sdb", "sdb2", "8:34", "6\n");
    stick(&f.sys);
    mapped(&f, "swap", "dm-1", "253:1", &["sdb2"]);
    let swaps = "Filename Type Size Used Priority\n/dev/dm-1 partition 1 0 -2\n";
    assert_eq!(names(&f, &root_mountinfo(), swaps), ["sda"], "a swap on dm-1 over sdb2 hides sdb");
    let named = "Filename Type Size Used Priority\n/dev/mapper/swap partition 1 0 -2\n";
    assert_eq!(names(&f, &root_mountinfo(), named), ["sda"], "the mapper name resolves the same way");
}

#[test]
fn c3_a_swap_on_a_whole_disk_or_a_p_less_partition_excludes_it() {
    let f = fake("disk-swapwhole");
    removable_system(&f);
    usb_disk(&f, "sdp", "sdp2", "65:242", "5\n");
    stick(&f.sys);
    let whole = "Filename Type Size Used Priority\n/dev/nvme0n1 partition 1 0 -2\n";
    assert_eq!(names(&f, &root_mountinfo_without_nvme(), whole), ["sda", "sdp"], "a swap on the whole nvme0n1 hides it");
    let part_swap = "Filename Type Size Used Priority\n/dev/sdp2 partition 1 0 -2\n";
    assert_eq!(names(&f, &root_mountinfo_without_nvme(), part_swap), ["nvme0n1", "sda"], "a swap on sdp2 hides sdp");
}

// A root on a disk the fixtures do not list, so the swap alone decides what is hidden.
fn root_mountinfo_without_nvme() -> String {
    "28 1 9:9 / / rw - ext4 /dev/vdz1 rw\n".to_string()
}

#[test]
fn c3_a_swapfile_excludes_the_disk_of_its_mount() {
    let f = fake("disk-swapfile");
    system(&f.sys);
    usb_disk(&f, "sdb", "sdb1", "8:33", "6\n");
    stick(&f.sys);
    let info = root_mountinfo() + "50 28 8:33 / /data rw - ext4 /dev/sdb1 rw\n";
    let swaps = "Filename Type Size Used Priority\n/data/swapfile file 1 0 -2\n";
    assert_eq!(names(&f, &info, swaps), ["sda"], "the swapfile's mount source is on sdb");
}

#[test]
fn c9_a_usb_disk_that_reports_not_removable_is_listed_by_its_path() {
    let f = fake("disk-usbpath");
    system(&f.sys);
    disk(&f.sys, "sdc", "0\n", "0\n", 8 * GIB, "7\n", "/usb3/3-2/3-2:1.0/host4/target4:0:0");
    identity(&f.sys, "sdc", "Vendor", "Enclosure", "");
    assert_eq!(names(&f, &root_mountinfo(), NO_SWAPS), ["sdc"], "the bus is in the kernel path, not in the relative device link");
}

#[test]
fn c9_an_internal_sata_disk_is_never_listed() {
    let f = fake("disk-sata");
    system(&f.sys);
    disk(&f.sys, "sdd", "0\n", "0\n", 8 * GIB, "8\n", "/pci0000:00/0000:00:17.0/ata1/host0/target0:0:0");
    identity(&f.sys, "sdd", "ATA", "Internal", "");
    assert!(names(&f, &root_mountinfo(), NO_SWAPS).is_empty(), "not removable and no usb, mmc or firewire in its path");
}

#[test]
fn c11_nvme0n10_beside_nvme0n1_keeps_each_disk_apart() {
    let f = fake("disk-nvme10");
    system(&f.sys);
    std::fs::write(f.sys.join("block/nvme0n1/removable"), "1\n").unwrap();
    disk(&f.sys, "nvme0n10", "1\n", "0\n", 8 * GIB, "11\n", "/pci0000:00/nvme1");
    identity(&f.sys, "nvme0n10", "Vendor", "Second", "");
    part(&f.sys, "nvme0n10", "nvme0n10p2", "259:12");
    let info = "28 1 259:12 / / rw - ext4 /dev/nvme0n10p2 rw\n";
    assert_eq!(names(&f, info, NO_SWAPS), ["nvme0n1"], "a root on nvme0n10p2 hides nvme0n10 and never nvme0n1");
}
