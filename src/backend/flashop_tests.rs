// The flash worker's decisions: layer 6, every ending's drive state, the progress totals and the answers.
use super::*;
use crate::backend::flashdesc::{majmin, node_number};
use std::os::unix::fs::MetadataExt;
use crate::backend::flasheject::eject_with;
use crate::backend::flashfake::*;
use crate::backend::flashmeter::Meter;
use crate::backend::flashwrite::Job;
use crate::backend::testdir::TestDir;
use std::sync::mpsc::channel;

// A disk name no sysfs lists, so a failed write reads as gone rather than depending on this box.
const GONE_DEV: &str = "flea-no-such-disk";
const IMAGE_BYTES: usize = 9_000_000;
const DRIVE_BYTES: usize = 16_000_000;
const MIB: usize = 1024 * 1024;
// A pause past the throttle, so the next beat after it is sent.
const PAST_THROTTLE: std::time::Duration = std::time::Duration::from_millis(160);

fn target(dir: &TestDir, name: &str, bytes: usize) -> std::fs::File {
    let file = std::fs::OpenOptions::new().read(true).write(true).create(true).truncate(true).open(dir.join(name)).unwrap();
    file.set_len(bytes as u64).unwrap();
    file
}

fn image(dir: &TestDir, name: &str, bytes: usize, seed: u8) -> std::path::PathBuf {
    let path = dir.join(name);
    let body: Vec<u8> = (0..bytes).map(|n| (n % 251) as u8 ^ seed).collect();
    std::fs::write(&path, &body).unwrap();
    path
}

fn ends_are_zero(dir: &TestDir, name: &str) -> bool {
    let body = std::fs::read(dir.join(name)).unwrap();
    body[..MIB].iter().all(|b| *b == 0) && body[body.len() - MIB..].iter().all(|b| *b == 0)
}

// One raw image flashed by flash_body onto a regular file, with a hook that acts at one phase.
fn raw_flash(tag: &str, hook: impl Fn(&std::path::Path, &AtomicBool, &str) + 'static) -> (TestDir, Ending, Vec<String>) {
    let d = TestDir::new(tag);
    let src = image(&d, "a.img", IMAGE_BYTES, 5);
    let dest = target(&d, "drive.img", DRIVE_BYTES);
    let cancel = AtomicBool::new(false);
    let (tx, rx) = channel::<FlashMsg>();
    let mut meter = Meter::new(1, &tx, true, IMAGE_BYTES as u64, IMAGE_BYTES as u64);
    let path = d.join("drive.img");
    let flag = &cancel;
    meter.hook = Some(Box::new(move |phase, _| hook(&path, flag, phase)));
    let job = Job::new(&src, "img", "", &dest, DRIVE_BYTES as u64, &cancel);
    let end = flash_body(&job, GONE_DEV, &mut meter);
    drop(meter);
    drop(tx);
    (d, end, rx.into_iter().map(|m| m.line).collect())
}

fn flip(path: &std::path::Path, at: u64) {
    use std::io::{Seek, SeekFrom, Write};
    let mut raw = std::fs::OpenOptions::new().write(true).open(path).unwrap();
    raw.seek(SeekFrom::Start(at)).unwrap();
    raw.write_all(&[0xFF]).unwrap();
}

#[test]
fn a_mounted_partition_dirties_the_disk() {
    let (sys, dev) = (std::path::Path::new("/nonexistent-sys"), std::path::Path::new("/nonexistent-dev"));
    let info = "28 1 8:1 / / rw - ext4 /dev/sda1 rw\n";
    assert!(!crate::backend::flashdesc::mounts_clean("sda", info, NO_SWAPS, sys, dev));
    assert!(crate::backend::flashdesc::mounts_clean("sda", "28 1 8:1 / / rw - ext4 /dev/nvme0n1p1 rw\n", NO_SWAPS, sys, dev));
    assert!(!crate::backend::flashdesc::mounts_clean("sda", "28 1 8:1 / / rw - ext4 /dev/nvme0n1p1 rw\n", "Filename Type Size Used Priority\n/dev/sda1 partition 1 0 -2\n", sys, dev));
}

// A2: the regular-file path belongs to the bench seam alone, so a default build refuses a file.
#[cfg(not(feature = "flash-test-seam"))]
#[test]
fn a_regular_file_is_refused_as_a_descriptor() {
    let d = TestDir::new("flashop-regular");
    let path = d.join("drive.img");
    std::fs::write(&path, vec![0u8; 4096]).unwrap();
    let file = std::fs::OpenOptions::new().read(true).write(true).open(&path).unwrap();
    let req = FlashReq { id: 1, image: String::new(), dev: "sda".to_string(), seq: 0, serial: String::new(), bytes: 0 };
    assert_eq!(check_descriptor(&file, &req), Err("changed"));
}

// A1: layer 6 compares st_rdev, the node's own number, never st_dev, the filesystem holding the node.
#[test]
fn layer_six_compares_the_node_rdev_and_not_its_filesystem() {
    assert_eq!(majmin(0x800), "8:0");
    assert_eq!(majmin(0x10300), "259:0");
    assert_eq!(majmin(0x1230_0845), "8:74565", "a minor past 255 spreads over two bit ranges");
    let d = TestDir::new("flashop-rdev");
    let path = d.join("plain.img");
    std::fs::write(&path, b"x").unwrap();
    let meta = std::fs::metadata(&path).unwrap();
    assert_ne!(meta.dev(), 0, "a file lives on a filesystem with a number of its own");
    assert_eq!(node_number(&meta), meta.rdev(), "the number compared is the node's rdev");
}

#[test]
fn a_second_flash_while_one_runs_is_refused() {
    let slot = Slot::new();
    let (tx, _rx) = std::sync::mpsc::channel::<FlashMsg>();
    let mut out = Vec::new();
    let _held = slot.claim(1).unwrap();
    start_flash(&mut out, &slot, &tx, FlashReq { id: 2, image: String::new(), dev: "sda".to_string(), seq: 0, serial: String::new(), bytes: 0 });
    let text = String::from_utf8(out).unwrap();
    assert!(text.contains("\"where\":\"flash\"") && text.contains("already running"), "{text}");
}

// One press on the fake stick (diskseq 2) through a stub helper that opens drive.img for writing: the lines, whether the helper ran, whether drive.img stayed zero.
fn press_on_fake(tag: &str, seq: u64, cancelled: bool) -> (Vec<FlashMsg>, bool, bool) {
    let f = fake(tag);
    stick(&f.sys);
    let d = TestDir::new(&format!("{tag}-files"));
    let image = image(&d, "a.img", 70_000, 0);
    let target_path = d.join("drive.img");
    std::fs::write(&target_path, vec![0u8; 8_000_000]).unwrap();
    let reached = d.join("helper-reached");
    let mountinfo = d.file("mountinfo", &root_mountinfo());
    let swaps = d.file("swaps", NO_SWAPS);
    let body = format!("#!/bin/sh\ncase \"$1\" in\ndrives) printf '%s' '{{\"drives\":[{{\"dev\":\"sda\",\"system\":false}}]}}' ;;\nopen) : > '{}'; exec python3 -c 'import socket;s=socket.fromfd(0,socket.AF_UNIX,socket.SOCK_SEQPACKET);f=open(\"{}\",\"r+b\");socket.send_fds(s,[b\"O\"],[f.fileno()])' ;;\nesac\n",
        reached.display(), target_path.display());
    let helper = d.script("stub-udisks", &body).to_string_lossy().to_string();
    let (exe, ui) = roots();
    let host = Host { sys: &f.sys, dev: &f.dev, exe: &exe, ui: &ui, mountinfo: &mountinfo, swaps: &swaps, helper: &helper };
    let (tx, rx) = std::sync::mpsc::channel::<FlashMsg>();
    let req = FlashReq { id: 3, image: image.to_string_lossy().to_string(), dev: "sda".to_string(), seq,
        serial: "2003007157171692".to_string(), bytes: 124_623_257_600 };
    run_flash_on(req, Arc::new(AtomicBool::new(cancelled)), &tx, &host);
    drop(tx);
    let zero = std::fs::read(&target_path).unwrap().iter().all(|b| *b == 0);
    (rx.into_iter().collect(), reached.exists(), zero)
}

// A5 and A13: layers 1 to 4 run under the prepare phase, no password beat precedes a refusal, and the target stays untouched.
#[test]
fn the_worker_refuses_a_changed_identity_before_any_write() {
    let (lines, reached, zero) = press_on_fake("flashop-changed", 0, false);
    let text: Vec<&String> = lines.iter().map(|m| &m.line).collect();
    assert!(!reached, "the helper was never asked for the descriptor: {text:?}");
    assert_eq!(lines.len(), 3, "started, one prepare beat, then done: {text:?}");
    assert!(lines[0].line.contains("\"t\":\"flashstarted\""), "{}", lines[0].line);
    assert!(lines[1].line.contains("\"phase\":\"prepare\""), "{}", lines[1].line);
    assert!(!text.iter().any(|l| l.contains("\"phase\":\"password\"")), "the helper never ran, so no password beat: {text:?}");
    assert!(lines[2].line.contains("\"t\":\"flashdone\"") && lines[2].line.contains("\"err\":\"changed\""), "{}", lines[2].line);
    assert!(lines[2].terminal);
    assert!(zero, "a refused flash writes nothing to the target");
}

// A cancel that lands during prepare ends before the helper opens anything, so no prompt rises for a dead flash.
#[test]
fn a_cancel_during_prepare_never_reaches_the_helper() {
    let (lines, reached, zero) = press_on_fake("flashop-precancel", 2, true);
    let text: Vec<&String> = lines.iter().map(|m| &m.line).collect();
    assert!(!reached, "the helper was never asked for the descriptor: {text:?}");
    assert!(!text.iter().any(|l| l.contains("\"phase\":\"password\"")), "no prompt beat for a dead flash: {text:?}");
    assert!(text.last().is_some_and(|l| l.contains("\"t\":\"flashdone\"") && l.contains("\"err\":\"cancelled\"")), "{text:?}");
    assert!(zero, "a cancelled flash writes nothing to the target");
}

// The control: with the identity intact the stub is reached and hands over drive.img, and layer 6 still refuses a regular file before a byte moves.
#[test]
fn the_stub_helper_is_reached_when_the_identity_holds() {
    let (lines, reached, zero) = press_on_fake("flashop-reached", 2, false);
    let text: Vec<&String> = lines.iter().map(|m| &m.line).collect();
    assert!(reached, "the helper was asked for the descriptor: {text:?}");
    assert!(text.iter().any(|l| l.contains("\"phase\":\"password\"")), "{text:?}");
    assert!(text.last().is_some_and(|l| l.contains("\"err\":\"changed\"")), "the descriptor is no block device: {text:?}");
    assert!(zero, "layer 6 refuses before any write");
}

// A4: a read-back mismatch is a failed flash, so both ends are wiped and the card says blank.
#[test]
fn a_verify_mismatch_wipes_both_ends() {
    let (d, end, _) = raw_flash("flashop-mismatch", |path, _, phase| {
        if phase == "flush" {
            flip(path, crate::backend::flash::CHUNK_BYTES as u64 + 10);
        }
    });
    assert_eq!((end.ok, end.phase, end.err, end.at), (false, "verify", "verify", crate::backend::flash::CHUNK_BYTES as u64));
    assert!(end.blank, "a mismatch leaves a wiped drive, never an image that boots");
    assert!(ends_are_zero(&d, "drive.img"));
}

// A4 and A18: a cancel that lands during the final flush names flush and wipes.
#[test]
fn a_cancel_during_the_flush_wipes_and_names_flush() {
    let (d, end, _) = raw_flash("flashop-flushcancel", |_, cancel, phase| {
        if phase == "flush" {
            cancel.store(true, Ordering::Relaxed);
        }
    });
    assert_eq!((end.ok, end.phase, end.err), (false, "flush", "cancelled"));
    assert!(end.blank, "the final flush is not the verify, so the image does not stay");
    assert!(ends_are_zero(&d, "drive.img"));
}

// A4: callout 6 of the approved FlasherRun board, a cancelled verify leaves the image flashed.
#[test]
fn a_cancel_during_the_verify_keeps_the_image() {
    let (d, end, _) = raw_flash("flashop-verifycancel", |_, cancel, phase| {
        if phase == "verify" {
            cancel.store(true, Ordering::Relaxed);
        }
    });
    assert_eq!((end.ok, end.phase, end.err, end.blank), (false, "verify", "cancelled", false));
    let body = std::fs::read(d.join("drive.img")).unwrap();
    let want = std::fs::read(d.join("a.img")).unwrap();
    assert_eq!(&body[..IMAGE_BYTES], want.as_slice(), "the whole image is still on the drive");
}

// A12: an unknown-size stream knows its written total once the write ends, so flush and verify use it.
#[test]
fn flush_and_verify_measure_against_the_written_total() {
    let d = TestDir::new("flashop-unknown");
    let src = image(&d, "a.img.gz", 1000, 9);
    let dest = target(&d, "drive.img", DRIVE_BYTES);
    let cancel = AtomicBool::new(false);
    let (tx, rx) = channel::<FlashMsg>();
    let mut meter = Meter::new(1, &tx, false, 1000, 1000);
    let mut slept = false;
    meter.hook = Some(Box::new(move |phase, _| {
        if phase == "verify" && !slept {
            slept = true;
            std::thread::sleep(PAST_THROTTLE);
        }
    }));
    let mut job = Job::new(&src, "gz", "", &dest, DRIVE_BYTES as u64, &cancel);
    job.decompressor = Some(vec!["/bin/sh".to_string(), "-c".to_string(), format!("head -c {IMAGE_BYTES} /dev/zero")]);
    let end = flash_body(&job, GONE_DEV, &mut meter);
    drop(meter);
    drop(tx);
    assert!(end.ok, "{:?}", (end.phase, end.err));
    let lines: Vec<String> = rx.into_iter().map(|m| m.line).collect();
    let later: Vec<&String> = lines.iter().filter(|l| l.contains("\"phase\":\"flush\"") || l.contains("\"phase\":\"verify\"")).collect();
    assert!(later.len() >= 2, "a flush beat and a verify beat: {lines:?}");
    for line in &later {
        assert!(line.contains(&format!("\"total\":{IMAGE_BYTES}")), "total is the written size, not the packed file: {line}");
    }
    let verify = later.iter().find(|l| l.contains("\"phase\":\"verify\"")).unwrap();
    assert!(!verify.contains("\"permille\":1000"), "a first chunk of three is not done: {verify}");
}

// A7: a writer that counts flushes, so a line answered but never flushed is caught.
struct Counting {
    flushes: usize,
    bytes: Vec<u8>,
}

impl std::io::Write for Counting {
    fn write(&mut self, buf: &[u8]) -> std::io::Result<usize> {
        self.bytes.extend_from_slice(buf);
        Ok(buf.len())
    }
    fn flush(&mut self) -> std::io::Result<()> {
        self.flushes += 1;
        Ok(())
    }
}

#[test]
fn every_answer_path_flushes_its_line() {
    let d = TestDir::new("flashop-flush");
    let src = image(&d, "a.img", 4096, 1);
    let mut out = Counting { flushes: 0, bytes: Vec::new() };
    handle_flashimage(&mut out, &src.to_string_lossy());
    assert!(out.flushes >= 1, "the flashimage line is flushed");
    let f = fake("flashop-flush-eject");
    let (exe, ui) = roots();
    let r = crate::backend::flasheligible::Roots { sys: &f.sys, dev: &f.dev, exe: &exe, ui: &ui, loop_root: None };
    stick(&f.sys);
    let mut gone_out = Counting { flushes: 0, bytes: Vec::new() };
    eject_with(&mut gone_out, "sdz", 2, &r, ("", NO_SWAPS), &mut |_| Ok(()));
    assert!(String::from_utf8(gone_out.bytes.clone()).unwrap().contains("\"err\":\"gone\""));
    assert!(gone_out.flushes >= 1, "the gone answer is flushed");
    let mut changed_out = Counting { flushes: 0, bytes: Vec::new() };
    eject_with(&mut changed_out, "sda", 99, &r, ("", NO_SWAPS), &mut |_| Ok(()));
    assert!(String::from_utf8(changed_out.bytes.clone()).unwrap().contains("\"err\":\"changed\""));
    assert!(changed_out.flushes >= 1, "the changed answer is flushed");
}

// A11: an eject names a bare kernel disk the listing offers, never a system disk or a path.
#[test]
fn eject_never_runs_the_helper_for_a_system_disk_or_a_path() {
    let f = fake("flashop-eject");
    system(&f.sys);
    stick(&f.sys);
    let (exe, ui) = roots();
    let r = crate::backend::flasheligible::Roots { sys: &f.sys, dev: &f.dev, exe: &exe, ui: &ui, loop_root: None };
    let info = root_mountinfo();
    let mut ran: Vec<String> = Vec::new();
    for dev in ["nvme0n1", "sda/../nvme0n1", "../block/nvme0n1"] {
        let mut out = Vec::new();
        eject_with(&mut out, dev, 9, &r, (&info, NO_SWAPS), &mut |d| { ran.push(d.to_string()); Ok(()) });
        let text = String::from_utf8(out).unwrap();
        assert!(text.contains("\"ok\":false"), "{dev} is refused: {text}");
    }
    assert!(ran.is_empty(), "the helper never ran for a system disk or a traversing name: {ran:?}");
    let mut out = Vec::new();
    eject_with(&mut out, "sda", 2, &r, (&info, NO_SWAPS), &mut |d| { ran.push(d.to_string()); Ok(()) });
    assert_eq!(ran, vec!["sda".to_string()], "the listed stick still ejects");
    assert!(String::from_utf8(out).unwrap().contains("\"ok\":true"));
}

// A6: the log line for a failed phase names the phase, the disk and the cause.
#[test]
fn a6_the_io_log_line_names_phase_disk_and_detail() {
    assert_eq!(io_line("write", "sdb", "Input/output error at offset 4194304"), "flea: the flash write on /dev/sdb failed (Input/output error at offset 4194304)");
}

// A live disk name where io_ending reads io rather than gone; the kernel may list none here.
fn live_dev() -> String {
    std::fs::read_dir("/sys/block").ok()
        .and_then(|mut entries| entries.find_map(|e| e.ok().and_then(|e| e.file_name().into_string().ok())))
        .unwrap_or_else(|| GONE_DEV.to_string())
}

// One stub-fed flash of `streamed` bytes against a known probe total of IMAGE_BYTES; also the io line it logged.
fn probe_checked_flash(tag: &str, streamed: usize) -> (Ending, String, String) {
    let d = TestDir::new(tag);
    let src = image(&d, "a.img.gz", 1000, 9);
    let dest = target(&d, "drive.img", DRIVE_BYTES);
    let cancel = AtomicBool::new(false);
    let (tx, rx) = channel::<FlashMsg>();
    let mut meter = Meter::new(1, &tx, true, IMAGE_BYTES as u64, IMAGE_BYTES as u64);
    let mut job = Job::new(&src, "gz", "", &dest, DRIVE_BYTES as u64, &cancel);
    job.decompressor = Some(vec!["/bin/sh".to_string(), "-c".to_string(), format!("head -c {streamed} /dev/zero")]);
    job.probe_total = IMAGE_BYTES as u64;
    job.probe_known = true;
    let dev = live_dev();
    LAST_IO_LINE.with(|line| line.borrow_mut().clear());
    let end = flash_body(&job, &dev, &mut meter);
    drop(meter);
    drop(tx);
    drop(rx);
    (end, dev, LAST_IO_LINE.with(|line| line.borrow().clone()))
}

// A stream that ends before its known probe total never ends ok, however clean the short write verifies.
#[test]
fn an_image_shorter_than_its_probe_never_ends_ok() {
    let (end, dev, line) = probe_checked_flash("flashop-short", 100);
    assert!(!end.ok, "a short image never ends ok");
    assert_eq!(end.phase, "write");
    assert_eq!(end.err, if dev == GONE_DEV { "gone" } else { "io" });
    assert_eq!(line, io_line("write", &dev, "the image ended short"), "a short stream logs that it ended short");
}

// A stream longer than its probe total is refused too: the flasher trusts a known size in both directions.
#[test]
fn an_image_longer_than_its_probe_never_ends_ok() {
    let (end, dev, line) = probe_checked_flash("flashop-long", IMAGE_BYTES + 1);
    assert!(!end.ok, "a long image never ends ok");
    assert_eq!(end.phase, "write");
    assert_eq!(end.err, if dev == GONE_DEV { "gone" } else { "io" });
    assert_eq!(line, io_line("write", &dev, "the image held more data than its header listed"), "a long stream logs that it held more data");
}

#[test]
fn a_size_that_differs_from_the_probe_total_says_which_way() {
    assert_eq!(size_refusal(99, 100), Some("the image ended short"));
    assert_eq!(size_refusal(101, 100), Some("the image held more data than its header listed"));
    assert_eq!(size_refusal(100, 100), None);
}
