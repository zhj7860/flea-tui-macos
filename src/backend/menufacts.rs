// Properties on a file asks for its codecs, bit rate and photo facts on the menu worker, under the request's own cancel, and only where the card can say more.
use super::exiffacts::{self, Photo};
use super::mediaprobe::{self, Media};
use super::menu_actions::{response, Selected};
use super::opsreq::OpMsg;
use super::trashmanifest::Cancellation;
use crate::json::{escape, field_usize};
use std::path::Path;
use std::sync::mpsc::Sender;

// The containers ffprobe is worth a process for; a photo or a document is never probed.
const VIDEO: &[&str] = &["mp4", "m4v", "mkv", "webm", "mov", "avi", "ts", "mts", "m2ts", "mpg", "mpeg", "flv", "3gp", "wmv", "ogv", "vob"];

// Sample input: {"c":"menuaction","op":"facts","id":4} answers one line, the raw facts the file has and empty or zero for the rest.
// False once the receiver is gone, so the worker ends with it.
pub(super) fn serve(line: &str, id: usize, items: &[Selected], replies: &Sender<OpMsg>, cancel: &Cancellation) -> bool {
    let send = |fields: Result<String, String>| replies.send(OpMsg::Meta { line: response(line, fields) }).is_ok();
    if id == 0 || field_usize(line, "id") != Some(id) || items.len() != 1 {
        return send(Err("Menu selection expired; reopen the menu.".into()));
    }
    // Looked at without a follow or an open, so a fifo, a device or a link is refused before anything blocks.
    match items[0].current() {
        Ok(meta) if meta.is_file() => {}
        Ok(_) => return send(Err("Only a file has codecs or photo facts.".into())),
        Err(error) => return send(Err(error)),
    }
    let cancelled = || send(Ok(r#""cancelled":true"#.to_string()));
    if cancel.check().is_err() {
        return cancelled();
    }
    let path = &items[0].path;
    let media = if is_video(path) { mediaprobe::probe(path) } else { Media::default() };
    if cancel.check().is_err() {
        return cancelled();
    }
    send(Ok(fields(&media, &exiffacts::read(path))))
}

pub(super) fn fields(media: &Media, photo: &Photo) -> String {
    format!(
        r#""vcodec":"{}","acodec":"{}","bps":{},"make":"{}","model":"{}","lens":"{}","shutter":[{},{}],"fnumber":[{},{}],"iso":{},"taken":"{}""#,
        escape(&media.video_codec), escape(&media.audio_codec), media.bit_rate, escape(&photo.make), escape(&photo.model), escape(&photo.lens),
        photo.shutter.0, photo.shutter.1, photo.fnumber.0, photo.fnumber.1, photo.iso, escape(&photo.taken)
    )
}

pub(super) fn is_video(path: &Path) -> bool {
    path.extension().and_then(|e| e.to_str()).is_some_and(|e| VIDEO.iter().any(|v| e.eq_ignore_ascii_case(v)))
}

#[cfg(test)]
#[path = "menufacts_tests.rs"]
mod tests;
