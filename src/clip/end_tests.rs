// Pure argv fixtures and isolated fault doubles pin the production owner-end branches.
use super::owner_args;
use crate::backend::testdir::TestDir;
use std::process::Command;

const FAULT_WATCHDOG_SECONDS: u32 = 15;
const EMFILE: i32 = 24;
const EAGAIN: i32 = 11;
const EIO: i32 = 5;
const TEST_FAILURE_EXIT: i32 = 101;
const COMPILER_FAILURE_TEST: &str = "clip::end::tests::eventfd_failure_reports_once_across_retries";

#[test]
fn a_failed_fault_compiler_leaves_no_scratch_directory() {
    let root = TestDir::new("clip-end-compiler-failure");
    let argv = root.join("rustc-argv");
    let rustc = root.script("rustc-fails", &format!("#!/bin/sh\nprintf '%s\\n' \"$@\" > '{}'\nexit 1\n", argv.display()));
    // Child-only overrides keep parallel tests' compiler and scratch environment unchanged.
    let result = Command::new("timeout").arg(FAULT_WATCHDOG_SECONDS.to_string())
        .arg(std::env::current_exe().unwrap()).arg("--exact").arg(COMPILER_FAILURE_TEST).arg("--nocapture")
        .env("TMPDIR", root.path()).env("RUSTC", &rustc).output().unwrap();
    assert_eq!(result.status.code(), Some(TEST_FAILURE_EXIT), "the failing compiler must fail the child test");
    assert!(String::from_utf8_lossy(&result.stdout).contains(&format!("test {} ... FAILED", COMPILER_FAILURE_TEST)));
    // The compiler was handed an output path in a scratch directory under TMPDIR, so the cleanup below had work to do.
    let args = std::fs::read_to_string(&argv).expect("the failing compiler ran");
    let program = std::path::PathBuf::from(args.lines().skip_while(|arg| *arg != "-o").nth(1).expect("an output path"));
    assert!(program.starts_with(root.path()) && program.parent() != Some(root.path()),
        "scratch outside TMPDIR: {}", program.display());
    let leftovers: Vec<_> = std::fs::read_dir(root.path()).unwrap().map(|entry| entry.unwrap().path())
        .filter(|path| path.is_dir()).collect();
    assert!(leftovers.is_empty(), "failed compiler left scratch directories: {:?}", leftovers);
}

#[test]
fn only_the_production_owner_argument_pair_is_an_owner() {
    let fixtures: &[(&[u8], bool)] = &[
        (b"/usr/bin/flea\0--clip-own", true),
        (b"/usr/bin/flea\0--clip-own\0extra", false),
        (b"/usr/bin/flea\0--backend", false),
        (b"", false),
    ];
    for (command, expected) in fixtures {
        // Sample input: /usr/bin/flea\0--clip-own, after removing procfs's terminal NUL.
        let arguments: Vec<_> = command.split(|byte| *byte == 0).collect();
        assert_eq!(owner_args(&arguments), *expected, "owner argv fixture {:?}", command);
    }
}

fn check_fault(mode: &str, component: &str, error: i32, counts: &str) {
    let dir = TestDir::new("clip-end-faults");
    let root = dir.path().join(mode);
    std::fs::create_dir(&root).unwrap();
    let program = root.join("faults");
    let source = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("src/clip/end_fault_fixture.rs");
    let compiler = std::env::var_os("RUSTC").unwrap_or_else(|| "rustc".into());
    let compiled = Command::new("timeout").arg(FAULT_WATCHDOG_SECONDS.to_string()).arg(compiler)
        .arg("--edition=2021").arg(source).arg("-o").arg(&program).output().unwrap();
    assert!(compiled.status.success(), "{}", String::from_utf8_lossy(&compiled.stderr));
    let result = Command::new("timeout").arg(FAULT_WATCHDOG_SECONDS.to_string()).arg(&program).arg(mode).output().unwrap();
    assert!(result.status.success(), "{}", String::from_utf8_lossy(&result.stderr));
    assert_eq!(String::from_utf8(result.stdout).unwrap(), format!("{}: {}\n", mode, counts));
    assert_eq!(String::from_utf8(result.stderr).unwrap(),
        format!("flea: clipboard owner-end {} failed: {}\n", component, std::io::Error::from_raw_os_error(error)),
        "the failed component must emit one diagnostic with its OS error");
}

#[test]
fn eventfd_failure_reports_once_across_retries() {
    check_fault("eventfd", "eventfd", EMFILE,
        "eventfd_calls=2 spawn_calls=0 poll_calls=0 wake=false worker_started=false");
}

#[test]
fn thread_spawn_failure_reports_once_across_retries() {
    check_fault("spawn", "thread spawn", EAGAIN,
        "eventfd_calls=2 spawn_calls=2 poll_calls=0 wake=false worker_started=false");
}

#[test]
fn terminal_poll_error_reports_once() {
    check_fault("poll", "poll", EIO,
        "eventfd_calls=1 spawn_calls=1 poll_calls=1 wake=true worker_started=true");
}

#[test]
fn interrupted_poll_retries_without_a_diagnostic() {
    check_fault("interrupted", "poll", EIO,
        "eventfd_calls=1 spawn_calls=1 poll_calls=2 wake=true worker_started=true");
}
