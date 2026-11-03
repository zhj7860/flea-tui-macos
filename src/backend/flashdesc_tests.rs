// Layer 6's decision over a fake tree: a volume built on the target dirties it however it is named.
use super::*;
use crate::backend::flashfake::*;

// The stick's own numbers: sda is 8:0, rdev 0x800, with the bytes and diskseq flashfake writes.
const STICK_RDEV: u64 = 0x800;
const STICK_BYTES: u64 = 124_623_257_600;
const STICK_SEQ: u64 = 2;

fn stick_req() -> FlashReq {
    FlashReq { id: 1, image: String::new(), dev: "sda".to_string(), seq: STICK_SEQ, serial: String::new(), bytes: STICK_BYTES }
}

fn stick_facts() -> Facts {
    Facts { block: true, rdev: STICK_RDEV, size: Some(STICK_BYTES), seq: Some(STICK_SEQ) }
}

// The stick with LUKS on sda1 opened as dm-1: the slave link on dm-1, and the kernel's holder link on sda1 when held.
fn opened_stick(tag: &str, held: bool) -> Fake {
    let f = fake(tag);
    stick(&f.sys);
    std::fs::write(f.sys.join("block/sda/dev"), "8:0\n").unwrap();
    mapped(&f, "luks-x", "dm-1", "254:1", &["sda1"]);
    std::fs::create_dir_all(f.sys.join("block/sda/sda1/holders")).unwrap();
    if held {
        std::fs::write(f.sys.join("block/sda/sda1/holders/dm-1"), "").unwrap();
    }
    f
}

#[test]
fn a_clean_stick_passes_layer_six() {
    let f = fake("flashdesc-clean");
    stick(&f.sys);
    std::fs::write(f.sys.join("block/sda/dev"), "8:0\n").unwrap();
    assert_eq!(decide(Some(&stick_facts()), &stick_req(), (&f.sys, &f.dev), &root_mountinfo(), NO_SWAPS, true), Ok(()));
}

// A-r2 F21: a mapper volume on a partition of the target, mounted under its own name, is a mount on the target.
#[test]
fn a_mounted_mapper_volume_on_the_target_is_changed() {
    let f = opened_stick("flashdesc-mapper", false);
    let info = format!("{}40 1 254:1 / /run/media/u/x rw - ext4 /dev/mapper/luks-x rw\n", root_mountinfo());
    assert_eq!(decide(Some(&stick_facts()), &stick_req(), (&f.sys, &f.dev), &info, NO_SWAPS, true), Err("changed"));
}

// A-r2 F21: a dm or md device still holding a partition of the target is refused even with nothing mounted.
#[test]
fn a_holder_on_the_target_is_changed_with_nothing_mounted() {
    let f = opened_stick("flashdesc-holder", true);
    assert_eq!(decide(Some(&stick_facts()), &stick_req(), (&f.sys, &f.dev), &root_mountinfo(), NO_SWAPS, true), Err("changed"));
}

// The control for the two above: the same mapped stick, neither held nor mounted, passes, so the refusal is the holder's.
#[test]
fn a_mapped_stick_with_no_holder_and_no_mount_passes() {
    let f = opened_stick("flashdesc-unheld", false);
    assert_eq!(decide(Some(&stick_facts()), &stick_req(), (&f.sys, &f.dev), &root_mountinfo(), NO_SWAPS, true), Ok(()));
}

// A-r2 F21: swap on a mapper volume of the target is swap on the target.
#[test]
fn swap_on_a_mapper_volume_of_the_target_is_changed() {
    let f = opened_stick("flashdesc-swap", false);
    let swaps = format!("{NO_SWAPS}/dev/dm-1 partition 1 0 -2\n");
    assert_eq!(decide(Some(&stick_facts()), &stick_req(), (&f.sys, &f.dev), &root_mountinfo(), &swaps, true), Err("changed"));
}

// Threat F4: each fact the descriptor answers, changed on its own, is changed; an unreadable one is too.
#[test]
fn each_descriptor_fact_changed_on_its_own_is_changed() {
    let f = fake("flashdesc-facts");
    stick(&f.sys);
    std::fs::write(f.sys.join("block/sda/dev"), "8:0\n").unwrap();
    let roots = (f.sys.as_path(), f.dev.as_path());
    let changed = [
        Facts { block: false, ..stick_facts() },
        Facts { rdev: STICK_RDEV + 1, ..stick_facts() },
        Facts { size: Some(STICK_BYTES - 512), ..stick_facts() },
        Facts { size: None, ..stick_facts() },
        Facts { seq: Some(STICK_SEQ + 1), ..stick_facts() },
        Facts { seq: None, ..stick_facts() },
    ];
    for facts in &changed {
        assert_eq!(decide(Some(facts), &stick_req(), roots, &root_mountinfo(), NO_SWAPS, true), Err("changed"), "{}", majmin(facts.rdev));
    }
    assert_eq!(decide(None, &stick_req(), roots, &root_mountinfo(), NO_SWAPS, true), Err("changed"), "a failed fstat refuses");
}

// Layer 6 refuses a descriptor without O_DIRECT; decide takes the flag because no unprivileged test can fabricate a block node.
#[test]
fn a_block_descriptor_without_o_direct_is_refused() {
    let f = fake("flashdesc-nodirect");
    stick(&f.sys);
    std::fs::write(f.sys.join("block/sda/dev"), "8:0\n").unwrap();
    let roots = (f.sys.as_path(), f.dev.as_path());
    assert_eq!(decide(Some(&stick_facts()), &stick_req(), roots, &root_mountinfo(), NO_SWAPS, false), Err("changed"));
    assert_eq!(decide(Some(&stick_facts()), &stick_req(), roots, &root_mountinfo(), NO_SWAPS, true), Ok(()));
}

// A prefix twin is another disk, nvme0n10 beside nvme0n1 the way the listing's c11 splits them.
#[test]
fn a_prefix_twin_is_not_a_partition_of_the_target() {
    let f = fake("flashdesc-twin");
    let roots = (&f.sys, &f.dev);
    assert!(mounts_clean("nvme0n1", "28 1 259:12 / / rw - ext4 /dev/nvme0n10p2 rw\n", NO_SWAPS, roots.0, roots.1), "nvme0n10p2 rests on nvme0n10, never nvme0n1");
    assert!(mounts_clean("loop1", "28 1 7:10 / / rw - ext4 /dev/loop10 rw\n", NO_SWAPS, roots.0, roots.1), "loop10 is another disk beside loop1");
    assert!(!mounts_clean("nvme0n1", "28 1 259:1 / / rw - ext4 /dev/nvme0n1p1 rw\n", NO_SWAPS, roots.0, roots.1), "nvme0n1p1 still dirties nvme0n1");
    assert!(!mounts_clean("sda", "28 1 8:1 / / rw - ext4 /dev/sda1 rw\n", NO_SWAPS, roots.0, roots.1), "sda1 still dirties sda");
}
