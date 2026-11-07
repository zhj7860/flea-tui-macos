// Everything's search syntax, restricted to what a name index can answer: a space is AND, `|` is OR,
// `!` negates, `< >` group, `"..."` is literal, and `*` / `?` are wildcards on a whole name. `case:`,
// `nocase:`, `path:`, `nopath:`, `wholefilename:`, `exact:`, `ext:`, `startwith:` and `endwith:` are
// honoured; the metadata functions (`size:`, `dm:`, ...) and `regex:` answer one sentence rather than
// a silent empty list. Matching is ASCII case-insensitive unless `case:` is on, like the name sort.

#[derive(Debug)]
pub struct Query {
    root: Node,
    case: bool,
    // `folder:` asks for folders, and a This Mac answer is a file list, so it matches nothing.
    folders_only: bool,
}

#[derive(Debug)]
enum Node {
    Term(Term),
    Not(Box<Node>),
    And(Vec<Node>),
    Or(Vec<Node>),
    Always,
    // One sentence for a function this index cannot honour; parse() refuses the whole query.
    Error(String),
}

#[derive(Debug)]
struct Term {
    text: String,
    mode: Mode,
    wildcard: bool,
}

#[derive(Debug)]
enum Mode {
    Name,
    Path,
    WholeName,
    StartsWith,
    EndsWith,
    Ext(Vec<String>),
}

impl Query {
    // True when this file is an answer; `name` is its own name, `path` the whole absolute path.
    pub fn matches(&self, name: &str, path: &str) -> bool {
        !self.folders_only && self.root.matches(name, path, self.case)
    }
}

impl Node {
    fn matches(&self, name: &str, path: &str, case: bool) -> bool {
        match self {
            Node::Always => true,
            Node::Term(term) => term.matches(name, path, case),
            Node::Not(inner) => !inner.matches(name, path, case),
            Node::And(parts) => parts.iter().all(|part| part.matches(name, path, case)),
            Node::Or(parts) => parts.iter().any(|part| part.matches(name, path, case)),
            Node::Error(_) => false,
        }
    }
}

impl Term {
    fn matches(&self, name: &str, path: &str, case: bool) -> bool {
        match &self.mode {
            Mode::Name => contains(name, &self.text, self.wildcard, case),
            Mode::Path => contains(path, &self.text, self.wildcard, case),
            Mode::WholeName => {
                if self.wildcard { glob(name, &self.text, case) } else { equals(name, &self.text, case) }
            }
            Mode::StartsWith => starts(name, &self.text, case),
            Mode::EndsWith => ends(name, &self.text, case),
            Mode::Ext(list) => extension(name).is_some_and(|ext| list.iter().any(|want| equals(ext, want, case))),
        }
    }
}

fn extension(name: &str) -> Option<&str> {
    name.rsplit_once('.').map(|(_, ext)| ext).filter(|ext| !ext.is_empty())
}

fn fold(byte: u8, case: bool) -> u8 {
    if case { byte } else { byte.to_ascii_lowercase() }
}

fn equals(hay: &str, needle: &str, case: bool) -> bool {
    hay.len() == needle.len() && hay.bytes().zip(needle.bytes()).all(|(a, b)| fold(a, case) == fold(b, case))
}

fn starts(hay: &str, needle: &str, case: bool) -> bool {
    hay.as_bytes().len() >= needle.len()
        && hay.as_bytes()[..needle.len()].iter().zip(needle.bytes()).all(|(a, b)| fold(*a, case) == fold(b, case))
}

fn ends(hay: &str, needle: &str, case: bool) -> bool {
    let (h, n) = (hay.as_bytes(), needle.as_bytes());
    h.len() >= n.len() && h[h.len() - n.len()..].iter().zip(n).all(|(a, b)| fold(*a, case) == fold(*b, case))
}

// A term is a whole-name wildcard pattern when it holds an unquoted * or ?; otherwise it is a
// substring. A wildcard pattern is anchored to the name, as Everything's is.
fn contains(hay: &str, needle: &str, wildcard: bool, case: bool) -> bool {
    if wildcard {
        return glob(hay, needle, case);
    }
    if needle.is_empty() {
        return true;
    }
    let (h, n) = (hay.as_bytes(), needle.as_bytes());
    if n.len() > h.len() {
        return false;
    }
    (0..=h.len() - n.len()).any(|at| h[at..at + n.len()].iter().zip(n).all(|(a, b)| fold(*a, case) == fold(*b, case)))
}

// `*` takes any run and `?` one byte, with the whole text anchored; the classic backtracking scan.
fn glob(text: &str, pattern: &str, case: bool) -> bool {
    let (t, p) = (text.as_bytes(), pattern.as_bytes());
    let (mut ti, mut pi, mut star, mut mark) = (0, 0, None, 0);
    while ti < t.len() {
        if pi < p.len() && (p[pi] == b'?' || fold(p[pi], case) == fold(t[ti], case)) {
            ti += 1;
            pi += 1;
        } else if pi < p.len() && p[pi] == b'*' {
            star = Some(pi);
            mark = ti;
            pi += 1;
        } else if let Some(at) = star {
            pi = at + 1;
            mark += 1;
            ti = mark;
        } else {
            return false;
        }
    }
    while pi < p.len() && p[pi] == b'*' {
        pi += 1;
    }
    pi == p.len()
}

#[derive(Debug, Clone)]
enum Tok {
    Word { text: String, quoted: bool, wildcard: bool },
    Or,
    Open,
    Close,
    Not,
}

const FLAGS: [&str; 8] = ["case", "nocase", "path", "nopath", "wholefilename", "exact", "file", "folder"];
const FUNCTIONS: [&str; 3] = ["ext", "startwith", "endwith"];

// The functions Everything documents that this index cannot answer: the value needs metadata the
// snapshot never stores, or a matcher this crate does not carry.
const METADATA: [&str; 26] = [
    "size", "dm", "dc", "da", "rc", "attrib", "type", "content", "dupe", "empty", "len", "sort",
    "asc", "desc", "parent", "infolder", "child", "childfile", "childfolders", "root", "filelist",
    "container", "sibling", "shell", "iso", "utf8",
];

fn lex(text: &str) -> Vec<Tok> {
    let mut toks = Vec::new();
    let mut word = String::new();
    let mut started = false;
    let mut quoted = true;
    let mut wildcard = false;
    let mut chars = text.chars().peekable();
    let flush = |word: &mut String, started: &mut bool, quoted: &mut bool, wildcard: &mut bool, toks: &mut Vec<Tok>| {
        if *started {
            toks.push(Tok::Word { text: std::mem::take(word), quoted: *quoted, wildcard: *wildcard });
        }
        *started = false;
        *quoted = true;
        *wildcard = false;
    };
    while let Some(c) = chars.next() {
        match c {
            '"' => {
                started = true;
                for quoted_char in chars.by_ref() {
                    if quoted_char == '"' {
                        break;
                    }
                    word.push(quoted_char);
                }
            }
            c if c.is_whitespace() => flush(&mut word, &mut started, &mut quoted, &mut wildcard, &mut toks),
            '|' => {
                flush(&mut word, &mut started, &mut quoted, &mut wildcard, &mut toks);
                toks.push(Tok::Or);
            }
            '<' => {
                flush(&mut word, &mut started, &mut quoted, &mut wildcard, &mut toks);
                toks.push(Tok::Open);
            }
            '>' => {
                flush(&mut word, &mut started, &mut quoted, &mut wildcard, &mut toks);
                toks.push(Tok::Close);
            }
            '!' if !started => toks.push(Tok::Not),
            '*' | '?' => {
                started = true;
                quoted = false;
                wildcard = true;
                word.push(c);
            }
            _ => {
                started = true;
                quoted = false;
                word.push(c);
            }
        }
    }
    flush(&mut word, &mut started, &mut quoted, &mut wildcard, &mut toks);
    toks
}

// The query as typed: Ok answers matches; Err is one sentence naming what cannot be honoured.
pub fn parse(text: &str) -> Result<Query, String> {
    let mut toks = lex(text);
    let (mut case, mut path, mut whole, mut folders_only) = (false, false, false, false);
    // Everything's flags are global, so they are read off first and apply to every term.
    for tok in &mut toks {
        let Tok::Word { text, quoted, wildcard } = tok else { continue };
        if *quoted {
            continue;
        }
        let Some((name, value)) = text.split_once(':') else { continue };
        let name = name.to_ascii_lowercase();
        if !FLAGS.contains(&name.as_str()) {
            continue;
        }
        match name.as_str() {
            "case" => case = true,
            "nocase" => case = false,
            "path" => path = true,
            "nopath" => path = false,
            "wholefilename" | "exact" => whole = true,
            "file" => folders_only = false,
            "folder" => folders_only = true,
            _ => {}
        }
        // `case:foo` is the flag and the term, which is what a person typing it means; the value
        // stays literal (no function parsing) but keeps its wildcards.
        let replacement = value.to_string();
        let wild = replacement.contains('*') || replacement.contains('?');
        *text = replacement;
        *quoted = true;
        *wildcard = wild;
    }
    let mut parser = Parser { toks, at: 0, path, whole };
    let root = parser.or();
    if let Some(message) = root.error() {
        return Err(message.to_string());
    }
    Ok(Query { root, case, folders_only })
}

struct Parser {
    toks: Vec<Tok>,
    at: usize,
    path: bool,
    whole: bool,
}

impl Parser {
    fn or(&mut self) -> Node {
        let mut parts = vec![self.and()];
        while matches!(self.toks.get(self.at), Some(Tok::Or)) {
            self.at += 1;
            parts.push(self.and());
        }
        if parts.len() == 1 {
            parts.pop().unwrap_or(Node::Always)
        } else {
            Node::Or(parts)
        }
    }

    fn and(&mut self) -> Node {
        let mut parts = Vec::new();
        while self.at < self.toks.len() && !matches!(self.toks[self.at], Tok::Or | Tok::Close) {
            parts.push(self.factor());
        }
        match parts.len() {
            0 => Node::Always,
            1 => parts.pop().unwrap_or(Node::Always),
            _ => Node::And(parts),
        }
    }

    fn factor(&mut self) -> Node {
        if matches!(self.toks.get(self.at), Some(Tok::Not)) {
            self.at += 1;
            return Node::Not(Box::new(self.factor()));
        }
        let Some(tok) = self.toks.get(self.at).cloned() else { return Node::Always };
        self.at += 1;
        match tok {
            Tok::Open => {
                let inner = self.or();
                if matches!(self.toks.get(self.at), Some(Tok::Close)) {
                    self.at += 1;
                }
                inner
            }
            Tok::Word { text, quoted, wildcard } => self.term(text, quoted, wildcard),
            Tok::Close | Tok::Or | Tok::Not => Node::Always,
        }
    }

    fn term(&mut self, text: String, quoted: bool, wildcard: bool) -> Node {
        if text.is_empty() {
            return Node::Always;
        }
        if !quoted {
            if let Some((name, value)) = text.split_once(':') {
                let name = name.to_ascii_lowercase();
                if FUNCTIONS.contains(&name.as_str()) {
                    if value.is_empty() {
                        return Node::Always;
                    }
                    let mode = match name.as_str() {
                        "ext" => Mode::Ext(value.split([';', ',']).filter(|ext| !ext.is_empty()).map(str::to_string).collect()),
                        "startwith" => Mode::StartsWith,
                        _ => Mode::EndsWith,
                    };
                    return Node::Term(Term { text: value.to_string(), mode, wildcard: false });
                }
                if METADATA.contains(&name.as_str()) {
                    return Node::Error(format!("{name}: needs file metadata, and this index holds names only"));
                }
                if name == "regex" {
                    return Node::Error("regular expressions are not supported; use * and ? wildcards".into());
                }
                if name.chars().all(|c| c.is_ascii_alphanumeric() || c == '_') {
                    return Node::Error(format!("unknown function `{name}:`; quote the term to search it literally"));
                }
            }
        }
        let mode = if self.whole {
            Mode::WholeName
        } else if self.path || text.contains('/') {
            Mode::Path
        } else {
            Mode::Name
        };
        Node::Term(Term { text, mode, wildcard })
    }
}

// The parser's failures are nodes so one pass can report them; parse() turns the first into Err.
impl Node {
    fn error(&self) -> Option<&str> {
        match self {
            Node::Error(message) => Some(message),
            Node::Not(inner) => inner.error(),
            Node::And(parts) | Node::Or(parts) => parts.iter().find_map(Node::error),
            Node::Term(_) | Node::Always => None,
        }
    }
}

#[cfg(test)]
#[path = "searchsyntax_tests.rs"]
mod tests;
