use std::collections::HashMap;

pub struct Names {
    generic: HashMap<String, String>,
}

const GENERIC_ICONS: &str = "/usr/share/mime/generic-icons";
const FOLDER: &str = "folder";
const UNKNOWN: &str = "text-x-generic";
// The icon naming spec's generic file, for the application types generic-icons does not list.
const GENERIC: &str = "application-x-generic";
// The execute bits of st_mode, the same three Row.nameColor reads to colour an executable.
pub(crate) const ANY_EXECUTE_BIT: u32 = 0o111;
// The file type bits of st_mode, so a symlink's own mode is told apart from the file it names.
const S_IFMT: u32 = 0o170000;
const S_IFLNK: u32 = 0o120000;

impl Names {
    pub fn load() -> Names {
        match std::fs::read_to_string(GENERIC_ICONS) {
            Ok(text) => Names::from_str(&text),
            Err(_) => Names::from_str(""),
        }
    }

    // Sample input, /usr/share/mime/generic-icons: "model/vrml:x-office-document", one pair per line.
    pub fn from_str(text: &str) -> Names {
        let mut generic = HashMap::new();
        for line in text.lines() {
            if line.starts_with('#') || line.is_empty() {
                continue;
            }
            if let Some((mime, icon)) = line.split_once(':') {
                if !mime.is_empty() && !icon.is_empty() {
                    generic.insert(mime.to_string(), icon.to_string());
                }
            }
        }
        Names { generic }
    }

    // Always returns a real icon name, because a row with no icon is a worse bug than a wrong icon.
    pub fn icon_for(&self, mime: Option<&str>, is_dir: bool, mode: u32) -> &str {
        if is_dir {
            return FOLDER;
        }
        let mime = match mime {
            Some(m) if !m.is_empty() => m,
            // No glob names this file, so its execute bit alone says it is a program, as it does for an unlisted application type.
            _ if is_program(mode) => return "application-x-executable",
            _ => return UNKNOWN,
        };
        if let Some(icon) = self.generic.get(mime) {
            return icon;
        }
        // The icon naming spec's fallback: image/jpeg has no entry but image-x-generic exists.
        match mime.split_once('/') {
            Some(("application", _)) => {
                if mode & ANY_EXECUTE_BIT != 0 {
                    "application-x-executable"
                } else {
                    GENERIC
                }
            }
            Some((class, _)) if !class.is_empty() => class_icon(class),
            _ => UNKNOWN,
        }
    }
}

// A symlink's mode is the link's own, which always carries execute bits, so only a file's own bits count.
fn is_program(mode: u32) -> bool {
    mode & S_IFMT != S_IFLNK && mode & ANY_EXECUTE_BIT != 0
}

// Returning a borrow rules out building "<class>-x-generic", so the shipped class names are literals here.
fn class_icon(class: &str) -> &'static str {
    match class {
        "image" => "image-x-generic",
        "video" => "video-x-generic",
        "audio" => "audio-x-generic",
        "text" => "text-x-generic",
        "font" => "font-x-generic",
        _ => UNKNOWN,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    // Sample input, rows copied from /usr/share/mime/generic-icons: one "type:icon" pair per line.
    const GENERIC_ROWS: &str = concat!(
        "model/vrml:x-office-document\n",
        "application/x-executable:application-x-executable\n",
        "application/zip:package-x-generic\n",
    );

    // A fixture table rather than this box's own, because update-mime-database merges /usr/share/mime/packages and an installed application can add the very rows these fallbacks are asserted to miss.
    fn names() -> Names {
        Names::from_str(GENERIC_ROWS)
    }

    // A regular file at 0644, which is what every mode-independent case here means.
    const PLAIN: u32 = 0o100644;
    const EXECUTABLE: u32 = 0o100755;

    #[test]
    fn a_directory_is_a_folder_whatever_its_name() {
        let n = names();
        assert_eq!(n.icon_for(Some("image/jpeg"), true, 0o040755), "folder");
        assert_eq!(n.icon_for(None, true, 0o040755), "folder");
    }

    #[test]
    fn the_generic_icons_table_wins_when_it_has_an_answer() {
        let n = names();
        assert_eq!(n.icon_for(Some("model/vrml"), false, PLAIN), "x-office-document");
    }

    #[test]
    fn an_unlisted_type_falls_back_to_its_media_class() {
        let n = names();
        assert_eq!(n.icon_for(Some("image/jpeg"), false, PLAIN), "image-x-generic");
        assert_eq!(n.icon_for(Some("video/mp4"), false, PLAIN), "video-x-generic");
        assert_eq!(n.icon_for(Some("audio/flac"), false, PLAIN), "audio-x-generic");
    }

    #[test]
    fn an_unknown_type_is_still_a_real_icon_name() {
        let n = names();
        assert_eq!(n.icon_for(None, false, PLAIN), "text-x-generic");
        assert_eq!(n.icon_for(Some("nonsense/nothing"), false, PLAIN), "text-x-generic");
    }

    #[test]
    fn a_malformed_type_cannot_produce_an_empty_name() {
        let n = names();
        assert_eq!(n.icon_for(Some(""), false, PLAIN), "text-x-generic");
        assert_eq!(n.icon_for(Some("noslash"), false, PLAIN), "text-x-generic");
    }

    #[test]
    fn a_missing_table_still_answers() {
        let n = Names::from_str("");
        assert_eq!(n.icon_for(Some("image/jpeg"), false, PLAIN), "image-x-generic");
    }

    #[test]
    fn the_folder_arm_answers_before_the_mime_type_or_the_mode_is_read() {
        let n = names();
        // A symlink to a directory reaches this arm with is_dir already true, from the OR on Meta::target_is_dir in proto::rows_line; that OR is covered by meta.rs and by the linkdir pair in tests/protocol.sh.
        assert_eq!(n.icon_for(Some("text/plain"), true, 0o120777), "folder");
    }

    #[test]
    fn an_unlisted_application_type_is_not_an_executable_unless_it_is_one() {
        let n = names();
        // application/pkcs7-mime is unlisted in the fixture, as it is in this box's own table.
        assert_eq!(n.icon_for(Some("application/pkcs7-mime"), false, PLAIN), "application-x-generic");
        assert_eq!(n.icon_for(Some("application/x-sharedlib"), false, EXECUTABLE), "application-x-executable");
    }

    #[test]
    fn a_shared_object_draws_the_program_mark_only_with_its_execute_bit() {
        let n = names();
        assert_eq!(n.icon_for(Some("application/x-sharedlib"), false, PLAIN), "application-x-generic");
        assert_eq!(n.icon_for(Some("application/x-sharedlib"), false, EXECUTABLE), "application-x-executable");
    }

    #[test]
    fn an_extensionless_program_draws_the_program_mark_from_its_execute_bit() {
        // A PIE or non-PIE ELF named with no extension has no glob, so the mode is the only signal the row has.
        let n = names();
        assert_eq!(n.icon_for(None, false, EXECUTABLE), "application-x-executable");
        assert_eq!(n.icon_for(Some(""), false, EXECUTABLE), "application-x-executable");
        assert_eq!(n.icon_for(None, false, PLAIN), "text-x-generic");
    }

    #[test]
    fn a_symlink_never_draws_the_program_mark_from_its_own_execute_bits() {
        // lstat gives a link mode 0777, so its own bits say nothing about the file it names.
        let n = names();
        assert_eq!(n.icon_for(None, false, 0o120777), "text-x-generic");
    }

    #[test]
    fn a_listed_application_type_still_wins_over_the_class_fallback() {
        let n = names();
        // application/x-executable and application/zip both have generic-icons entries on a real box.
        assert_eq!(n.icon_for(Some("application/x-executable"), false, PLAIN), "application-x-executable");
        assert_eq!(n.icon_for(Some("application/zip"), false, PLAIN), "package-x-generic");
    }

    #[test]
    fn a_vanished_row_reports_mode_zero_and_still_gets_a_real_name() {
        let n = names();
        assert_eq!(n.icon_for(Some("application/pkcs7-mime"), false, 0), "application-x-generic");
    }

    // The only test here that reads this box's own table, and it asserts the module's promise rather than any row's value.
    #[test]
    fn the_live_table_parses_and_never_answers_an_empty_name() {
        let n = Names::load();
        assert_eq!(n.icon_for(None, true, 0o040755), "folder");
        for mime in ["image/jpeg", "application/zip", "application/pkcs7-mime", "nonsense/nothing", ""] {
            assert!(!n.icon_for(Some(mime), false, PLAIN).is_empty(), "empty name for {mime}");
        }
    }
}
