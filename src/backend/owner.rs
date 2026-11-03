// Resolves a uid to its login name from /etc/passwd alone, never through getpwuid: that call goes
// through NSS and can wait on a network directory, and the meta thread must never hang the column on one.
use std::os::unix::fs::MetadataExt;
use std::path::Path;

const PASSWD: &str = "/etc/passwd";

// The owner of the path itself, so a symlink reports the link's owner as its row does; empty when unknown.
pub fn of(path: &Path) -> String {
    match path.symlink_metadata() {
        Ok(m) => name(m.uid()),
        Err(_) => String::new(),
    }
}

pub fn name(uid: u32) -> String {
    match std::fs::read_to_string(PASSWD) {
        Ok(text) => name_in(&text, uid),
        Err(_) => String::new(),
    }
}

// Sample input: gm:x:1000:1000::/home/gm:/usr/bin/bash
// A uid the file does not list answers the empty string, never the number dressed as a name.
fn name_in(passwd: &str, uid: u32) -> String {
    for line in passwd.lines() {
        let mut fields = line.split(':');
        let login = fields.next().unwrap_or("");
        // Field three is the uid; a line too short or non-numeric there is skipped, not a match.
        if fields.nth(1).and_then(|f| f.parse::<u32>().ok()) == Some(uid) {
            return login.to_string();
        }
    }
    String::new()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::backend::testdir::TestDir;

    const SAMPLE: &str = "root:x:0:0::/root:/usr/bin/bash\n\
bin:x:1:1::/:/usr/bin/nologin\n\
broken line with no fields\n\
short:x\n\
gm:x:1000:1000::/home/gm:/usr/bin/bash\n";

    #[test]
    fn the_uid_column_picks_the_login_and_a_malformed_line_is_skipped_not_matched() {
        assert_eq!(name_in(SAMPLE, 0), "root");
        assert_eq!(name_in(SAMPLE, 1000), "gm");
        assert_eq!(name_in(SAMPLE, 1), "bin");
        assert_eq!(name_in(SAMPLE, 4242), "", "an unknown uid is empty, never a number");
        assert_eq!(name_in("", 0), "");
    }

    // corner: every Linux box lists uid 0 as root in /etc/passwd, so this reads the real file.
    #[test]
    fn uid_zero_resolves_to_root_from_the_real_file() {
        assert_eq!(name(0), "root");
        assert_eq!(name(u32::MAX), "", "no account carries the largest uid");
    }

    // corner: the test runner is a local account on this box, so its own file resolves to a name.
    #[test]
    fn a_path_resolves_through_its_own_uid_and_a_missing_path_resolves_to_nothing() {
        let d = TestDir::new("owner");
        let p = d.file("mine.txt", "body");
        let uid = p.symlink_metadata().unwrap().uid();
        let passwd = std::fs::read_to_string(PASSWD).unwrap();
        assert_eq!(of(&p), name_in(&passwd, uid), "the path answer is the pure parser over the same inputs");
        assert!(!of(&p).is_empty(), "the test runner's uid is a local account on this box");
        assert_eq!(of(&d.join("never-existed")), "");
    }
}
