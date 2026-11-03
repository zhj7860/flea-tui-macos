// The summary of refused entries reads as one whole sentence for each verb and count.
use std::path::Path;

// Sample output: "a could not be moved: no", or "2 items inside could not be copied; the first is a: no".
#[test]
fn the_summary_is_one_whole_sentence_for_each_verb_and_count() {
    let refuse = |names: &[&str]| {
        super::begin(false);
        for name in names {
            super::note(super::marked(&Path::new("/d").join(name), "no".to_string()));
        }
    };
    refuse(&["a"]);
    assert_eq!(super::summary(Path::new("/d"), true).unwrap().msg, "a could not be moved: no");
    assert_eq!(super::summary(Path::new("/d"), false).unwrap().msg, "a could not be copied: no");
    refuse(&["a", "b"]);
    assert_eq!(super::summary(Path::new("/d"), true).unwrap().msg, "2 items inside could not be moved; the first is a: no");
    assert_eq!(super::summary(Path::new("/d"), false).unwrap().msg, "2 items inside could not be copied; the first is a: no");
    super::begin(false);
}
