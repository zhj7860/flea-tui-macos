// The verify and the wipe against plain files; the O_DIRECT cases live in flashdirect_tests.
use super::*;
use crate::backend::flashio::{direct_on, set_direct, write_at};
use crate::backend::flashwrite::{write_stream, Job};
use crate::backend::testdir::TestDir;

const DRIVE_BYTES: usize = 16_000_000;
const IMAGE_BYTES: usize = 9_000_000;
const CANCEL_DRIVE_BYTES: usize = 12_000_000;

fn target(dir: &TestDir, name: &str, bytes: usize) -> std::fs::File {
    let path = dir.join(name);
    let file = std::fs::OpenOptions::new().read(true).write(true).create(true).truncate(true).open(&path).unwrap();
    file.set_len(bytes as u64).unwrap();
    file
}

fn image(dir: &TestDir, name: &str, bytes: usize, seed: u8) -> std::path::PathBuf {
    let path = dir.join(name);
    let body: Vec<u8> = (0..bytes).map(|n| (n % 251) as u8 ^ seed).collect();
    std::fs::write(&path, &body).unwrap();
    path
}

#[test]
fn a_write_then_verify_round_trips_against_a_file() {
    let d = TestDir::new("flashverify-roundtrip");
    let src = image(&d, "a.img", IMAGE_BYTES, 3);
    let dest = target(&d, "drive.img", DRIVE_BYTES);
    let cancel = AtomicBool::new(false);
    let mut seen = 0;
    let job = Job::new(&src, "img", "", &dest, DRIVE_BYTES as u64, &cancel);
    let (table, written) = write_stream(&job, &mut |_, _| seen += 1).unwrap();
    assert_eq!((table.len(), written), (3, IMAGE_BYTES as u64), "9 MiB over 4 MiB chunks is three digests");
    assert!(seen > 0);
    verify(&dest, &table, written, &cancel, &mut |_| {}).unwrap();
}

#[test]
fn a_byte_flipped_between_write_and_verify_fails_at_its_chunk() {
    let d = TestDir::new("flashverify-verifyhook");
    let src = image(&d, "a.img", IMAGE_BYTES, 5);
    let dest = target(&d, "drive.img", DRIVE_BYTES);
    let cancel = AtomicBool::new(false);
    let job = Job::new(&src, "img", "", &dest, DRIVE_BYTES as u64, &cancel);
    let (table, written) = write_stream(&job, &mut |_, _| {}).unwrap();
    {
        use std::io::{Seek, SeekFrom, Write};
        let mut raw = std::fs::OpenOptions::new().write(true).open(d.join("drive.img")).unwrap();
        raw.seek(SeekFrom::Start(CHUNK_BYTES as u64 + 10)).unwrap();
        raw.write_all(&[0xFF]).unwrap();
    }
    match verify(&dest, &table, written, &cancel, &mut |_| {}) {
        Err(Fail::Mismatch(at)) => assert_eq!(at, CHUNK_BYTES as u64),
        other => panic!("a flipped byte must fail verify, got {other:?}"),
    }
}

#[test]
fn a_cancel_mid_write_leaves_both_ends_zero() {
    let d = TestDir::new("flashverify-cancel");
    let src = image(&d, "a.img", CANCEL_DRIVE_BYTES, 7);
    let dest = target(&d, "drive.img", CANCEL_DRIVE_BYTES);
    let cancel = AtomicBool::new(false);
    let mut calls = 0;
    let job = Job::new(&src, "img", "", &dest, CANCEL_DRIVE_BYTES as u64, &cancel);
    let out = write_stream(&job, &mut |_, _| {
        calls += 1;
        if calls == 1 {
            cancel.store(true, Ordering::Relaxed);
        }
    });
    assert!(matches!(out, Err(Fail::Cancelled)));
    assert!(wipe_ends(&dest, CANCEL_DRIVE_BYTES as u64));
    let body = std::fs::read(d.join("drive.img")).unwrap();
    assert!(body[..WIPE_BYTES as usize].iter().all(|b| *b == 0), "the first MiB is zero");
    assert!(body[body.len() - WIPE_BYTES as usize..].iter().all(|b| *b == 0), "the last MiB is zero");
}

#[test]
fn a_regular_file_without_o_direct_stays_buffered_through_a_ragged_write() {
    let d = TestDir::new("flashverify-direct");
    let dest = target(&d, "drive.img", DIRECT_ALIGN);
    assert!(!direct_on(&dest));
    set_direct(&dest, false);
    assert!(!direct_on(&dest));
    write_at(&dest, &[1u8; 100], 0).unwrap();
}
