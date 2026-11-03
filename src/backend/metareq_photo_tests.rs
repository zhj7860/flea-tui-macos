// The photo facts of the meta reply and of Properties: a RAW through the walk, a JPEG through its Exif APP1, and nothing for anything else.
use super::*;
use crate::backend::fifotest::BOUND;
use crate::backend::rawbmff::tests::{cr3, tiff as cmt_tiff};
use crate::backend::rawexif as ex;
use crate::backend::rawtiff::tests::{jpeg, write, Ev, Tb};
use crate::backend::testdir::TestDir;

fn rat(num: u32, den: u32) -> Vec<u8> {
    [num.to_le_bytes(), den.to_le_bytes()].concat()
}

fn text(tag: u16, s: &str) -> (u16, Ev) {
    (tag, Ev::B(2, format!("{}\0", s).into_bytes()))
}

// A little-endian TIFF carrying every photo fact, the shape a camera writes into a RAW or into a JPEG's APP1.
fn camera_tiff() -> Vec<u8> {
    let mut t = Tb::new(true);
    let exif = t.ifd(
        vec![
            (ex::EXPOSURE, Ev::B(5, rat(1, 250))),
            (ex::FNUMBER, Ev::B(5, rat(28, 10))),
            (ex::ISO, Ev::T(3, 400)),
            text(ex::TAKEN, "2026:09:12 18:31:00"),
            (ex::FOCAL, Ev::B(5, rat(35, 1))),
            text(ex::LENS, "RF35mm F1.8 MACRO IS STM"),
            (ex::PIXEL_X, Ev::T(4, 6000)),
            (ex::PIXEL_Y, Ev::T(4, 4000)),
        ],
        0,
    );
    let ifd0 = t.ifd(vec![text(ex::MAKE, "Canon"), text(ex::MODEL, "Canon EOS R6"), (ex::EXIF_IFD_PTR, Ev::T(4, exif))], 0);
    t.set_ifd0(ifd0);
    t.b
}

// FF D8 | APP0 | `pad` bytes of true-length APP2 segments | APP1 "Exif" TIFF | SOF0, so the walk reads every segment to reach Exif.
fn jpeg_with_exif(tiff: &[u8], pad: usize) -> Vec<u8> {
    let mut v = vec![0xFF, 0xD8, 0xFF, 0xE0, 0x00, 0x08, 1, 2, 3, 4, 5, 6];
    let mut left = pad;
    while left > 0 {
        let chunk = left.min(65_533);
        v.extend_from_slice(&[0xFF, 0xE2]);
        v.extend_from_slice(&u16::try_from(chunk + 2).expect("one APP2 segment fits its length").to_be_bytes());
        v.resize(v.len() + chunk, 0);
        left -= chunk;
    }
    v.extend_from_slice(&[0xFF, 0xE1]);
    v.extend_from_slice(&((tiff.len() + 8) as u16).to_be_bytes());
    v.extend_from_slice(b"Exif\0\0");
    v.extend_from_slice(tiff);
    v.extend_from_slice(&jpeg(64, 48)[2..]);
    v
}

const WIRE: &str = r#"{"make":"Canon","model":"Canon EOS R6","lens":"RF35mm F1.8 MACRO IS STM","exp":[1,250],"fnum":[28,10],"iso":400,"focal":[35,1],"taken":"2026:09:12 18:31:00","w":6000,"h":4000}"#;

#[test]
fn a_raw_reports_each_photo_fact_on_the_meta_line() {
    let d = TestDir::new("photoraw");
    let p = write(&d, "IMG_0412.CR2", &camera_tiff());
    let m = read(&p, false, false, None);
    assert_eq!(m.photo.make.as_deref(), Some("Canon"));
    assert_eq!(m.photo.model.as_deref(), Some("Canon EOS R6"));
    assert_eq!(m.photo.lens.as_deref(), Some("RF35mm F1.8 MACRO IS STM"));
    assert_eq!((m.photo.exposure, m.photo.f_number, m.photo.iso), (Some((1, 250)), Some((28, 10)), Some(400)));
    assert_eq!((m.photo.focal_mm, m.photo.taken.as_deref()), (Some((35, 1)), Some("2026:09:12 18:31:00")));
    assert_eq!((m.photo.width, m.photo.height), (Some(6000), Some(4000)), "the sensor size rides with the facts");
    let line = meta_line(3, &m);
    assert!(line.contains(&format!(r#""lfailed":false,"frames":0,"photo":{},"target""#, WIRE)), "{}", line);
    assert!(crate::jsondoc::parse(&line).is_ok(), "{}", line);
}

#[test]
fn a_cr3_reports_its_camera_from_the_cmt_box() {
    let d = TestDir::new("photocr3");
    let cmt1 = cmt_tiff(&[(ex::MAKE, 2, b"Canon\0"), (ex::MODEL, 2, b"Canon EOS R6\0")]);
    let cmt2 = cmt_tiff(&[(ex::PIXEL_X, 4, &6000u32.to_le_bytes()), (ex::PIXEL_Y, 3, &4000u16.to_le_bytes())]);
    let p = write(&d, "IMG_0412.CR3", &cr3(&jpeg(1620, 1080), &jpeg(160, 120), &cmt1, &cmt2));
    let m = read_in(&p, false, false, None, &d.join("raw"));
    assert_eq!(m.raw.as_ref().map(|raw| (raw.width, raw.height)), Some((1620, 1080)), "the embedded preview stays separate from the sensor size");
    assert_eq!((m.photo.make.as_deref(), m.photo.model.as_deref()), (Some("Canon"), Some("Canon EOS R6")));
    assert_eq!((m.photo.width, m.photo.height), (Some(6000), Some(4000)), "CMT2 carries the EXIF dimensions, SHORT or LONG");
    assert!(photo_json(&m.photo).contains(r#""model":"Canon EOS R6""#));
}

#[test]
fn a_raw_with_no_exif_and_a_name_with_no_raw_in_it_answer_null() {
    let d = TestDir::new("photonone");
    let mut bare = Tb::new(true);
    let ifd0 = bare.ifd(vec![(ex::ORIENTATION, Ev::T(3, 6))], 0);
    bare.set_ifd0(ifd0);
    let none = read(&write(&d, "bare.nef", &bare.b), false, false, None);
    assert_eq!(photo_json(&none.photo), "null", "an orientation alone is no photo fact");
    assert!(meta_line(1, &none).contains(r#""photo":null,"target""#));
    assert_eq!(photo_json(&read(&write(&d, "junk.cr2", b"not a raw file at all"), false, false, None).photo), "null");
    assert_eq!(photo_json(&read(&d.join("never-existed.dng"), false, false, None).photo), "null");
    assert_eq!(photo_json(&read(&write(&d, "camera.txt", &camera_tiff()), false, false, None).photo), "null", "the name decides, not the bytes");
}

#[test]
fn the_wire_escapes_a_string_and_leaves_an_absent_fact_out() {
    let facts = RawFacts { model: Some("say \"hi\"".to_string()), iso: Some(100), ..Default::default() };
    assert_eq!(photo_json(&facts), r#"{"model":"say \"hi\"","iso":100}"#);
    let half = RawFacts { width: Some(6000), ..Default::default() };
    assert_eq!(photo_json(&half), "null", "one side of the size is no size");
    assert_eq!(photo_json(&RawFacts { height: Some(4), ..half }), r#"{"w":6000,"h":4}"#);
    assert_eq!(photo_json(&RawFacts::default()), "null");
}

#[test]
fn a_jpeg_reports_photo_facts_to_properties_and_never_to_the_meta_reply() {
    let d = TestDir::new("photojpeg");
    let p = write(&d, "holiday.JPG", &jpeg_with_exif(&camera_tiff(), 0));
    assert_eq!(photo_json(&photo(&p, true)), WIRE);
    // The column reads the same file through read(), which asks for no JPEG facts.
    let m = read(&p, false, false, None);
    assert_eq!(photo_json(&m.photo), "null", "a JPEG's column card stays as it is");
    assert_eq!((m.width, m.height), (64, 48), "the size still comes from the frame header");
    assert_eq!(photo_json(&photo(&write(&d, "holiday.jpeg", &jpeg_with_exif(&camera_tiff(), 0)), true)), WIRE);
}

#[test]
fn a_jpeg_without_an_exif_segment_or_without_a_jpeg_name_has_no_facts() {
    let d = TestDir::new("photojpegnone");
    assert_eq!(photo_json(&photo(&write(&d, "plain.jpg", &jpeg(64, 48)), true)), "null");
    assert_eq!(photo_json(&photo(&write(&d, "photo.png", &jpeg_with_exif(&camera_tiff(), 0)), true)), "null");
    assert_eq!(photo_json(&photo(&write(&d, "text.jpg", b"\xFF\xD8\xFF\xE1\x00"), true)), "null");
    assert_eq!(photo_json(&photo(&write(&d, "gone.jpg", b""), true)), "null");
}

#[test]
fn the_jpeg_read_stops_at_64_kib() {
    let d = TestDir::new("photojpegcap");
    let tiff = camera_tiff();
    // An Exif segment starting inside the cap is read; one starting past it is never reached.
    let near = write(&d, "near.jpg", &jpeg_with_exif(&tiff, 60_000));
    assert_eq!(photo_json(&photo(&near, true)), WIRE);
    // Two well-formed APP2 segments put the Exif segment past 64 KiB; only the read cap hides it.
    let far_bytes = jpeg_with_exif(&tiff, 66_000);
    assert!(far_bytes.len() > JPEG_EXIF_READ as usize, "the whole file is longer than the cap");
    let far = write(&d, "far.jpg", &far_bytes);
    assert_eq!(photo_json(&photo(&far, true)), "null");
    assert_eq!(exif_segment(&far_bytes).map(|t| t.len() >= tiff.len()), Some(true), "the uncut file does carry its Exif segment");
    assert_eq!(JPEG_EXIF_READ, 65_536);
}

#[test]
fn the_facts_ride_the_one_meta_reply_and_no_second_message_follows() {
    let d = TestDir::new("photoone");
    let p = write(&d, "one.cr2", &camera_tiff());
    let (tx, rx) = std::sync::mpsc::channel();
    spawn(5, p, false, false, None, 9, tx);
    let Ok(OpMsg::Meta { line }) = rx.recv_timeout(BOUND) else { panic!("no meta reply") };
    assert!(line.contains(WIRE) && line.ends_with(r#","token":9}"#), "{}", line);
    assert!(rx.recv_timeout(std::time::Duration::from_millis(200)).is_err(), "one request, one reply");
}
