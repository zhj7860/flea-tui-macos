// Losing the TUI's one-arena call warns nowhere, so its place before the first thread is pinned here.
#[test]
fn the_tui_keeps_one_malloc_arena_from_before_its_first_thread() {
    let source: String = include_str!("mod.rs").lines().filter(|line| !line.trim_start().starts_with("//")).collect::<Vec<_>>().join("\n");
    let arena = source.find("crate::heap::one_arena();").expect("tui::run keeps one arena");
    let wire = source.find("wire::Wire::start(").expect("tui::run starts the backend wire");
    let gvfs = source.find("warm::start(").expect("tui::run starts the gvfs head start");
    assert!(arena < wire, "the arena is fixed before the wire's reader thread starts");
    assert!(arena < gvfs, "the arena is fixed before the gvfs head start can spawn its helper");
}
