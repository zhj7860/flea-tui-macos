use std::collections::HashMap;
use std::path::PathBuf;

const MIME_ROOT: &str = "/usr/share/mime";

// A per-process, per-type cache, so every type is read from disk at most once, see docs/protocol.md "rows".
pub struct Kinds {
    cache: HashMap<String, Option<String>>,
    reads: u32,
}

impl Kinds {
    pub fn new() -> Kinds {
        Kinds { cache: HashMap::new(), reads: 0 }
    }

    // Test-only: pre-seeds the cache so a test never depends on the box's own /usr/share/mime, the same reason rows.rs's dbs() uses literal strings.
    #[cfg(test)]
    pub fn from_pairs(pairs: &[(&str, Option<&str>)]) -> Kinds {
        let cache = pairs.iter().map(|(k, v)| (k.to_string(), v.map(str::to_string))).collect();
        Kinds { cache, reads: 0 }
    }

    // A human description of a MIME type, read lazily and cached for the life of the process.
    pub fn comment(&mut self, mime: &str) -> Option<String> {
        if let Some(hit) = self.cache.get(mime) {
            return hit.clone();
        }
        self.reads += 1;
        let value = read_comment(mime);
        self.cache.insert(mime.to_string(), value.clone());
        value
    }

    // What the cache-hit test asserts on, kept in shipped code on purpose: a cache with no observable hit count is a cache nobody can test.
    #[allow(dead_code)]
    pub fn reads(&self) -> u32 {
        self.reads
    }
}

// Sample input, /usr/share/mime/image/jpeg.xml: "<comment>JPEG image</comment>".
fn read_comment(mime: &str) -> Option<String> {
    let path = PathBuf::from(MIME_ROOT).join(format!("{}.xml", mime));
    let text = std::fs::read_to_string(path).ok()?;
    first_untranslated_comment(&text)
}

// The first <comment> carrying no xml:lang attribute, not the first <comment> of any kind, see docs/protocol.md "rows".
fn first_untranslated_comment(text: &str) -> Option<String> {
    let mut rest = text;
    loop {
        let start = rest.find("<comment")?;
        rest = &rest[start..];
        let tag_end = rest.find('>')?;
        let tag = &rest[..tag_end];
        rest = &rest[tag_end + 1..];
        if tag.contains("xml:lang") {
            continue;
        }
        let close = rest.find("</comment>")?;
        return Some(rest[..close].to_string());
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Sample input, the shape of /usr/share/mime/application/msword.xml: update-mime-database writes every translated comment before the untranslated one.
    const MSWORD_SHAPED: &str = concat!(
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>\n",
        "<mime-type xmlns=\"http://www.freedesktop.org/standards/shared-mime-info\" type=\"application/msword\">\n",
        "  <comment xml:lang=\"zh-Hant-TW\">Word 文件</comment>\n",
        "  <comment xml:lang=\"vi\">Tài liệu Word</comment>\n",
        "  <comment>Word document</comment>\n",
        "</mime-type>\n",
    );

    #[test]
    fn a_translated_comment_first_does_not_win() {
        assert_eq!(first_untranslated_comment(MSWORD_SHAPED).as_deref(), Some("Word document"));
    }

    #[test]
    fn a_type_with_no_untranslated_comment_answers_none() {
        let translated_only = "<mime-type type=\"application/x-thing\">\n  <comment xml:lang=\"de\">Datei</comment>\n</mime-type>\n";
        assert_eq!(first_untranslated_comment(translated_only), None);
    }

    #[test]
    fn a_missing_mime_root_answers_none_not_a_panic() {
        assert_eq!(first_untranslated_comment(""), None);
        assert_eq!(first_untranslated_comment("<mime-type></mime-type>"), None);
    }

    // The only test here that reads this box's own database, and it asserts shape rather than wording, because update-mime-database merges /usr/share/mime/packages and an installed application supplies the English string.
    #[test]
    fn the_live_database_answers_a_real_type_in_ascii() {
        let mut db = Kinds::new();
        let jpeg = db.comment("image/jpeg").expect("shared-mime-info is a hard dependency and ships image/jpeg");
        assert!(!jpeg.is_empty() && !jpeg.contains('<'), "got {jpeg}");
        // msword.xml opens with zh-Hant-TW, so a reader that took the first comment of any kind would answer non-ASCII here.
        let msword = db.comment("application/msword").expect("shared-mime-info ships application/msword");
        assert!(msword.is_ascii(), "got a translated comment: {msword}");
        // corner: a type with no XML answers None and the caller falls back to the icon name.
        assert_eq!(db.comment("application/x-nonexistent-type"), None);
    }

    #[test]
    fn comment_is_read_once_per_type() {
        let mut db = Kinds::new();
        let _ = db.comment("image/jpeg");
        let _ = db.comment("image/jpeg");
        assert_eq!(db.reads(), 1);
    }

    #[test]
    fn from_pairs_never_touches_disk() {
        let mut db = Kinds::from_pairs(&[("text/plain", Some("Plain Text Document"))]);
        assert_eq!(db.comment("text/plain").as_deref(), Some("Plain Text Document"));
        // A pre-seeded entry is answered straight from the cache, so it costs no read.
        assert_eq!(db.reads(), 0);
    }
}
