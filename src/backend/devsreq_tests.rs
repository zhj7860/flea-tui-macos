use super::*;
use crate::backend::testdir::TestDir;
use std::os::unix::fs::MetadataExt;
use std::path::Path;
use std::time::Duration;

// The asked paths as the request carries them, answered against an empty mount table.
fn asked(paths: &[&str]) -> String {
    answer(&paths.iter().map(|path| path.to_string()).collect::<Vec<_>>(), "", 0)
}

fn said(pairs: &[(&str, u64)]) -> String {
    let body: Vec<String> = pairs.iter().map(|(path, dev)| format!(r#""{}":{}"#, path, dev)).collect();
    format!(r#"{{"t":"devs","devs":{{{}}}}}"#, body.join(","))
}

#[test]
fn a_symlink_answers_the_device_of_the_directory_it_names() {
    let sandbox = TestDir::new("devslink");
    let link = sandbox.path().join("link");
    // /proc stands in for another filesystem: it is never on the sandbox's device, so the link and its target differ.
    std::os::unix::fs::symlink("/proc", &link).unwrap();
    let own = std::fs::symlink_metadata(&link).unwrap().dev();
    let target = dev_of(Path::new("/proc"));
    assert_ne!(own, target, "the link and the directory it names sit on two devices");
    let (link, dir) = (link.to_str().unwrap(), sandbox.path().to_str().unwrap());
    assert_eq!(asked(&[link, dir]), said(&[(link, target), (dir, own)]), "the link answers its target's device, the sandbox its own");
}

#[test]
fn a_path_that_cannot_be_read_answers_zero_and_the_rest_still_answer() {
    let sandbox = TestDir::new("devsmissing");
    let (here, gone) = (sandbox.path().to_str().unwrap(), sandbox.path().join("gone/deeper"));
    let real = std::fs::metadata(sandbox.path()).unwrap().dev();
    let gone = gone.to_str().unwrap();
    // "." exists relative to this process, so only refusing a relative path answers 0 for it.
    assert_eq!(asked(&[gone, "", "relative/dir", ".", here]), said(&[(gone, 0), ("", 0), ("relative/dir", 0), (".", 0), (here, real)]),
        "a missing, empty or relative path is 0, and one failure never voids the others");
    assert_eq!(asked(&[]), said(&[]), "no path asks nothing");
}

#[test]
fn each_path_answers_once_in_the_order_asked() {
    let sandbox = TestDir::new("devsorder");
    let (first, second) = (sandbox.path().to_str().unwrap(), "/proc");
    let (a, b) = (std::fs::metadata(first).unwrap().dev(), dev_of(Path::new(second)));
    assert_eq!(asked(&[second, first, second]), said(&[(second, b), (first, a)]));
}

#[test]
fn a_mount_marked_stuck_answers_zero_at_once_and_a_live_one_answers_its_device() {
    let sandbox = TestDir::new("devsstuck");
    let (share, live) = (sandbox.path().join("share"), sandbox.path().join("live"));
    std::fs::create_dir(&share).unwrap();
    std::fs::create_dir(&live).unwrap();
    let body = format!("1 0 0:30 / / rw - ext4 /dev/a rw\n30 1 0:9 / {} rw - cifs //nas/m rw\n31 1 0:10 / {} rw - nfs n:/s rw\n",
        share.display(), live.display());
    // The share exists, so only the stuck mark answers it 0.
    let (stuck, ok) = (share.to_string_lossy().to_string(), live.to_string_lossy().to_string());
    let held = iomount::test_hold_stuck(share.clone());
    let line = answer(&[stuck.clone(), ok.clone()], &body, 0);
    drop(held);
    assert_eq!(line, said(&[(&stuck, 0), (&ok, std::fs::metadata(&live).unwrap().dev())]),
        "the mount that stopped answering is 0 with no stat, and a network mount that answers is read like any other");
}

#[test]
fn the_request_answers_on_its_own_thread_through_the_ops_channel() {
    let sandbox = TestDir::new("devsthread");
    let (tx, rx) = std::sync::mpsc::channel();
    let path = sandbox.path().to_str().unwrap().to_string();
    request(vec![path.clone()], 0, tx);
    match rx.recv_timeout(Duration::from_secs(5)) {
        Ok(OpMsg::Meta { line }) => assert_eq!(line, said(&[(&path, std::fs::metadata(&path).unwrap().dev())])),
        _ => panic!("the answer rides the ops channel as a finished line"),
    }
}

#[test]
fn a_tagged_hover_answer_keeps_its_request_identity_off_the_loop() {
    let sandbox = TestDir::new("devshover");
    let (tx, rx) = std::sync::mpsc::channel();
    let path = sandbox.path().to_str().unwrap().to_string();
    request(vec![path.clone()], 19, tx);
    match rx.recv_timeout(Duration::from_secs(5)) {
        Ok(OpMsg::Meta { line }) => {
            let expected = said(&[(&path, std::fs::metadata(&path).unwrap().dev())]);
            assert_eq!(line, format!("{}, \"id\":19}}", &expected[..expected.len() - 1]));
        }
        _ => panic!("the hover answer did not reach the ops channel"),
    }
}
