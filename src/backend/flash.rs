// The flasher's shared wire: every flash line the backend prints, built in one place.
use crate::json::{escape, field_str, field_usize};

// Four 4 MiB buffers, the benchmark's own starting point; both knobs stay constants, never settings.
pub const CHUNK_BYTES: usize = 4 * 1024 * 1024;
// Four in flight, so the kernel queues sixteen 1 MiB requests per call on this box.
pub const CHUNK_COUNT: usize = 4;
// One progress line per 150 ms, the transfer rule.
pub const PROGRESS_EVERY_MS: u64 = 150;
// A decompressor silent this long with no input progress is a stall.
pub const STALL_SECS: u64 = 30;
// A cancelled or failed flash zeroes this much at each end, so no half image looks bootable.
pub const WIPE_BYTES: u64 = 1024 * 1024;
// O_DIRECT moves in multiples of the logical block size from an aligned buffer.
pub const DIRECT_ALIGN: usize = 4096;

// Every image name suffix the pane accepts and the kind each answers; the probe and the chooser both read this one table.
pub const IMAGE_SUFFIXES: [(&str, &str); 8] = [
    (".img.xz", "xz"),
    (".img.gz", "gz"),
    (".img.zst", "zst"),
    (".img.bz2", "bz2"),
    (".iso", "iso"),
    (".img", "img"),
    (".raw", "img"),
    (".zip", "zip"),
];

// The refusal a drive carries in flashtargets, empty when the drive takes the image.
pub const REFUSED_SMALL: &str = "small";
pub const REFUSED_READONLY: &str = "readonly";
pub const REFUSED_HOLDSIMAGE: &str = "holdsimage";
pub const REFUSED_MEMBER: &str = "member";

// One drive as flashtargets lists it, in /sys/block order.
pub struct Drive {
    pub dev: String,
    pub seq: u64,
    pub serial: String,
    pub label: String,
    pub model: String,
    pub bytes: u64,
    pub volumes: Vec<String>,
    pub refused: String,
}

// Sample output: {"t":"flashimage","path":"/d/a.img.xz","kind":"xz","bytes":10,"unpacked":20,"known":true,"member":""}.
pub fn flashimage_line(path: &str, kind: &str, bytes: u64, unpacked: u64, known: bool, member: &str) -> String {
    format!(r#"{{"t":"flashimage","path":"{}","kind":"{}","bytes":{},"unpacked":{},"known":{},"member":"{}"}}"#,
        escape(path), escape(kind), bytes, unpacked, known, escape(member))
}

// Sample output: {"t":"flashtargets","drives":[{"dev":"sda","seq":2,"serial":"9","label":"128GB","model":"General USB Flash Disk","bytes":124623257600,"volumes":["128GB"],"refused":""}]}.
pub fn flashtargets_line(drives: &[Drive]) -> String {
    let mut out = String::from(r#"{"t":"flashtargets","drives":["#);
    for (i, d) in drives.iter().enumerate() {
        if i > 0 {
            out.push(',');
        }
        let mut vols = String::from("[");
        for (j, v) in d.volumes.iter().enumerate() {
            if j > 0 {
                vols.push(',');
            }
            vols.push('"');
            vols.push_str(&escape(v));
            vols.push('"');
        }
        vols.push(']');
        out.push_str(&format!(r#"{{"dev":"{}","seq":{},"serial":"{}","label":"{}","model":"{}","bytes":{},"volumes":{},"refused":"{}"}}"#,
            escape(&d.dev), d.seq, escape(&d.serial), escape(&d.label), escape(&d.model), d.bytes, vols, escape(&d.refused)));
    }
    out.push_str("]}");
    out
}

// Sample output: {"t":"flashstarted","id":31,"total":124623257600,"known":true}.
pub fn flashstarted_line(id: usize, total: u64, known: bool) -> String {
    format!(r#"{{"t":"flashstarted","id":{},"total":{},"known":{}}}"#, id, total, known)
}

// Sample output: {"t":"flashprogress","id":31,"phase":"write","bytes":1048576,"total":124623257600,"permille":8}.
pub fn flashprogress_line(id: usize, phase: &str, bytes: u64, total: u64, permille: u64) -> String {
    format!(r#"{{"t":"flashprogress","id":{},"phase":"{}","bytes":{},"total":{},"permille":{}}}"#,
        id, escape(phase), bytes, total, permille.min(1000))
}

// Sample output: {"t":"flashdone","id":31,"ok":true,"phase":"verify","at":0,"err":"","blank":false}.
pub fn flashdone_line(id: usize, ok: bool, phase: &str, at: u64, err: &str, blank: bool) -> String {
    format!(r#"{{"t":"flashdone","id":{},"ok":{},"phase":"{}","at":{},"err":"{}","blank":{}}}"#,
        id, ok, escape(phase), at, escape(err), blank)
}

// Sample output: {"t":"flasheject","ok":true,"err":""}.
pub fn flasheject_line(ok: bool, err: &str) -> String {
    format!(r#"{{"t":"flasheject","ok":{},"err":"{}"}}"#, ok, escape(err))
}

// Bytes over total in permille, clamped; unknown totals never reach this, they follow the input offset.
pub fn permille(bytes: u64, total: u64) -> u64 {
    if total == 0 {
        return 0;
    }
    bytes.saturating_mul(1000).checked_div(total).unwrap_or(1000).min(1000)
}

// The five flash requests, parsed off the wire beside the other requests in proto.rs.
pub enum Req {
    Image { path: String },
    Targets { image: String },
    Flash { id: usize, image: String, dev: String, seq: usize, serial: String, bytes: u64 },
    Cancel { id: usize },
    Eject { dev: String, seq: usize },
}

// Sample input: {"c":"flash","id":31,...}; anything but the five exact names is None, so an unknown flashxyz answers silence.
pub fn parse(c: &str, line: &str) -> Option<Req> {
    match c {
        "flashimage" => Some(Req::Image { path: field_str(line, "path").unwrap_or_default() }),
        "flashtargets" => Some(Req::Targets { image: field_str(line, "image").unwrap_or_default() }),
        "flash" => Some(Req::Flash {
            id: field_usize(line, "id").unwrap_or(0),
            image: field_str(line, "image").unwrap_or_default(),
            dev: field_str(line, "dev").unwrap_or_default(),
            seq: field_usize(line, "seq").unwrap_or(0),
            serial: field_str(line, "serial").unwrap_or_default(),
            bytes: field_usize(line, "bytes").unwrap_or(0) as u64,
        }),
        "flashcancel" => Some(Req::Cancel { id: field_usize(line, "id").unwrap_or(0) }),
        "flasheject" => Some(Req::Eject {
            dev: field_str(line, "dev").unwrap_or_default(),
            seq: field_usize(line, "seq").unwrap_or(0),
        }),
        _ => None,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_progress_line_clamps_its_permille() {
        assert!(flashprogress_line(1, "write", 9, 10, 900).contains(r#""permille":900"#));
        assert!(flashprogress_line(1, "write", 20, 10, 2000).contains(r#""permille":1000"#));
    }

    #[test]
    fn an_empty_target_list_is_still_a_line() {
        assert_eq!(flashtargets_line(&[]), r#"{"t":"flashtargets","drives":[]}"#);
    }

    #[test]
    fn permille_divides_bytes_by_total() {
        assert_eq!(permille(0, 0), 0);
        assert_eq!(permille(5, 10), 500);
        assert_eq!(permille(10, 10), 1000);
        assert_eq!(permille(11, 10), 1000);
    }
}

#[cfg(test)]
#[path = "flash_tests.rs"]
mod wire_tests;
