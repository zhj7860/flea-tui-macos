// Issue 133, the TUI's half of ui/js/Mounts.js "trashable": what a folder's path says about its Trash.
pub use crate::backend::hometrash::trashable;

// The status line's refusal: what failed, then the key that still removes the rows, when the keymap binds one.
pub fn no_trash(delete_permanently: &str) -> String {
    if delete_permanently.is_empty() {
        "This location has no Trash".into()
    } else {
        format!("This location has no Trash; {} deletes permanently", delete_permanently)
    }
}
