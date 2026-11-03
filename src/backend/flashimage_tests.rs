// The image probe against names, magic and real files.
use super::*;
use crate::backend::testdir::TestDir;

#[test]
fn a_name_without_an_image_suffix_has_no_kind() {
    assert_eq!(kind_of_name("notes.txt"), "");
    assert_eq!(kind_of_name("disk.iso.torrent"), "");
    assert_eq!(kind_of_name("a.img.xz"), "xz");
    assert_eq!(kind_of_name("a.raw"), "img");
    assert_eq!(kind_of_name("a.zip"), "zip");
}

// The probe itself lowercases the name, so an upper-case suffix still answers its kind.
#[test]
fn the_probe_reads_an_upper_case_suffix() {
    let d = TestDir::new("flashimage-upper");
    let path = d.join("DISK.IMG");
    std::fs::write(&path, [0u8; 512]).unwrap();
    assert_eq!(probe(&path).kind, "img");
}

#[test]
fn magic_that_disagrees_with_the_name_refuses_the_row() {
    assert!(!magic_holds("xz", b"not compressed at all"));
    assert!(magic_holds("xz", &[0xFD, 0x37, 0x7A, 0x58, 0x5A, 0x00, 0x01]));
    assert!(magic_holds("gz", &[0x1F, 0x8B, 0x08]));
    assert!(magic_holds("zst", &[0x28, 0xB5, 0x2F, 0xFD, 0x00]));
    assert!(magic_holds("bz2", b"BZh91AY&SY"));
    assert!(magic_holds("zip", &[0x50, 0x4B, 0x03, 0x04, 0x14]));
    assert!(magic_holds("img", b""));
}

// A fifo named like an image has no head to read and no writer to wake its open, so the probe must refuse it unopened.
#[test]
fn a_fifo_named_like_an_image_is_refused_and_never_waited_on() {
    use crate::backend::fifotest::{mkfifo, within};
    let d = TestDir::new("flashimage-fifo");
    let fifo = d.join("pipe.img");
    mkfifo(&fifo);
    let got = within("a probe of a fifo", move || probe(&fifo));
    assert_eq!(got.kind, "", "a fifo is no image");
}

#[test]
fn a_raw_image_probes_off_name_and_bytes_alone() {
    let d = TestDir::new("flashimage-raw");
    let path = d.join("plain.img");
    std::fs::write(&path, vec![7u8; 8192]).unwrap();
    let got = probe(&path);
    assert_eq!((got.kind.as_str(), got.bytes, got.unpacked, got.known), ("img", 8192, 8192, true));
}

#[test]
fn a_renamed_text_file_is_not_a_disk_image() {
    let d = TestDir::new("flashimage-fake");
    let path = d.join("notes.img");
    std::fs::write(&path, b"just text").unwrap();
    let got = probe(&path);
    assert_eq!((got.kind.as_str(), got.bytes), ("img", 9), "a .img takes anything, so a text body still probes");
    let xz = d.join("notes.img.xz");
    std::fs::write(&xz, b"just text").unwrap();
    assert_eq!(probe(&xz).kind, "", "magic refusing a mismatched suffix is the whole rule");
}

#[test]
fn a_gzip_image_probes_with_an_unknown_size() {
    let d = TestDir::new("flashimage-gz");
    let body: Vec<u8> = (0..5000u32).map(|n| (n % 251) as u8).collect();
    std::fs::write(d.join("a.img"), &body).unwrap();
    let status = std::process::Command::new("gzip").arg("-k").arg("-f").arg(d.join("a.img")).status().unwrap();
    assert!(status.success());
    let got = probe(&d.join("a.img.gz"));
    assert_eq!((got.kind.as_str(), got.known), ("gz", false));
    assert_eq!(got.bytes, d.join("a.img.gz").metadata().unwrap().len());
}

// A fixture ISO: the 9660 signature at its offset, in a body of this length.
fn iso_of(bytes: usize) -> Vec<u8> {
    let mut body = vec![0u8; bytes];
    body[ISO_OFFSET..ISO_OFFSET + ISO_MAGIC.len()].copy_from_slice(ISO_MAGIC);
    body
}

// A little past the probe's head, and several times the pipe buffer.
const SMALL_ISO_BYTES: usize = ISO_OFFSET + 8192;
const BIG_ISO_BYTES: usize = 8 * 1024 * 1024;

// True where the sandbox really runs a tool; a host may carry the programs and a layout bwrap cannot bind.
fn jail_runs(dir: &TestDir) -> bool {
    let inner = vec!["bsdtar".to_string(), "--version".to_string()];
    capture(&crate::backend::sandbox::wrap_readonly(&inner, &dir.join("."))).is_some()
}

fn zip_of(dir: &TestDir, member: &str, body: &[u8]) -> std::path::PathBuf {
    std::fs::write(dir.join(member), body).unwrap();
    let zip = dir.join("bundle.zip");
    let made = std::process::Command::new("bsdtar").arg("--format").arg("zip").arg("-cf").arg(&zip).arg("-C").arg(dir.join(".")).arg(member).status().unwrap();
    assert!(made.success());
    zip
}

#[test]
fn b1_an_iso_with_its_signature_probes_iso() {
    let d = TestDir::new("flashimage-iso");
    std::fs::write(d.join("disk.iso"), iso_of(SMALL_ISO_BYTES)).unwrap();
    let got = probe(&d.join("disk.iso"));
    assert_eq!((got.kind.as_str(), got.known, got.unpacked), ("iso", true, SMALL_ISO_BYTES as u64));
    std::fs::write(d.join("blank.iso"), vec![0u8; SMALL_ISO_BYTES]).unwrap();
    assert_eq!(probe(&d.join("blank.iso")).kind, "", "an .iso without CD001 is refused");
}

#[test]
fn b1_a_zip_holding_an_iso_probes_zip() {
    let d = TestDir::new("flashimage-zipiso");
    if !jail_runs(&d) {
        eprintln!("flea test: the sandbox does not run on this host, so the zipped ISO probe went unproven here");
        return;
    }
    let zip = zip_of(&d, "disk.iso", &iso_of(SMALL_ISO_BYTES));
    let got = probe(&zip);
    assert_eq!((got.kind.as_str(), got.member.as_str()), ("zip", "disk.iso"));
}

// Folders a zip stores beside its files are not members, so one image in a folder still probes zip.
#[test]
fn flx1_a_zip_with_one_image_in_a_folder_probes_zip() {
    let d = TestDir::new("flashimage-zipsub");
    if !jail_runs(&d) {
        eprintln!("flea test: the sandbox does not run on this host, so the subfolder zip probe went unproven here");
        return;
    }
    std::fs::create_dir_all(d.join("fw")).unwrap();
    std::fs::write(d.join("fw/disk.img"), vec![7u8; 8192]).unwrap();
    let zip = d.join("bundle.zip");
    let made = std::process::Command::new("bsdtar").arg("--format").arg("zip").arg("-cf").arg(&zip).arg("-C").arg(d.join(".")).arg("fw").status().unwrap();
    assert!(made.success());
    let got = probe(&zip);
    assert_eq!((got.kind.as_str(), got.member.as_str()), ("zip", "fw/disk.img"));
}

// Two file members refuse the row, however few folders they stand beside.
#[test]
fn flx1_a_zip_with_two_images_is_refused() {
    let d = TestDir::new("flashimage-ziptwo");
    if !jail_runs(&d) {
        eprintln!("flea test: the sandbox does not run on this host, so the two-image zip probe went unproven here");
        return;
    }
    std::fs::write(d.join("a.img"), vec![7u8; 4096]).unwrap();
    std::fs::write(d.join("b.img"), vec![7u8; 4096]).unwrap();
    let zip = d.join("bundle.zip");
    let made = std::process::Command::new("bsdtar").arg("--format").arg("zip").arg("-cf").arg(&zip).arg("-C").arg(d.join(".")).arg("a.img").arg("b.img").status().unwrap();
    assert!(made.success());
    let got = probe(&zip);
    assert_eq!((got.kind.as_str(), got.member.as_str()), ("", ""));
}

// A member no ledger suffix names refuses the row the same way.
#[test]
fn flx1_a_zip_with_a_non_image_member_is_refused() {
    let d = TestDir::new("flashimage-ziptext");
    if !jail_runs(&d) {
        eprintln!("flea test: the sandbox does not run on this host, so the text-member zip probe went unproven here");
        return;
    }
    std::fs::write(d.join("notes.txt"), b"just text").unwrap();
    let zip = d.join("bundle.zip");
    let made = std::process::Command::new("bsdtar").arg("--format").arg("zip").arg("-cf").arg(&zip).arg("-C").arg(d.join(".")).arg("notes.txt").status().unwrap();
    assert!(made.success());
    let got = probe(&zip);
    assert_eq!((got.kind.as_str(), got.member.as_str()), ("", ""));
}

#[test]
fn b6_two_zstd_frames_sum_both_sizes() {
    let d = TestDir::new("flashimage-zstd2");
    let first: Vec<u8> = (0..5000u32).map(|n| (n % 251) as u8).collect();
    let second: Vec<u8> = (0..7000u32).map(|n| (n % 241) as u8).collect();
    for (name, body) in [("one.img", &first), ("two.img", &second)] {
        std::fs::write(d.join(name), body).unwrap();
        assert!(std::process::Command::new("zstd").arg("-q").arg("-f").arg(d.join(name)).arg("-o").arg(d.join(&format!("{name}.zst"))).status().unwrap().success());
    }
    let mut joined = std::fs::read(d.join("one.img.zst")).unwrap();
    let whole = joined.len();
    joined.extend(std::fs::read(d.join("two.img.zst")).unwrap());
    std::fs::write(d.join("both.img.zst"), &joined).unwrap();
    let got = probe(&d.join("both.img.zst"));
    assert_eq!((got.kind.as_str(), got.unpacked, got.known), ("zst", 12_000, true), "both frames count");
    std::fs::write(d.join("cut.img.zst"), &joined[..whole + 20]).unwrap();
    let cut = probe(&d.join("cut.img.zst"));
    assert_eq!((cut.kind.as_str(), cut.known), ("zst", false), "a truncated second frame is unknown, never frame one's size");
}

#[test]
fn b2_a_zipped_iso_larger_than_the_pipe_probes_zip_at_once() {
    let d = TestDir::new("flashimage-zipbig");
    if !jail_runs(&d) {
        eprintln!("flea test: the sandbox does not run on this host, so the big zipped ISO probe went unproven here");
        return;
    }
    let zip = zip_of(&d, "big.iso", &iso_of(BIG_ISO_BYTES));
    let started = std::time::Instant::now();
    let got = probe(&zip);
    assert_eq!((got.kind.as_str(), got.member.as_str(), got.unpacked), ("zip", "big.iso", BIG_ISO_BYTES as u64));
    assert!(started.elapsed() < PROBE_TIMEOUT / 2, "the head is read and the unpacker ended, not waited out");
}

// A plain child that writes this much stands in for a jailed tool, so the capture rule is proven where bwrap cannot run.
fn writer_of(bytes: usize) -> crate::backend::jail::Jailed {
    let child = std::process::Command::new("/bin/sh").arg("-c").arg(format!("head -c {bytes} /dev/zero"))
        .stdin(std::process::Stdio::null()).stdout(std::process::Stdio::piped()).stderr(std::process::Stdio::null()).spawn().unwrap();
    crate::backend::jail::Jailed { child, sandbox_pid: std::sync::Arc::new(std::sync::atomic::AtomicI32::new(crate::backend::jail::NO_PID)) }
}

#[test]
fn b2_a_full_head_is_taken_and_the_tool_that_writes_on_is_ended() {
    let started = std::time::Instant::now();
    let head = collect(writer_of(BIG_ISO_BYTES), HEAD_BYTES, true, PROBE_TIMEOUT);
    assert!(head.is_some_and(|h| h.len() >= HEAD_BYTES), "the head of a member bigger than the pipe is accepted");
    assert!(started.elapsed() < PROBE_TIMEOUT / 2, "the tool is ended at the head, not waited out");
}

#[test]
fn a_whole_capture_that_hits_its_cap_is_refused() {
    assert_eq!(collect(writer_of(BIG_ISO_BYTES), HEAD_BYTES, false, PROBE_TIMEOUT), None, "a truncated listing is never parsed");
    assert_eq!(collect(writer_of(HEAD_BYTES / 2), HEAD_BYTES, false, PROBE_TIMEOUT).map(|o| o.len()), Some(HEAD_BYTES / 2), "a short clean run is kept");
}

// The one file member beside any folders, read off the central directory without any decompression.
fn entries_of(names: &[(&str, bool)]) -> Vec<crate::backend::archivelist::Entry> {
    names.iter().map(|(n, d)| crate::backend::archivelist::Entry { name: n.to_string(), is_dir: *d }).collect()
}

// One image in a folder names that file, so its menu row and its flash read the same member.
#[test]
fn flx1_one_file_beside_folders_names_that_file() {
    assert_eq!(zip_image_member(&entries_of(&[("fw/", true), ("fw/disk.img", false)])), "fw/disk.img");
}

// Two files name nothing, so the row stays absent however few folders stand beside them.
#[test]
fn flx1_two_files_name_nothing() {
    assert_eq!(zip_image_member(&entries_of(&[("a.img", false), ("b.img", false)])), "");
}

// A member no ledger suffix names refuses the row the same way.
#[test]
fn flx1_a_non_image_names_nothing() {
    assert_eq!(zip_image_member(&entries_of(&[("notes.txt", false)])), "");
}

// A capped name list holding folders plus one image, with further files past the cap, names nothing.
#[test]
fn flx1_a_capped_listing_names_nothing() {
    let mut names = vec![
        crate::backend::archivelist::Entry { name: "fw/".to_string(), is_dir: true },
        crate::backend::archivelist::Entry { name: "fw/disk.img".to_string(), is_dir: false },
    ];
    for n in 0..62 {
        names.push(crate::backend::archivelist::Entry { name: format!("folder{n}/"), is_dir: true });
    }
    assert_eq!(names.len(), crate::backend::archivelist::ARCHIVE_NAME_CAP);
    let contents = crate::backend::archivelist::Contents { entries: 70, produced_entries: 69,
        unpacked: 100, names, failed: false };
    assert_eq!(zip_member(&contents), "", "files past the cap defeat the one-file read");
}

// A whole listing naming one image beside folders still names it.
#[test]
fn flx1_a_whole_listing_still_names_its_image() {
    let contents = crate::backend::archivelist::Contents { entries: 2, produced_entries: 2,
        unpacked: 100, names: entries_of(&[("fw/", true), ("fw/disk.img", false)]), failed: false };
    assert_eq!(zip_member(&contents), "fw/disk.img");
}

// bsdtar builds the fixture below, so without it the listing proves nothing.
fn bsdtar_or_skip() -> bool {
    if std::process::Command::new("bsdtar").arg("--version").output().map(|o| o.status.success()).unwrap_or(false) {
        return true;
    }
    let who = std::thread::current().name().unwrap_or("a sandboxed test").to_string();
    let line = format!("SKIP {who}: no bsdtar on this box, so no zip listing can be built\n");
    let _ = std::io::Write::write_all(&mut std::io::stderr(), line.as_bytes());
    false
}

// A real whole zip listing with folders counts every row it names.
#[test]
fn flxf2_a_real_zip_listing_is_whole() {
    if !bsdtar_or_skip() { return; }
    for (tag, with_extra) in [("flashimage-ziplisting", false), ("flashimage-ziplisting-two", true)] {
        let d = TestDir::new(tag);
        std::fs::create_dir_all(d.join("fw")).unwrap();
        std::fs::write(d.join("fw/disk.img"), vec![7u8; 4096]).unwrap();
        let mut build = std::process::Command::new("bsdtar");
        build.arg("--format").arg("zip").arg("-cf").arg(d.join("bundle.zip"))
            .arg("-C").arg(d.join(".")).arg("fw");
        if with_extra {
            std::fs::create_dir_all(d.join("extra")).unwrap();
            build.arg("extra");
        }
        assert!(build.status().unwrap().success());
        let out = std::process::Command::new("bsdtar").arg("-tvf").arg(d.join("bundle.zip")).output().expect("bsdtar -tvf");
        assert!(out.status.success());
        let text = String::from_utf8(out.stdout).expect("bsdtar listing is UTF-8");
        let contents = crate::backend::archivelist::parse_reader(std::io::BufReader::new(text.as_bytes()),
            &crate::backend::archivespec::tar_spec());
        assert!(!contents.failed, "a whole zip listing parses");
        assert_eq!(contents.entries, contents.names.len(), "a whole listing names every row it counted: {text}");
        assert_eq!(zip_member(&contents), "fw/disk.img");
    }
}
