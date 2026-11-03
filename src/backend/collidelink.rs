// A link that resolves into the batch, walked the way the kernel walks it.
use std::path::{Component, Path, PathBuf};

// Symlinks Linux follows in one lookup before it answers ELOOP, so a walk that follows more is broken wherever it was heading.
const MAX_HOPS: usize = 40;

// A link lands under its own text in dest, so it resolves into there either now or once it sits there itself.
pub(crate) fn links_into(src: &Path, there: &Path) -> bool {
    let Ok(text) = std::fs::read_link(src) else { return false };
    let now = src.canonicalize().is_ok_and(|target| target.starts_with(there));
    now || there.parent().is_some_and(|dest| matches!(walk(dest.to_path_buf(), &text, there, &mut 0), Walk::Loops))
}

// Where a lookup ends: a folder or file it reached, a name that is not there, back at there, which holds the link itself, or past MAX_HOPS short of there.
enum Walk {
    Ends(PathBuf),
    Dangles,
    Loops,
    // The kernel answers ELOOP before the lookup reaches there, so the link is broken like a dangling one and not a link to itself.
    Overflows,
}

// Resolves text from at as the kernel would once there holds a link with this same text, so reaching there starts the lookup over.
fn walk(mut at: PathBuf, text: &Path, there: &Path, hops: &mut usize) -> Walk {
    for part in text.components() {
        match part {
            Component::RootDir => at = PathBuf::from(Component::RootDir.as_os_str()),
            Component::Prefix(_) | Component::CurDir => {}
            Component::ParentDir => { at.pop(); }
            Component::Normal(name) => {
                let next = at.join(name);
                if next == there {
                    return Walk::Loops;
                }
                let Ok(meta) = next.symlink_metadata() else { return Walk::Dangles };
                if !meta.file_type().is_symlink() {
                    at = next;
                    continue;
                }
                *hops += 1;
                let Ok(target) = std::fs::read_link(&next) else { return Walk::Dangles };
                if *hops > MAX_HOPS {
                    return Walk::Overflows;
                }
                at = match walk(at, &target, there, hops) {
                    Walk::Ends(end) => end,
                    stopped => return stopped,
                };
            }
        }
    }
    Walk::Ends(at)
}
