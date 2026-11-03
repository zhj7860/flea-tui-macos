// An ENAMETOOLONG names the drive only while the path itself fits the kernel's limit.
use std::path::Path;

const ENAMETOOLONG: i32 = 36;

// Sample input: ENAMETOOLONG on a 300 byte leaf is the drive's, and on a path of PATH_MAX bytes it is the copy's own error.
#[test]
fn enametoolong_names_a_refusal_only_while_the_path_fits_the_kernel() {
    let long = std::io::Error::from_raw_os_error(ENAMETOOLONG);
    let leaf = super::refused(super::Kind::Entry, &long, Path::new(&format!("/media/stick/{}", "n".repeat(300))), None);
    assert_eq!((leaf.where_.as_str(), leaf.msg.as_str()), (super::UNHELD, super::LONG), "a name past the drive's limit is the drive's refusal");
    let deep = format!("/media/stick/{}", "d/".repeat(2100));
    assert!(deep.len() >= super::PATH_MAX);
    assert_eq!(super::refused(super::Kind::Entry, &long, Path::new(&deep), None).where_, "copy", "a path past PATH_MAX is not the drive's");
}
