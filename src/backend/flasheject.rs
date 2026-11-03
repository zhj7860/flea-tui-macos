// The flasheject answer: a bare kernel disk the listing offers, then the helper, never a system disk or a path.
use crate::backend::flash::flasheject_line;
use crate::backend::flasheligible::{list_drives, roots_for_production, Roots};
use crate::backend::flashdesc::{disk_seq, gone};
use crate::backend::flashop::answer;
use std::path::Path;

// A kernel disk name is short and plain, so a slash or a dot never reaches a sysfs path.
const DEV_NAME_MAX: usize = 32;

// Sample names: "sda", "nvme0n1" and "mmcblk0" pass; "sda/../sdb", "..", "" and "a b" do not.
fn bare_kernel_name(dev: &str) -> bool {
    !dev.is_empty() && dev.len() <= DEV_NAME_MAX && dev.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

// Eject through the helper; the rail's own lsblk verdict still writes the sentence the user reads.
pub fn handle_flasheject(out: &mut dyn std::io::Write, dev: &str, seq: u64) {
    let (exe, ui) = roots_for_production();
    let loop_root = crate::backend::flasheligible::seam_root();
    let roots = Roots { sys: Path::new("/sys"), dev: Path::new("/dev"), exe: &exe, ui: &ui, loop_root: loop_root.as_deref() };
    let mountinfo = std::fs::read_to_string("/proc/self/mountinfo").unwrap_or_default();
    let swaps = std::fs::read_to_string("/proc/swaps").unwrap_or_default();
    eject_with(out, dev, seq, &roots, (&mountinfo, &swaps), &mut crate::backend::flashhelper::eject);
}

// The eject decision over caller-supplied roots and helper, so a test never reaches a real drive.
pub(crate) fn eject_with(out: &mut dyn std::io::Write, dev: &str, seq: u64, roots: &Roots, tables: (&str, &str), eject: &mut dyn FnMut(&str) -> Result<(), String>) {
    let refuse = |out: &mut dyn std::io::Write, err: &str| answer(out, &flasheject_line(false, err));
    if !bare_kernel_name(dev) {
        return refuse(out, "error");
    }
    if gone(roots.sys, dev) {
        return refuse(out, "gone");
    }
    if disk_seq(roots.sys, dev) != Some(seq) {
        return refuse(out, "changed");
    }
    // Listed means a removable disk no layer excludes, so a system disk never reaches the helper.
    if !list_drives(roots, tables.0, tables.1, None, None).iter().any(|d| d.dev == dev) {
        return refuse(out, "error");
    }
    match eject(dev) {
        Ok(()) => answer(out, &flasheject_line(true, "")),
        Err(err) => refuse(out, &err),
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn only_a_bare_kernel_name_passes() {
        for good in ["sda", "nvme0n1", "mmcblk0", "dm-0", "sdz9"] {
            assert!(bare_kernel_name(good), "{good}");
        }
        for bad in ["", "..", ".", "sda/../sdb", "../block/sda", "/dev/sda", "a b", "sd\0a", &"x".repeat(DEV_NAME_MAX + 1)] {
            assert!(!bare_kernel_name(bad), "{bad:?}");
        }
    }
}
