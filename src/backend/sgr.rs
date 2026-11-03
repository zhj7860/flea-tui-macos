// bat's SGR stream as role runs for the code preview: the eight ANSI foregrounds become roles, everything else is dropped.

// A line is its runs in order, each a role (0 foreground, 1 red, 2 green, 3 yellow, 4 blue, 5 magenta, 6 cyan) and its text.
pub type Line = Vec<(u8, String)>;

const ESC: u8 = 0x1b;
const BEL: u8 = 0x07;

// Sample input: b"\x1b[35mfn\x1b[0m \x1b[34mmain\x1b[0m() {}\n" gives [[(5,"fn"),(0," "),(4,"main"),(0,"() {}")]].
// A role set before a newline carries into the next line, and a CR right before a newline is dropped.
pub fn parse(bytes: &[u8]) -> Vec<Line> {
    let mut lines = Vec::new();
    let mut line: Line = Vec::new();
    let mut text: Vec<u8> = Vec::new();
    let mut role = 0u8;
    let mut at = 0;
    while at < bytes.len() {
        match bytes[at] {
            ESC => {
                let (next, params) = escape(bytes, at);
                if let Some(params) = params {
                    let new = apply(params, role);
                    if new != role {
                        flush(&mut line, &mut text, role);
                        role = new;
                    }
                }
                at = next;
            }
            b'\n' => {
                flush(&mut line, &mut text, role);
                if let Some(last) = line.last_mut() {
                    if last.1.ends_with('\r') {
                        last.1.pop();
                    }
                    if last.1.is_empty() {
                        line.pop();
                    }
                }
                lines.push(std::mem::take(&mut line));
                at += 1;
            }
            b => {
                text.push(b);
                at += 1;
            }
        }
    }
    flush(&mut line, &mut text, role);
    if !line.is_empty() {
        lines.push(line);
    }
    lines
}

// A run next to one of the same role joins it, since bat resets after every token.
fn flush(line: &mut Line, text: &mut Vec<u8>, role: u8) {
    if text.is_empty() {
        return;
    }
    let piece = String::from_utf8_lossy(text).into_owned();
    match line.last_mut() {
        Some(last) if last.0 == role => last.1.push_str(&piece),
        _ => line.push((role, piece)),
    }
    text.clear();
}

// Reads one escape starting at the ESC at `at`: where the text resumes, and the parameters when it is an SGR (CSI ... m).
// Sample input: b"\x1b[1;33mx" gives (5, Some(b"1;33")); b"\x1b]0;title\x07x" gives (10, None); a cut-off escape ends the input.
fn escape(bytes: &[u8], at: usize) -> (usize, Option<&[u8]>) {
    let Some(&kind) = bytes.get(at + 1) else { return (bytes.len(), None) };
    match kind {
        b'[' => {
            let start = at + 2;
            let mut end = start;
            while end < bytes.len() && (0x20..=0x3f).contains(&bytes[end]) {
                end += 1;
            }
            match bytes.get(end) {
                Some(b'm') => (end + 1, Some(&bytes[start..end])),
                Some(0x40..=0x7e) => (end + 1, None),
                Some(_) => (end, None),
                None => (bytes.len(), None),
            }
        }
        // String escapes (OSC, DCS, SOS, PM, APC) run to BEL or ESC \.
        b']' | b'P' | b'X' | b'^' | b'_' => {
            let mut end = at + 2;
            while end < bytes.len() && bytes[end] != BEL && !(bytes[end] == ESC && bytes.get(end + 1) == Some(&b'\\')) {
                end += 1;
            }
            let after = if bytes.get(end) == Some(&BEL) { end + 1 } else { end + 2 };
            (after.min(bytes.len()), None)
        }
        // A short escape: intermediate bytes then one final byte, as in ESC ( B.
        _ => {
            let mut end = at + 1;
            while end < bytes.len() && (0x20..=0x2f).contains(&bytes[end]) {
                end += 1;
            }
            match bytes.get(end) {
                Some(0x30..=0x7e) => (end + 1, None),
                Some(_) => (end, None),
                None => (bytes.len(), None),
            }
        }
    }
}

// Sample input: b"1;33" from role 0 gives 3 (bold dropped); b"38;5;208" gives 0; b"0" gives 0; b"44" keeps the role.
fn apply(params: &[u8], mut role: u8) -> u8 {
    let numbers: Vec<Option<u16>> = params
        .split(|&b| b == b';')
        .map(|p| if p.is_empty() { Some(0) } else { std::str::from_utf8(p).ok().and_then(|s| s.parse().ok()) })
        .collect();
    let mut i = 0;
    while i < numbers.len() {
        match numbers[i] {
            Some(0 | 30 | 37 | 39 | 90 | 97) => role = 0,
            Some(n @ 31..=36) => role = (n - 30) as u8,
            Some(n @ 91..=96) => role = (n - 90) as u8,
            // An extended colour carries its own parameters: 5;n or 2;r;g;b. A foreground is role 0, a background is dropped.
            Some(code @ (38 | 48 | 58)) => {
                if code == 38 {
                    role = 0;
                }
                i += match numbers.get(i + 1) {
                    Some(Some(5)) => 2,
                    Some(Some(2)) => 4,
                    _ => 0,
                };
            }
            _ => {}
        }
        i += 1;
    }
    role
}

#[cfg(test)]
mod tests {
    use super::*;

    fn one(input: &str) -> Line {
        let lines = parse(input.as_bytes());
        assert_eq!(lines.len(), 1, "one line in: {input:?}");
        lines.into_iter().next().unwrap()
    }

    fn run(role: u8, text: &str) -> (u8, String) {
        (role, text.to_string())
    }

    #[test]
    fn each_foreground_code_maps_to_its_role() {
        for (code, role) in [(31, 1), (32, 2), (33, 3), (34, 4), (35, 5), (36, 6), (91, 1), (92, 2), (93, 3), (94, 4), (95, 5), (96, 6)] {
            assert_eq!(one(&format!("\x1b[{code}mx\x1b[0m")), vec![run(role, "x")], "code {code}");
        }
    }

    #[test]
    fn the_neutral_codes_and_extended_colours_are_foreground() {
        for code in ["30", "37", "39", "90", "97", "38;5;208", "38;2;10;20;30"] {
            assert_eq!(one(&format!("\x1b[35ma\x1b[{code}mb")), vec![run(5, "a"), run(0, "b")], "code {code}");
        }
    }

    #[test]
    fn a_reset_ends_the_role_mid_line() {
        assert_eq!(one("\x1b[32mab\x1b[0mcd"), vec![run(2, "ab"), run(0, "cd")]);
        assert_eq!(one("\x1b[32mab\x1b[mcd\x1b[0mef"), vec![run(2, "ab"), run(0, "cdef")]);
    }

    #[test]
    fn neighbouring_runs_of_one_role_are_one_run() {
        assert_eq!(one("\x1b[32m\"\x1b[0m\x1b[32mx\x1b[0m\x1b[32m\"\x1b[0m; }"), vec![run(2, "\"x\""), run(0, "; }")]);
        assert_eq!(one("a\x1b[0mb\x1b[39mc"), vec![run(0, "abc")]);
    }

    #[test]
    fn bold_italic_underline_and_backgrounds_are_dropped() {
        assert_eq!(one("\x1b[1;33mx"), vec![run(3, "x")]);
        for code in ["1", "3", "4", "22", "44", "104", "49", "48;5;9", "48;2;1;2;3", "58;5;9", "7"] {
            assert_eq!(one(&format!("\x1b[36ma\x1b[{code}mb")), vec![run(6, "ab")], "code {code}");
        }
        assert_eq!(one("\x1b[48;5;9;31mx"), vec![run(1, "x")], "the parameters after a background still apply");
    }

    #[test]
    fn a_run_split_across_lines_keeps_its_role() {
        let lines = parse(b"\x1b[32m/* a\nb */\x1b[0m c\n");
        assert_eq!(lines, vec![vec![run(2, "/* a")], vec![run(2, "b */"), run(0, " c")]]);
    }

    #[test]
    fn any_other_escape_is_stripped() {
        let sample = "a\x1b[2Jb\x1b]0;title\x07c\x1b]8;;http://x\x1b\\d\x1b(Be\x1b[?25lf\x1b[3;4Hg";
        assert_eq!(one(sample), vec![run(0, "abcdefg")]);
        assert_eq!(one("x\x1b[31"), vec![run(0, "x")], "a cut-off sequence ends the input");
        assert_eq!(one("x\x1b"), vec![run(0, "x")]);
    }

    #[test]
    fn invalid_utf8_becomes_the_replacement_character() {
        assert_eq!(parse(b"ok \xff\xfe bad\n"), vec![vec![run(0, "ok \u{fffd}\u{fffd} bad")]]);
    }

    #[test]
    fn line_ends_blank_lines_and_a_carriage_return() {
        assert_eq!(parse(b"a\r\n\n\x1b[0m\nb"), vec![vec![run(0, "a")], vec![], vec![], vec![run(0, "b")]]);
        assert_eq!(parse(b"x\n\x1b[0m"), vec![vec![run(0, "x")]], "a trailing reset is not a line");
        assert!(parse(b"").is_empty());
    }
}
