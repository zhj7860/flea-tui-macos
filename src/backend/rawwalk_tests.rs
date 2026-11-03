// IFD walk limits and type rules: the entry-count cap, the value budget, a next pointer cut by the file's end, and type 13 pointers.
use super::*;
use super::tests::{ctx_of, jpeg, write, Ev, Tb};
use crate::backend::rawexif as ex;
use crate::backend::testdir::TestDir;

#[test]
fn an_entry_count_of_0xffff_is_refused_before_its_entries_are_read() {
    let d = TestDir::new("rawcount");
    let pic = jpeg(64, 48);
    let mut t = Tb::new(true);
    let po = t.blob(&pic);
    let ifd0 = t.b.len() as u32;
    // The file holds all 0xFFFF entries, the first two a real JPEG pair, so a walker with no cap names the preview.
    t.b.extend_from_slice(&0xFFFFu16.to_le_bytes());
    for (tag, v) in [(ex::JPEG_OFF, po), (ex::JPEG_LEN, pic.len() as u32)] {
        t.b.extend_from_slice(&tag.to_le_bytes());
        t.b.extend_from_slice(&4u16.to_le_bytes());
        t.b.extend_from_slice(&1u32.to_le_bytes());
        t.b.extend_from_slice(&v.to_le_bytes());
    }
    t.b.resize(t.b.len() + (0xFFFF - 2) * 12 + 4, 0);
    t.set_ifd0(ifd0);
    let p = write(&d, "entries.cr2", &t.b);
    assert!(inspect_file(&mut ctx_of(&p)).is_none(), "0xFFFF entries walks no IFD");
    // The control: the same bytes with an honest count name the pair, so the refusal is the cap and not the file.
    t.b[ifd0 as usize..ifd0 as usize + 2].copy_from_slice(&2u16.to_le_bytes());
    let p = write(&d, "honest.cr2", &t.b);
    let (cands, _) = inspect_file(&mut ctx_of(&p)).expect("an honest count walks");
    assert_eq!(cands, vec![(po as u64, pic.len() as u64)]);
}

#[test]
fn a_700_entry_ifd_with_large_values_still_names_its_preview() {
    let d = TestDir::new("rawbudget");
    let pic = jpeg(64, 48);
    let mut t = Tb::new(true);
    let po = t.blob(&pic);
    let mut entries = vec![(ex::JPEG_OFF, Ev::T(4, po)), (ex::JPEG_LEN, Ev::T(4, pic.len() as u32))];
    for i in 0..698u16 {
        entries.push((0xC000 + i, Ev::B(7, vec![i as u8; 1500])));
    }
    let ifd0 = t.ifd(entries, 0);
    t.set_ifd0(ifd0);
    let p = write(&d, "hungry.cr2", &t.b);
    // Unknown tags cost no value reads, so 698 values of 1500 bytes leave the walk its budget.
    let (cands, _) = inspect_file(&mut ctx_of(&p)).expect("a 700-entry IFD walks");
    assert_eq!(cands, vec![(po as u64, pic.len() as u64)]);
}

#[test]
fn a_next_pointer_cut_off_by_the_end_of_the_file_keeps_the_collected_preview() {
    let d = TestDir::new("rawtrunctail");
    let pic = jpeg(64, 48);
    let mut t = Tb::new(true);
    let po = t.blob(&pic);
    let ifd0 = t.ifd(vec![(ex::JPEG_OFF, Ev::T(4, po)), (ex::JPEG_LEN, Ev::T(4, pic.len() as u32))], 0);
    t.set_ifd0(ifd0);
    let want = vec![(po as u64, pic.len() as u64)];
    let whole = write(&d, "whole.cr2", &t.b);
    assert_eq!(inspect_file(&mut ctx_of(&whole)).expect("the whole file walks").0, want);
    // The IFD is the last thing in the file, so two bytes off the end leave its next pointer half there.
    let cut = write(&d, "cut.cr2", &t.b[..t.b.len() - 2]);
    let (cands, _) = inspect_file(&mut ctx_of(&cut)).expect("a cut next pointer ends the walk, not the file");
    assert_eq!(cands, want);
}

#[test]
fn a_subifd_and_an_exif_pointer_typed_as_ifd_are_followed_like_longs() {
    let d = TestDir::new("rawtype13");
    let (a, b) = (jpeg(100, 80), jpeg(200, 160));
    let mut t = Tb::new(true);
    let (ao, bo) = (t.blob(&a), t.blob(&b));
    let sub_a = t.ifd(vec![(ex::JPEG_OFF, Ev::T(4, ao)), (ex::JPEG_LEN, Ev::T(4, a.len() as u32))], 0);
    let sub_b = t.ifd(vec![(ex::JPEG_OFF, Ev::T(4, bo)), (ex::JPEG_LEN, Ev::T(4, b.len() as u32))], 0);
    let exif = t.ifd(vec![(ex::ISO, Ev::T(3, 200))], 0);
    let subs = [sub_a.to_le_bytes(), sub_b.to_le_bytes()].concat();
    // Type 13 is an IFD offset stored as 4 bytes, the way ExifTool's Exif.pm reads format 'ifd'.
    let ifd0 = t.ifd(vec![(ex::SUB_IFD, Ev::B(13, subs)), (ex::EXIF_IFD_PTR, Ev::T(13, exif))], 0);
    t.set_ifd0(ifd0);
    let p = write(&d, "t13.dng", &t.b);
    let (cands, facts) = inspect_file(&mut ctx_of(&p)).expect("walks");
    assert_eq!(cands, vec![(ao as u64, a.len() as u64), (bo as u64, b.len() as u64)]);
    assert_eq!(facts.iso, Some(200));
}
