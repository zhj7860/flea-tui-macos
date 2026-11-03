// The words a refused registry read shows; each pins the sentence a person reads, not the branch that raises it.
use super::*;

// A registry error ends with exactly one period, so a caller that wraps it never adds a second.
#[test]
fn registry_errors_are_sentences_that_end_once() {
    let registry = Registry::default();
    let cancel = Cancellation::default();
    let query = registry.capture(&mut Command::new("/usr/bin/false"), &cancel).unwrap_err();
    let launch = registry.launch_command(&mut Command::new("/usr/bin/false"), &cancel).unwrap_err();
    assert_eq!(launch, "The application could not be started (exit status 1).");
    let missing = registry.launch_command(&mut Command::new("/definitely-missing-gio-test-helper"), &cancel).unwrap_err();
    assert!(missing.starts_with("The application could not be started: ") && !missing.contains("os error"), "{}", missing);
    let stopped = Cancellation::default();
    stopped.next();
    let cancelled = registry.launch_command(&mut Command::new("/usr/bin/true"), &stopped).unwrap_err();
    for error in [query, launch, missing, cancelled] {
        assert!(error.ends_with('.') && !error.ends_with(".."), "{}", error);
    }
}

// A launch is not a list read: the shared start and cancel code names the work the child serves, in both directions.
#[test]
fn a_launch_fault_never_blames_the_application_list_and_a_list_fault_never_blames_a_launch() {
    let registry = Registry::default();
    let live = Cancellation::default();
    let stopped = Cancellation::default();
    stopped.next();
    let missing = "/definitely-missing-gio-test-helper";
    assert_eq!(registry.launch_command(&mut Command::new("/usr/bin/true"), &stopped).unwrap_err(), "Opening the application was cancelled.");
    assert_eq!(registry.capture(&mut Command::new("/usr/bin/true"), &stopped).unwrap_err(), "Reading the application list was cancelled.");
    let launch = registry.launch_command(&mut Command::new(missing), &live).unwrap_err();
    assert!(launch.starts_with("The application could not be started: ") && !launch.contains("application list"), "{}", launch);
    let list = registry.capture(&mut Command::new(missing), &live).unwrap_err();
    assert!(list.starts_with("Could not start the application list: ") && !list.contains("could not be started"), "{}", list);
    for work in [Work::Launch, Work::List] {
        let observed = work.unobserved(&std::io::Error::from(std::io::ErrorKind::PermissionDenied));
        assert_eq!(observed.contains("application list"), matches!(work, Work::List), "{}", observed);
        assert!(observed.ends_with("permission denied."), "{}", observed);
    }
}

// A cancel whose kill is refused says the stop failed, never that the launch could not be observed. REFUSED_KILL answers for terminate, so no signal is sent, and the pid past pid_max means even a lost hook signals nothing.
#[test]
fn a_cancel_that_cannot_stop_the_child_says_the_stop_failed() {
    let refused = std::io::Error::from(std::io::ErrorKind::PermissionDenied);
    assert_eq!(Work::List.unstopped(&refused), "Could not stop the application list: permission denied.");
    let registry = Registry::default();
    let pidfd = OwnedFd::from(std::fs::File::open("/dev/null").unwrap());
    *registry.running.lock().unwrap() = Some(Running { pid: i32::MAX, pidfd, work: Work::Launch });
    REFUSED_KILL.with(|refusal| refusal.set(Some(1)));
    let error = registry.cancel().unwrap_err();
    REFUSED_KILL.with(|refusal| refusal.set(None));
    registry.running.lock().unwrap().take();
    assert_eq!(error, "The application could not be stopped: permission denied.");
}

#[test]
fn a_registry_that_stopped_answering_says_so_in_plain_words() {
    const STOPPED: &str = "The application list stopped answering.";
    let registry = Registry::default();
    let running = registry.running.clone();
    let icons = registry.icons.clone();
    let poisoner = std::thread::spawn(move || {
        let _running = running.lock().unwrap();
        let _icons = icons.lock().unwrap();
        panic!("poison both locks");
    });
    assert!(poisoner.join().is_err());
    assert_eq!(registry.cancel().unwrap_err(), STOPPED);
    assert_eq!(registry.icon_index(&Cancellation::default()).err().as_deref(), Some(STOPPED));
}

#[test]
fn an_unknown_application_is_one_that_could_not_be_found() {
    assert_eq!(resolve("not-a-desktop-file", &Cancellation::default()).err().as_deref(), Some("That application could not be found."));
    assert_eq!(resolve("../escape.desktop", &Cancellation::default()).err().as_deref(), Some("That application could not be found."));
}

// Lines no fixture reaches (gio answering without a type, a pidfd that cannot open) are pinned by their source.
#[test]
fn retired_registry_wording_is_gone_from_the_live_source() {
    let live = include_str!("menu_registry.rs").split("\n#[cfg(test)]\nmod tests").next().unwrap();
    for retired in ["GIO application", "GIO output reader", "GIO error reader", "GIO returned", "GIO did not report", "Could not reap GIO",
                    "Could not observe GIO", "owned GIO child", "Could not read GIO", "Could not start GIO", "Could not wait for GIO",
                    "query service", "icon index service", "not a desktop entry", "byte metadata limit", "is not valid UTF-8"] {
        assert!(!live.contains(retired), "retired wording came back: {}", retired);
    }
    for plain in ["The selected item's file type is unknown.", "Application {} could not be read: it is too large.", "Application {} could not be read: it is not valid text.", "Could not open {} with {}: {}."] {
        assert!(live.contains(plain), "plain wording is missing: {}", plain);
    }
}
