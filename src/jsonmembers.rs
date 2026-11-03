// One member of a JSON object read the way the loader's cJSON reads it: any case, every repeat seen.
use crate::jsondoc;

// Sample input: only("{\"ICD\":{\"library_path\":\"libGLX_nvidia.so.0\"}}", "icd") is Some("{\"library_path\":...}").
// Raw text of the one member matching key, or None; cJSON hands names on as C strings, so each ends at its first NUL.
pub fn only<'a>(text: &'a str, key: &str) -> Option<&'a str> {
    let mut found = members(text)?.into_iter().filter(|(name, _)| name.split('\0').next().is_some_and(|name| name.eq_ignore_ascii_case(key)));
    let (_, value) = found.next()?;
    found.next().is_none().then_some(value)
}

// Sample input: {"a":[1,2],"b":null} answers [("a","[1,2]"),("b","null")], in order and with repeats.
fn members(text: &str) -> Option<Vec<(String, &str)>> {
    let bytes = text.as_bytes();
    let mut at = skip_space(bytes, 0);
    if bytes.get(at) != Some(&b'{') {
        return None;
    }
    at += 1;
    let mut found = Vec::new();
    loop {
        at = skip_space(bytes, at);
        if bytes.get(at) == Some(&b'}') {
            return Some(found);
        }
        let name_end = value_end(bytes, at)?;
        let name = jsondoc::parse(&text[at..name_end]).ok()?.as_str()?.to_owned();
        at = skip_space(bytes, name_end);
        if bytes.get(at) != Some(&b':') {
            return None;
        }
        at = skip_space(bytes, at + 1);
        let end = value_end(bytes, at)?;
        found.push((name, text[at..end].trim_end()));
        at = skip_space(bytes, end);
        match bytes.get(at) {
            Some(b',') => at += 1,
            Some(b'}') => return Some(found),
            _ => return None,
        }
    }
}

// Sample input: `"[1,2]", "n"` read at 0 ends at 7, the comma after the closing quote.
fn value_end(bytes: &[u8], mut at: usize) -> Option<usize> {
    let mut depth = 0usize;
    let mut in_string = false;
    while at < bytes.len() {
        let byte = bytes[at];
        if in_string {
            if byte == b'\\' {
                at += 1;
            } else if byte == b'"' {
                in_string = false;
                if depth == 0 {
                    return Some(at + 1);
                }
            }
        } else {
            match byte {
                b'"' => in_string = true,
                b'{' | b'[' => depth += 1,
                b'}' | b']' if depth == 0 => return Some(at),
                b'}' | b']' => {
                    depth -= 1;
                    if depth == 0 {
                        return Some(at + 1);
                    }
                }
                b',' if depth == 0 => return Some(at),
                _ => {}
            }
        }
        at += 1;
    }
    None
}

fn skip_space(bytes: &[u8], mut at: usize) -> usize {
    while at < bytes.len() && matches!(bytes[at], b' ' | b'\t' | b'\n' | b'\r') {
        at += 1;
    }
    at
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn the_one_member_is_found_whatever_its_case_and_whatever_sits_beside_it() {
        let text = "{\"comment\":\"library_path {\\\"x\\\":[1,2]}\",\"n\":-1.5e3,\"Icd\":{\"a\":[{\"b\":true}]},\"z\":null}";
        assert_eq!(only(text, "ICD"), Some("{\"a\":[{\"b\":true}]}"));
        assert_eq!(only(text, "n"), Some("-1.5e3"));
        assert_eq!(only(text, "comment"), Some("\"library_path {\\\"x\\\":[1,2]}\""));
        assert_eq!(only(text, "missing"), None);
    }

    // cJSON takes the first of a repeat and jsondoc the last, so a repeat in any spelling answers nothing.
    #[test]
    fn a_repeated_name_in_any_spelling_is_no_answer() {
        for text in [
            "{\"ICD\":{},\"ICD\":{\"library_path\":\"x\"}}",
            "{\"icd\":{},\"ICD\":{}}",
            "{\"ICD\\u0000suffix\":{},\"ICD\":{}}",
            "{\"ICD\":{},\"I\\u0043D\":{}}",
        ] {
            assert_eq!(only(text, "ICD"), None, "{text}");
        }
    }

    #[test]
    fn anything_but_an_object_has_no_members() {
        assert_eq!(only("[\"ICD\"]", "ICD"), None);
        assert_eq!(only("\"ICD\"", "ICD"), None);
        assert_eq!(only("{}", "ICD"), None);
    }
}
