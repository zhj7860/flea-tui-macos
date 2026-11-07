use crate::gui;
use crate::runfile;
use crate::tearoff;
use crate::thp;
use crate::vulkan;
use std::os::unix::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

// The exit statuses ui/Opener.qml reads. 0 is a successful handoff and needs no name.
pub const FAILED: i32 = 2;
pub const IS_DIRECTORY: i32 = 3;

// A macOS application bundle is a directory to the filesystem and one program to the person who
// searched for it: the desktop launches it, and no caller is asked to walk into its Contents.
pub fn is_app_bundle(path: &Path) -> bool {
    cfg!(target_os = "macos") && path.extension().is_some_and(|ext| ext.eq_ignore_ascii_case("app"))
}

// The one shape whose 3 means navigate: a folder that is not an application bundle.
fn is_directory_answer(target: &Path) -> bool {
    target.is_dir() && !is_app_bundle(target)
}

// Canonical, so a file named --output=/etc/x cannot be read as a flag by the child.
fn resolved(path: &str) -> Option<PathBuf> {
    std::fs::canonicalize(path).ok()
}

// The environment every program Flea starts carries: huge pages back on, Qt's own pin, driver exclusion and theme dropped, the tear-off hand-off kept to its window. runfile.rs reuses this.
pub fn prepare(child: &mut Command) {
    // The setting is inherited across exec, so this is the last point that can hand it back.
    thp::enable();
    // The display-GPU pin and the driver exclusion are Qt's alone, and only this launcher's own are dropped.
    vulkan::drop_display_pin(child);
    crate::icdexclude::drop_exclusion(child);
    // The platform theme Flea traded for its own startup is Qt's alone too, and is handed back here.
    gui::restore_platform_theme(child);
    // The tear-off hand-off belongs to the one window a tear-off starts, never to a program it opens.
    tearoff::drop_env(child);
}

// In-process callers (the TUI, the shelf) stay on 0/2/3: an executable is refused with its sentence, and only the main.rs --open path asks the card, through open_ask.
pub fn open(path: &str) -> i32 {
    open_inner(path, false)
}

// The window's own entrance: a program asks once on the run card instead of reaching a handler.
pub fn open_ask(path: &str) -> i32 {
    open_inner(path, true)
}

// gio open is the OEM route: it asks the desktop database, so Terminal=true is honoured; see AGENTS.md "Opening a file".
fn open_inner(path: &str, ask: bool) -> i32 {
    let target = match resolved(path) {
        Some(p) => p,
        // The reason is elided, never shown raw, and the path is the user's own input.
        None => {
            eprintln!("flea: that file could not be opened, check that it still exists");
            return FAILED;
        }
    };
    // A bundle is handed to LaunchServices instead: the window's 3 means navigate, and nobody
    // navigates into an application.
    if is_directory_answer(&target) {
        return IS_DIRECTORY;
    }
    // A FIFO, socket or device is never a program and never blocks here: it skips the snapshot and the run decision and opens the way it always did.
    if !target.is_file() {
        return open_normally(&target, ask);
    }
    // One open for the kind and the identity together, so a swap between them cannot pair two files.
    let opened = match crate::runid::snapshot(&target) {
        Some(o) => o,
        None => {
            eprintln!("flea: that file could not be opened, check that it still exists");
            return FAILED;
        }
    };
    // A program asks once on the run card instead of reaching a handler, and a file no application claims asks Open with.
    let body = std::fs::read("/proc/self/mountinfo").unwrap_or_default();
    let mounts = String::from_utf8_lossy(&body).into_owned();
    match runfile::decide_opened(&opened, &target, &mounts) {
        runfile::Decision::Ask(kind) => {
            if !ask {
                eprintln!("flea: that file is a program, so it was not opened");
                return FAILED;
            }
            let handler = if matches!(kind, runfile::Kind::AppImage) { crate::desktopid::handler(&target) } else { None };
            println!("{}", runfile::ask_line(kind, handler.as_ref(), &opened.id, &target));
            return runfile::ASK_RUN;
        }
        // A script missing its bit opens with its handler the way it always did; the menu's Make executable is the one route to the bit.
        runfile::Decision::MakeExecutable(runfile::Kind::Script) => {}
        // A binary missing its bit is refused for every caller, since an AppImage launcher would run it.
        runfile::Decision::MakeExecutable(_) => {
            eprintln!("flea: that file is a program, so it was not opened");
            return FAILED;
        }
        runfile::Decision::RefuseNoExec => {
            eprintln!("flea: that program is on a volume that does not allow running files");
            return FAILED;
        }
        runfile::Decision::OpenNormally => {}
    }
    open_normally(&target, ask)
}

// The program a file is handed to: gio's desktop database on Linux, LaunchServices' `open` on Darwin.
fn open_program() -> &'static str {
    #[cfg(target_os = "macos")]
    {
        "/usr/bin/open"
    }
    #[cfg(not(target_os = "macos"))]
    {
        "gio"
    }
}

// Past every run decision: handed to gio open and waited on, the way the opener always did.
fn open_normally(target: &Path, ask: bool) -> i32 {
    // corner: waited for, not detached, and on an archive that wait is a cold handler start; see AGENTS.md "Opening a file".
    // Darwin asks LaunchServices with `open`, which is `gio open`'s counterpart and needs no subcommand.
    let mut launcher = Command::new(open_program());
    prepare(&mut launcher);
    #[cfg(not(target_os = "macos"))]
    launcher.arg("open");
    let finished = launcher
        .arg(target)
        // The handler outlives us, so an inherited pipe would kill it on its first write; see AGENTS.md "Opening a file".
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        // Its own process group, so nothing that later kills Flea's group reaches the opened program.
        .process_group(0)
        .status();
    match finished {
        Ok(status) if status.success() => 0,
        // A launcher that refused, which a spawn nobody waited on used to report as a clean handoff.
        Ok(_) => {
            // A file no application claims opens the approved Open with dialog instead, on the window's path alone.
            if ask && crate::desktopid::unclaimed(target) {
                println!(r#"{{"ask":"openWith"}}"#);
                return runfile::ASK_OPEN_WITH;
            }
            eprintln!("flea: no application on this system opened that file");
            FAILED
        }
        Err(_) => {
            eprintln!("flea: nothing on this system could be asked to open that file");
            FAILED
        }
    }
}

// Reveals an item where the desktop keeps it: Finder selects it on Darwin, and elsewhere the folder
// it lives in is opened by the desktop's own handler. The menu's Open path is the only caller.
// FLEA_OPEN names the launcher, the tree's test seam, as the macOS app entry honours it.
pub fn reveal(path: &str) -> i32 {
    let target = match resolved(path) {
        Some(p) => p,
        None => {
            eprintln!("flea: that file could not be opened, check that it still exists");
            return FAILED;
        }
    };
    let mut launcher = Command::new(std::env::var("FLEA_OPEN").unwrap_or_else(|_| open_program().into()));
    prepare(&mut launcher);
    #[cfg(target_os = "macos")]
    launcher.arg("-R").arg(&target);
    // gio has no reveal: the folder the item sits in is the closest thing its handler opens.
    #[cfg(not(target_os = "macos"))]
    launcher.arg("open").arg(target.parent().unwrap_or(&target));
    let ended = launcher
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .process_group(0)
        .status();
    match ended {
        Ok(status) if status.success() => 0,
        Ok(_) => {
            eprintln!("flea: no application on this system opened that path");
            FAILED
        }
        Err(_) => {
            eprintln!("flea: nothing on this system could be asked to open that path");
            FAILED
        }
    }
}

// The suite's stubs speak gio, GNU timeout and mkfifo, so those checks are Linux's.
#[cfg(all(test, target_os = "linux"))]
#[path = "open_tests.rs"]
mod tests;

#[cfg(all(test, target_os = "macos"))]
mod darwin_tests {
    use super::*;

    #[test]
    fn a_file_is_handed_to_launch_services() {
        assert_eq!(open_program(), "/usr/bin/open");
        assert!(Path::new(open_program()).is_file(), "every macOS ships this");
    }

    // The menu's Open path asks the launcher to reveal the item: Finder's own `-R` on this platform.
    #[test]
    fn reveal_asks_the_launcher_to_show_the_item() {
        let root = std::env::temp_dir().join(format!("flea-reveal-{}", std::process::id()));
        std::fs::create_dir_all(&root).expect("the fixture is made");
        let stub = root.join("open");
        let log = root.join("argv");
        std::fs::write(&stub, format!("#!/bin/sh\necho \"$@\" > \"{}\"\n", log.display())).expect("the stub is written");
        use std::os::unix::fs::PermissionsExt;
        std::fs::set_permissions(&stub, std::fs::Permissions::from_mode(0o755)).expect("the stub runs");
        let item = root.join("file.txt");
        std::fs::write(&item, b"x").expect("the item is written");
        std::env::set_var("FLEA_OPEN", &stub);
        let status = reveal(&item.to_string_lossy());
        std::env::remove_var("FLEA_OPEN");
        assert_eq!(status, 0);
        let asked = std::fs::read_to_string(&log).expect("the stub recorded its argv");
        let real = std::fs::canonicalize(&item).expect("the item resolves");
        assert_eq!(asked.trim(), format!("-R {}", real.display()));
        std::fs::remove_dir_all(&root).expect("the fixture is removed");
    }

    #[test]
    fn a_directory_is_answered_without_a_launch() {
        let dir = std::env::temp_dir();
        assert_eq!(open(&dir.to_string_lossy()), IS_DIRECTORY);
    }

    // A bundle is a directory to the filesystem and one program to the person who searched for
    // it, so it is the one folder shape that is not the navigate answer and reaches `open`.
    #[test]
    fn an_application_bundle_is_never_the_directory_answer() {
        for (name, bundle) in [("Safari.app", true), ("Safari.APP", true), ("Applications", false), ("notes.app.txt", false), ("app", false)] {
            let path = Path::new("/Applications").join(name);
            assert_eq!(is_app_bundle(&path), bundle, "{name}");
        }
        let root = std::env::temp_dir().join(format!("flea-open-bundle-{}", std::process::id()));
        let bundle = root.join("Fake.app");
        let plain = root.join("Plain");
        std::fs::create_dir_all(&bundle).expect("the bundle dir is made");
        std::fs::create_dir_all(&plain).expect("the plain dir is made");
        assert!(!is_directory_answer(&bundle), "a bundle is launched, never walked into");
        assert!(is_directory_answer(&plain), "every other folder is still the navigate answer");
        std::fs::remove_dir_all(&root).expect("the fixture is removed");
    }
}
