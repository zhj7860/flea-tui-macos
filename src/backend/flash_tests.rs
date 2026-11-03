// The flasher's wire lines in their exact shapes.
use super::*;

fn drive(dev: &str, refused: &str) -> Drive {
    Drive { dev: dev.to_string(), seq: 2, serial: "9".to_string(), label: "128GB".to_string(), model: "General USB Flash Disk".to_string(), bytes: 124_623_257_600, volumes: vec!["128GB".to_string()], refused: refused.to_string() }
}

// A14: every listed drive carries its refusal field, the check protocol.sh cannot make on a host with no removable drive.
#[test]
fn every_listed_drive_carries_its_refusal_field() {
    let line = flashtargets_line(&[drive("sda", ""), drive("sdb", REFUSED_SMALL)]);
    assert_eq!(line.matches("\"dev\":\"").count(), 2);
    assert_eq!(line.matches("\"refused\":\"").count(), 2, "one refusal field per drive: {line}");
    assert!(line.contains("\"refused\":\"small\""));
    assert!(line.starts_with("{\"t\":\"flashtargets\",\"drives\":["));
}

#[test]
fn an_empty_drive_list_is_still_one_line() {
    assert_eq!(flashtargets_line(&[]), "{\"t\":\"flashtargets\",\"drives\":[]}");
}

#[test]
fn the_ending_line_names_phase_error_and_blank() {
    assert_eq!(flashdone_line(7, false, "verify", 4194304, "verify", true), "{\"t\":\"flashdone\",\"id\":7,\"ok\":false,\"phase\":\"verify\",\"at\":4194304,\"err\":\"verify\",\"blank\":true}");
}
