use super::*;
use crate::backend::mediaprobe::Media;
use crate::backend::testdir::TestDir;

fn photo() -> Photo {
    Photo { make: "Canon".into(), model: "Canon EOS R6".into(), lens: "RF35mm \"F1.8\"".into(), shutter: (1, 250), fnumber: (28, 10), iso: 400, taken: "2026:09:12 18:31:07".into() }
}

fn ask(path: &std::path::Path, id: usize, asked: usize) -> String {
    let (tx, rx) = std::sync::mpsc::channel();
    let items = [Selected::inspect(&path.to_string_lossy()).unwrap()];
    assert!(serve(&format!(r#"{{"c":"menuaction","op":"facts","id":{}}}"#, asked), id, &items, &tx, &Cancellation::default()));
    let mut lines = Vec::new();
    while let Ok(OpMsg::Meta { line }) = rx.try_recv() { lines.push(line); }
    assert_eq!(lines.len(), 1, "one reply per request");
    lines.remove(0)
}

// A JPEG whose APP1 holds IFD0 with a Make and a Model, so the wire shows the photo fields.
fn jpeg_with_make(make: &str) -> Vec<u8> {
    let mut tiff = b"II".to_vec();
    tiff.extend_from_slice(&42u16.to_le_bytes());
    tiff.extend_from_slice(&8u32.to_le_bytes());
    tiff.extend_from_slice(&1u16.to_le_bytes());
    tiff.extend_from_slice(&0x010Fu16.to_le_bytes());
    tiff.extend_from_slice(&2u16.to_le_bytes());
    let text = format!("{}\0", make);
    tiff.extend_from_slice(&(text.len() as u32).to_le_bytes());
    tiff.extend_from_slice(&(8u32 + 2 + 12 + 4).to_le_bytes());
    tiff.extend_from_slice(&[0, 0, 0, 0]);
    tiff.extend_from_slice(text.as_bytes());
    let mut v = vec![0xFF, 0xD8, 0xFF, 0xE1];
    v.extend_from_slice(&((tiff.len() + 8) as u16).to_be_bytes());
    v.extend_from_slice(b"Exif\0\0");
    v.extend_from_slice(&tiff);
    v.extend_from_slice(&[0xFF, 0xC0, 0x00, 0x11, 0x08, 0, 8, 0, 8, 3]);
    v.extend_from_slice(&[0u8; 8]);
    v
}

#[test]
fn the_wire_fields_are_the_raw_facts_in_the_names_the_card_reads() {
    let media = Media { video_codec: "h264".into(), audio_codec: "aac".into(), bit_rate: 8_100_000, ..Media::default() };
    let line = format!("{{{}}}", fields(&media, &Photo::default()));
    let doc = crate::jsondoc::parse(&line).expect("valid json");
    assert_eq!(line, r#"{"vcodec":"h264","acodec":"aac","bps":8100000,"make":"","model":"","lens":"","shutter":[0,0],"fnumber":[0,0],"iso":0,"taken":""}"#);
    let _ = doc;
    let line = format!("{{{}}}", fields(&Media::default(), &photo()));
    assert!(crate::jsondoc::parse(&line).is_ok(), "a quote in a lens name is escaped: {line}");
    assert!(line.contains(r#""make":"Canon","model":"Canon EOS R6","lens":"RF35mm \"F1.8\"","shutter":[1,250],"fnumber":[28,10],"iso":400,"taken":"2026:09:12 18:31:07""#), "{line}");
}

#[test]
fn only_a_video_container_costs_a_probe() {
    for name in ["a.mp4", "A.MKV", "b.webm", "c.mov", "d.avi", "e.m4v", "f.ts", "g.mts", "h.m2ts", "i.mpg", "j.flv", "k.3gp", "l.wmv", "m.ogv", "n.vob"] {
        assert!(is_video(std::path::Path::new(name)), "{name}");
    }
    for name in ["a.jpg", "a.cr3", "a.txt", "mp4", "a.mp4.txt", "a.mp3", "a", ".mp4x"] {
        assert!(!is_video(std::path::Path::new(name)), "{name}");
    }
}

#[test]
fn a_photo_answers_its_facts_and_a_text_file_answers_ok_with_none() {
    let d = TestDir::new("menufactsjpeg");
    let p = d.join("shot.jpg");
    std::fs::write(&p, jpeg_with_make("Canon")).unwrap();
    let line = ask(&p, 7, 7);
    assert!(line.starts_with(r#"{"t":"menuaction","id":7,"op":"facts","ok":true,"#), "{line}");
    assert!(line.contains(r#""make":"Canon""#), "{line}");
    let t = d.file("note.txt", "hello\n");
    let line = ask(&t, 7, 7);
    assert!(line.contains(r#""ok":true"#) && line.contains(r#""vcodec":"","#) && line.contains(r#""make":"","#), "{line}");
}

#[test]
fn a_stale_id_a_folder_and_a_vanished_file_are_refused() {
    let d = TestDir::new("menufactsrefuse");
    let p = d.file("note.txt", "x");
    assert!(ask(&p, 7, 8).contains(r#""ok":false"#), "an id that is not the snapshot");
    assert!(ask(&p, 0, 0).contains(r#""ok":false"#), "no snapshot");
    let dir = d.dir("folder");
    let line = ask(&dir, 7, 7);
    assert!(line.contains(r#""ok":false"#) && line.contains("Only a file"), "{line}");
    let gone = d.file("gone.txt", "x");
    let items = [Selected::inspect(&gone.to_string_lossy()).unwrap()];
    std::fs::remove_file(&gone).unwrap();
    let (tx, rx) = std::sync::mpsc::channel();
    assert!(serve(r#"{"c":"menuaction","op":"facts","id":7}"#, 7, &items, &tx, &Cancellation::default()));
    let OpMsg::Meta { line } = rx.try_recv().unwrap() else { panic!() };
    assert!(line.contains(r#""ok":false"#), "{line}");
}

#[test]
fn a_fifo_is_never_opened() {
    let d = TestDir::new("menufactsfifo");
    let fifo = d.join("pipe.jpg");
    crate::backend::fifotest::mkfifo(&fifo);
    let line = crate::backend::fifotest::within("a facts request on a fifo", move || ask(&fifo, 7, 7));
    assert!(line.contains(r#""ok":false"#), "{line}");
}

#[test]
fn a_cancelled_request_is_answered_cancelled_and_reads_nothing() {
    let d = TestDir::new("menufactscancel");
    let p = d.join("shot.jpg");
    std::fs::write(&p, jpeg_with_make("Canon")).unwrap();
    let (tx, rx) = std::sync::mpsc::channel();
    let items = [Selected::inspect(&p.to_string_lossy()).unwrap()];
    let cancel = Cancellation::default();
    let _next = cancel.next();
    assert!(serve(r#"{"c":"menuaction","op":"facts","id":7}"#, 7, &items, &tx, &cancel));
    let OpMsg::Meta { line } = rx.try_recv().unwrap() else { panic!() };
    assert!(line.contains(r#""cancelled":true"#) && !line.contains("Canon"), "{line}");
}
