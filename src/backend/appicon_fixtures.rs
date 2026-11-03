use crate::backend::testdir::TestDir;

// Checked through the same required 7z binary, so the real-reader test needs no fixture builder or second hash tool.
pub(super) fn checked(dir: &TestDir, seven: &str, with_icon: bool) -> Vec<u8> {
    let (name, bytes): (&str, &[u8]) = if with_icon {
        ("with-dir-icon.sqfs", include_bytes!("../../tests/fixtures/appimage-icon/with-dir-icon.sqfs"))
    } else {
        ("without-dir-icon.sqfs", include_bytes!("../../tests/fixtures/appimage-icon/without-dir-icon.sqfs"))
    };
    // Sample input: "63842e22e89a6640cd356bb8f1be86cfb29a5bae416089484339326676774a53  with-dir-icon.sqfs"
    let expected = include_str!("../../tests/fixtures/appimage-icon/SHA256SUMS").lines()
        .find_map(|line| line.split_once("  ").filter(|(_, file)| *file == name).map(|(hash, _)| hash))
        .expect("fixture has no SHA-256 pin");
    assert_eq!(expected.len(), 64);
    let path = dir.join(name);
    std::fs::write(&path, bytes).unwrap();
    let hash = std::process::Command::new(seven).args(["h", "-scrcSHA256", "--"]).arg(&path).output().unwrap();
    assert!(hash.status.success(), "7z SHA-256 failed: {}", String::from_utf8_lossy(&hash.stderr));
    assert!(String::from_utf8_lossy(&hash.stdout).split_whitespace().any(|word| word.eq_ignore_ascii_case(expected)),
        "fixture SHA-256 differs from its pin: {}", name);
    bytes.to_vec()
}
