// The words of the status lines and faults the model raises: taildrop outcomes, menu faults, stale confirmations and a refused bulk rename.
use super::*;
use crate::tui::model::Model;
use std::path::PathBuf;

// Each line below is a status line or a fault the footer shows, so none ends in a period.
#[test]
fn taildrop_outcomes_are_status_lines_without_a_final_period() {
    let (mut wire, reader) = echo_wire();
    let peer = crate::tui::taildrop::Peer { id: "node".into(), label: "peer".into(), address: "peer.invalid".into() };
    let mut model = Model::new(PathBuf::from("/"), &Json::Null);
    model.taildrop_target = Some(peer.clone());
    model.menu_action = "taildropRefresh".into();
    model.advance_taildrop(&mut wire).unwrap();
    assert_eq!(model.error, "Taildrop device is unreachable");
    let mut model = Model::new(PathBuf::from("/"), &Json::Null);
    model.taildrop_target = Some(peer);
    model.menu_action = "taildrop".into();
    model.menu_count = 1;
    model.receive(crate::jsondoc::parse(r#"{"t":"menuaction","op":"validate","action":"taildrop","id":0,"ok":true,"paths":[]}"#).unwrap(), &mut wire).unwrap();
    assert_eq!(model.error, "Taildrop: selection is incomplete");
    finish(wire, reader);
}
// Plain words for the faults a person can meet: an open that lost its path, a delete with no token, a stale confirmation, a refused rename.
#[test]
fn menu_faults_and_stale_confirmations_read_as_plain_words() {
    let (mut wire, reader) = echo_wire();
    let mut model = Model::new(PathBuf::from("/"), &Json::Null);
    model.menu_action = "open".into();
    model.menu_path = PathBuf::from("/a");
    model.receive(crate::jsondoc::parse(r#"{"t":"menuaction","op":"validate","action":"open","id":0,"ok":true,"paths":["/b"]}"#).unwrap(), &mut wire).unwrap();
    assert_eq!(model.error, "Could not open selected file");
    let mut model = Model::new(PathBuf::from("/"), &Json::Null);
    model.menu_action = "deletePrepare".into();
    let error = model.receive(crate::jsondoc::parse(r#"{"t":"menuaction","op":"prepareDelete","id":0,"ok":true,"token":0}"#).unwrap(), &mut wire).unwrap_err();
    assert_eq!(error.to_string(), "Deletion could not be confirmed; try again");
    let mut model = Model::new(PathBuf::from("/"), &Json::Null);
    model.menu_action = "deleteRunning".into();
    model.receive(crate::jsondoc::parse(r#"{"t":"menuaction","op":"delete","id":0,"ok":true,"stale":true}"#).unwrap(), &mut wire).unwrap();
    assert_eq!(model.message, "Selection changed; confirm again");
    let mut model = Model::new(PathBuf::from("/"), &Json::Null);
    model.bulk = Some(crate::tui::batch::Batch::new(Vec::new()).unwrap());
    model.menu_action = "bulkRename".into();
    model.receive(crate::jsondoc::parse(r#"{"t":"renamed","ok":false}"#).unwrap(), &mut wire).unwrap();
    assert_eq!(model.error, "Bulk rename stopped: a rename could not finish");
    finish(wire, reader);
}
