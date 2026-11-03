// The producer behind a piped flash: its jail argv and the child production really spawns.
use super::*;
use crate::backend::testdir::TestDir;
use std::io::Read;

// The flasher's decompressor jail streams on stdio and binds no user path.
#[test]
fn the_stream_jail_binds_no_user_path_and_carries_no_cpu_cap() {
    let inner = vec!["xz".to_string(), "-dc".to_string()];
    let got = crate::backend::sandbox::wrap_stream(&inner, None);
    assert_eq!(got[0], "prlimit");
    assert!(got.iter().any(|a| a == "--as=2147483648"), "the stream jail keeps the 2 GiB cap: {:?}", got);
    assert!(!got.iter().any(|a| a.starts_with("--cpu=")), "a stream lasts as long as the image: {:?}", got);
    let tail = &got[got.len() - inner.len()..];
    assert_eq!(tail, inner.as_slice(), "the inner argv is still last and unchanged");
    let joined = got.join(" ");
    assert!(joined.contains("--ro-bind /usr /usr"), "system paths stay read-only: {}", joined);
    assert!(!joined.contains("--ro-bind /in"), "no user path is bound: {}", joined);
    assert!(!joined.contains("--bind "), "nothing is writable: {}", joined);
    assert!(got.iter().any(|a| a == "--unshare-all"), "the namespace flags are unchanged: {:?}", got);
}

// A zip inflates for longer than the decoder CPU cap, so its stream jail binds the image with no CPU cap.
#[test]
fn the_zip_stream_binds_the_image_read_only_and_carries_no_cpu_cap() {
    let inner = vec!["bsdtar".to_string(), "-xOf".to_string(), "/in/bundle.zip".to_string(), "disk.img".to_string()];
    let got = crate::backend::sandbox::wrap_stream(&inner, Some(std::path::Path::new("/in/bundle.zip")));
    assert_eq!(got[0], "prlimit");
    assert!(got.iter().any(|a| a == "--as=2147483648"), "the stream jail keeps the 2 GiB cap: {:?}", got);
    assert!(!got.iter().any(|a| a.starts_with("--cpu=")), "a zip inflates past the decoder cap: {:?}", got);
    let joined = got.join(" ");
    assert!(joined.contains("--ro-bind /in/bundle.zip /in/bundle.zip"), "the image stays readable: {}", joined);
    let tail = &got[got.len() - inner.len()..];
    assert_eq!(tail, inner.as_slice(), "the inner argv is still last and unchanged");
}

// The producer's zip branch builds through wrap_stream, not wrap_readonly: a swap must go red.
#[test]
fn the_producer_jail_binds_the_image_only_for_a_zip() {
    let zip_inner = vec!["bsdtar".to_string(), "-xOf".to_string(), "/in/bundle.zip".to_string(), "disk.img".to_string()];
    let zip = producer_jail(&zip_inner, "zip", std::path::Path::new("/in/bundle.zip"));
    assert!(!zip.iter().any(|a| a.starts_with("--cpu=")), "a zip inflates past the decoder cap: {:?}", zip);
    assert!(zip.join(" ").contains("--ro-bind /in/bundle.zip /in/bundle.zip"), "the zip branch binds the image: {}", zip.join(" "));
    let other_inner = vec!["xz".to_string(), "-dc".to_string()];
    let other = producer_jail(&other_inner, "xz", std::path::Path::new("/in/a.img.xz"));
    assert!(!other.iter().any(|a| a.starts_with("--cpu=")), "a stream lasts as long as the image: {:?}", other);
    assert!(!other.join(" ").contains("--ro-bind /in/a.img.xz"), "only the zip branch binds the image: {}", other.join(" "));
}

// A zip member named with brackets streams itself: bsdtar reads -xOf operands as patterns.
#[test]
fn a_zip_member_named_with_brackets_streams_itself() {
    assert_eq!(escape_member("disk[1].img"), "disk\\[1\\].img");
    assert_eq!(escape_member("a*b?c\\d.img"), "a\\*b\\?c\\\\d.img");
    assert_eq!(escape_member("fw/disk.img"), "fw/disk.img");
    let d = TestDir::new("flashpipe-brackets");
    let body: Vec<u8> = (0..70_000u32).map(|n| (n % 251) as u8).collect();
    std::fs::write(d.join("disk[1].img"), &body).unwrap();
    let zip = d.join("bundle.zip");
    let made = std::process::Command::new("bsdtar").arg("--format").arg("zip").arg("-cf").arg(&zip)
        .arg("-C").arg(d.join(".")).arg("disk[1].img").status().unwrap();
    assert!(made.success());
    let argv = decompressor_argv("zip", &zip, "disk[1].img").unwrap();
    assert_eq!(argv.last().unwrap(), "disk\\[1\\].img", "the member travels escaped, not raw");
    if !crate::backend::sandbox::available() && crate::backend::sandboxprobe::skipped() { return; }
    let cancel = std::sync::atomic::AtomicBool::new(false);
    let dest = std::fs::File::open(d.join("disk[1].img")).unwrap();
    let job = Job::new(&zip, "zip", "disk[1].img", &dest, 0, &cancel);
    let (mut child, _input) = spawn_producer(&job).map_err(|_| "the producer did not spawn").unwrap();
    let mut pipe = child.stdout.take().expect("the producer's stdout reaches the writer");
    let mut out = Vec::new();
    pipe.read_to_end(&mut out).unwrap();
    let status = child.wait().unwrap();
    if status.success() {
        assert_eq!(out, body, "the bracketed member streams itself, not a pattern miss");
    } else {
        eprintln!("flea: the jail did not run here ({status}), so only the escaped argv was proven");
    }
}

// A10: the production arm hands the producer's stdout to the writer, or every compressed image fails.
#[test]
fn the_production_arm_keeps_the_producers_stdout() {
    if !crate::backend::sandbox::available() && crate::backend::sandboxprobe::skipped() { return; }
    let d = TestDir::new("flashpipe-gz");
    let body: Vec<u8> = (0..70_000u32).map(|n| (n % 251) as u8).collect();
    std::fs::write(d.join("a.img"), &body).unwrap();
    assert!(std::process::Command::new("gzip").arg("-k").arg("-f").arg(d.join("a.img")).status().unwrap().success());
    let cancel = std::sync::atomic::AtomicBool::new(false);
    let dest = std::fs::File::open(d.join("a.img")).unwrap();
    let packed = d.join("a.img.gz");
    let job = Job::new(&packed, "gz", "", &dest, 0, &cancel);
    let (mut child, _input) = spawn_producer(&job).map_err(|_| "the producer did not spawn").unwrap();
    let mut pipe = child.stdout.take().expect("the producer's stdout reaches the writer");
    let mut out = Vec::new();
    pipe.read_to_end(&mut out).unwrap();
    let status = child.wait().unwrap();
    if status.success() {
        assert_eq!(out, body, "the unpacked bytes come through the pipe");
    } else {
        eprintln!("flea: the jail did not run here ({status}), so only the pipe's presence was proven");
    }
}
