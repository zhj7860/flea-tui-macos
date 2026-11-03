use super::*;

fn replace_record(d: &TestDir, root: &Path) -> PathBuf {
    guard(d, root);
    let path = std::fs::read_dir(root).unwrap().map(|entry| entry.unwrap().path())
        .find(|path| path.extension().is_some_and(|extension| extension == "review")).unwrap();
    d.replace_file(&path, "replacement record");
    path
}

#[test]
fn completed_delete_and_restore_report_a_record_removed_without_confirmed_sync() {
    for op in [Op::Delete, Op::Restore] {
        let d = TestDir::new("refusal-record-unconfirmed");
        let original = d.join("restored");
        let (path, reviewed) = fixture(&d, &original);
        let root = d.dir("recovery");
        let seen = logged().len();
        let refused = reviewed.with_claimed(op, &root, (op == Op::Restore).then_some(original.as_path()), || {}, |quarantine| {
            guard(&d, &fd_path(quarantine, OsStr::new("payload")).canonicalize().unwrap());
            if op == Op::Delete {
                remove_tree(reviewed.tree.as_ref().unwrap(), quarantine, Refusal::new(Outcome::NothingDeleted, "Trash contents changed; no deletion attempted."))?;
            } else {
                guard(&d, &original);
                rename(quarantine, OsStr::new("payload"), &open_dir(original.parent().unwrap())?, original.file_name().unwrap()).unwrap();
            }
            std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o300)).unwrap();
            Ok(())
        });
        std::fs::set_permissions(&root, std::fs::Permissions::from_mode(0o700)).unwrap();
        let refused = refused.unwrap_err();
        assert_eq!(refused.outcome(), &Outcome::RecordUnconfirmed(Some(op)));
        let effect = if op == Op::Delete { "deleted" } else { "restored" };
        assert_eq!(refused.shown(), format!("The item was {effect}, but after removing its recovery record, Flea could not confirm the removal on disk: permission denied."));
        assert_logged(seen, "Could not open Trash folder");
        assert_eq!(std::fs::read_dir(&root).unwrap().count(), 0);
        assert!(!path.exists());
        assert!(!reviewed.info.exists());
        if op == Op::Restore { assert_eq!(std::fs::read_to_string(&original).unwrap(), "payload"); }
    }
}

#[test]
fn metadata_removed_between_review_and_claim_asks_to_confirm_again() {
    for op in [Op::Delete, Op::Restore] {
        let d = TestDir::new("refusal-metadata-gone");
        let original = d.join("restored");
        let (path, reviewed) = fixture(&d, &original);
        let root = d.dir("recovery");
        let seen = logged().len();
        let refused = reviewed.with_claimed(op, &root, (op == Op::Restore).then_some(original.as_path()), || {
            guard(&d, &reviewed.info);
            std::fs::remove_file(&reviewed.info).unwrap();
        }, |_| panic!("missing metadata must not perform the operation")).unwrap_err();
        assert_eq!(refused.outcome(), &Outcome::ConfirmAgain);
        assert_eq!(refused.shown(), "The Trash changed, so nothing was done; confirm again.");
        assert_logged(seen, "Trash changed; no operation attempted. Confirm again.");
        assert_eq!(std::fs::read_to_string(&path).unwrap(), "payload");
        assert!(!reviewed.info.exists());
        assert!(!original.exists());
        let remaining: Vec<_> = std::fs::read_dir(d.join("files")).unwrap().map(|entry| entry.unwrap().path()).collect();
        assert_eq!(remaining, vec![path]);
        assert_eq!(std::fs::read_dir(&root).unwrap().count(), 0);
    }
}

#[test]
fn a_claim_failure_keeps_its_cause_when_record_cleanup_also_fails() {
    for op in [Op::Delete, Op::Restore] {
        for metadata_claim in [false, true] {
            let d = TestDir::new("refusal-claim-cleanup");
            let original = d.join("restored");
            d.dir("files");
            let infos = d.dir("info");
            let path = if metadata_claim { d.file("files/item", "payload") } else { locked(&d, "files/item") };
            d.file("info/item.trashinfo", &format!("[Trash Info]\nPath={}\n", original.display()));
            let reviewed = review(&d, &path);
            let root = d.dir("recovery");
            let seen = logged().len();
            let refused = reviewed.with_claimed(op, &root, (op == Op::Restore).then_some(original.as_path()), || {
                replace_record(&d, &root);
                if metadata_claim { std::fs::set_permissions(&infos, std::fs::Permissions::from_mode(0o500)).unwrap(); }
            }, |_| panic!("a failed claim must not perform the operation"));
            std::fs::set_permissions(&infos, std::fs::Permissions::from_mode(0o700)).unwrap();
            if !metadata_claim { std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap(); }
            let refused = refused.unwrap_err();
            assert_eq!(refused.outcome(), &Outcome::Prepare(op));
            let (step, effect) = if op == Op::Delete { ("deletion", "deleted") } else { ("restore", "restored") };
            assert_eq!(refused.shown(), format!("Could not prepare the {step}, so nothing was {effect}: permission denied."));
            assert_logged(seen, "Recovery record changed; it was preserved.");
            assert!(since(seen).iter().any(|line| line.contains("RecordLeft(None)")));
            let cause = if metadata_claim { "Could not claim Trash metadata: permission denied" } else { "Could not claim Trash item: permission denied" };
            assert_logged(seen, cause);
            let payload = if metadata_claim { path } else { path.join("child.txt") };
            assert_eq!(std::fs::read_to_string(payload).unwrap(), if metadata_claim { "payload" } else { "survive" });
            assert!(reviewed.info.exists());
            assert!(!original.exists());
            let record = std::fs::read_dir(&root).unwrap().next().unwrap().unwrap().path();
            assert_eq!(std::fs::read_to_string(record).unwrap(), "replacement record");
        }
    }
}

#[test]
fn an_ordinary_path_claim_failure_keeps_its_cause_when_record_cleanup_also_fails() {
    let d = TestDir::new("refusal-path-claim-cleanup");
    let path = locked(&d, "selected");
    let (reviewed, _) = PathReview::prepare(path.clone(), &mut Manifest::new(d.path()).unwrap(), d.path(), &Cancellation::default()).unwrap();
    let root = d.dir("recovery");
    let seen = logged().len();
    let refused = reviewed.delete_after(&root, || { replace_record(&d, &root); });
    std::fs::set_permissions(&path, std::fs::Permissions::from_mode(0o755)).unwrap();
    let refused = refused.unwrap_err();
    assert_eq!(refused.shown(), "Could not prepare the deletion, so nothing was deleted: permission denied.");
    assert_logged(seen, "Recovery record changed; it was preserved.");
    assert_logged(seen, "Could not claim item for deletion: permission denied");
    assert_eq!(std::fs::read_to_string(path.join("child.txt")).unwrap(), "survive");
}

#[test]
fn a_metadata_file_that_will_not_go_is_named_after_the_item_was_deleted() {
    let d = TestDir::new("refusal-info-left");
    let (path, reviewed) = fixture(&d, &d.join("restored"));
    let seen = logged().len();
    let refused = reviewed.with_claimed(Op::Delete, d.path(), None, || {}, |quarantine| {
        guard(&d, &fd_path(quarantine, OsStr::new("payload")).canonicalize().unwrap());
        remove_tree(reviewed.tree.as_ref().unwrap(), quarantine,
            Refusal::new(Outcome::NothingDeleted, "Trash contents changed; no deletion attempted."))?;
        std::fs::set_permissions(fd_path(quarantine, OsStr::new(".")), std::fs::Permissions::from_mode(0o500)).unwrap();
        Ok(())
    }).unwrap_err();
    let shown = refused.shown();
    assert!(shown.starts_with("The item was deleted, but a Trash record at "), "{shown}");
    assert!(shown.ends_with(" could not be removed: permission denied."), "{shown}");
    assert_logged(seen, "Trash metadata cleanup after completion");
    assert!(!path.exists());
    assert!(!quarantine_in(&d.join("files")).join("payload").exists());
}

#[test]
fn a_temporary_folder_that_will_not_go_is_named_after_the_step_finished() {
    let d = TestDir::new("refusal-folder-left");
    let original = d.join("restored");
    let (trashed, reviewed) = fixture(&d, &original);
    let seen = logged().len();
    let restored = reviewed.with_claimed(Op::Restore, d.path(), Some(&original), || {}, |quarantine| {
        guard(&d, &original);
        guard(&d, &fd_path(quarantine, OsStr::new("payload")).canonicalize().unwrap());
        let destination = open_dir(original.parent().unwrap())?;
        rename(quarantine, OsStr::new("payload"), &destination, original.file_name().unwrap()).unwrap();
        std::fs::write(fd_path(quarantine, OsStr::new("stray")), "x").unwrap();
        Ok(())
    }).unwrap_err();
    let temporary = quarantine_in(&d.join("files"));
    assert_eq!(restored.shown(), format!("The item was restored, but Flea could not remove its temporary folder at {}: it still holds items.", temporary.display()));
    assert_eq!(std::fs::read_to_string(temporary.join("stray")).unwrap(), "x");
    assert_logged(seen, "no cleanup was recorded");
    assert_eq!(std::fs::read_to_string(&original).unwrap(), "payload");
    assert!(!trashed.exists());
    assert!(!quarantine_in(&d.join("files")).join("payload").exists());
    let path = d.file("selected", "reviewed");
    let (review, _) = PathReview::prepare(path.clone(), &mut Manifest::new(d.path()).unwrap(), d.path(), &Cancellation::default()).unwrap();
    let deleted = review.delete_after(d.path(), || std::fs::write(quarantine_in(d.path()).join("stray"), "x").unwrap()).unwrap_err();
    let temporary = quarantine_in(d.path());
    assert_eq!(deleted.shown(), format!("The item was deleted, but Flea could not remove its temporary folder at {}: it still holds items.", temporary.display()));
    assert_eq!(std::fs::read_to_string(temporary.join("stray")).unwrap(), "x");
    assert!(!path.exists());
}

