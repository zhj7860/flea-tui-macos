// The mount a name sits on decides its hop, driven against real files in a sandbox.
use crate::backend::collide::*;
use crate::backend::testdir::TestDir;

#[test]
fn a_name_that_is_itself_a_remote_mountpoint_takes_the_guarded_hop_under_a_local_destination() {
    use crate::backend::iomount;
    let d = TestDir::new("identity-in-mountpoint");
    let dest = d.dir("dest");
    let (nas, plain) = (d.dir("dest/nas"), d.dir("dest/plain"));
    let body = format!("1 0 8:1 / / rw - ext4 /dev/a rw\n30 1 0:45 / {} rw - nfs n:/s rw\n", nas.display());
    let table = Table::of(body.clone(), &dest);
    for dst in [&nas, &plain] {
        assert_eq!(table.remote(dst), iomount::is_remote(dst, &body), "{} is judged by its own mount", dst.display());
    }
    assert!(table.remote(&nas) && !table.remote(&plain));
    iomount::test_reset();
    assert!(identity_in(&plain, &table).is_ok());
    assert_eq!(iomount::test_calls(), 0, "a plain child of a local folder is looked at inline");
    assert!(identity_in(&nas, &table).is_ok());
    assert_eq!(iomount::test_calls(), 1, "a remote mountpoint under it goes through iomount::call");
    let _stuck = iomount::test_hold_stuck(nas.clone());
    assert!(identity_in(&nas, &table).is_err_and(|e| e.msg.ends_with("is not responding.")), "its deadline answers for it");
    assert!(identity_in(&plain, &table).is_ok(), "the neighbour on the local mount still answers");
    let remote_dest = Table::of(format!("{body}31 1 0:46 / {} rw - nfs n:/t rw\n", dest.display()), &dest);
    assert!(remote_dest.remote(&plain), "every name in a remote folder keeps its guarded hop");
}
