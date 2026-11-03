// Link-walk bound tests for resolved_in: the file's own module holds the walk, this one pins its bound.
use super::*;

// A loop (a -> b -> a) and a 45-link chain past the bound of 40 answer the raw path, never hang.
#[test]
fn a_symlink_loop_and_a_chain_past_the_hop_bound_answer_the_raw_path() {
    let d = crate::backend::testdir::TestDir::new("extclass-loop");
    let local = "1 0 0:30 / / rw - ext4 /dev/a rw\n";
    let (a, b) = (d.join("a"), d.join("b"));
    std::os::unix::fs::symlink("b", &a).unwrap();
    std::os::unix::fs::symlink("a", &b).unwrap();
    let (tx, rx) = std::sync::mpsc::channel();
    let probe = a.clone();
    std::thread::spawn(move || tx.send(resolved_in(&probe, local)).unwrap());
    let looped = rx.recv_timeout(std::time::Duration::from_secs(10)).expect("a symlink loop answers, never hangs");
    assert_eq!(looped, a, "a loop answers the raw path past the hop bound");
    let target = d.dir("real");
    let mut next = target;
    for i in 0..45 {
        let link = d.join(&format!("c{i:03}"));
        std::os::unix::fs::symlink(&next, &link).unwrap();
        next = link;
    }
    assert_eq!(resolved_in(&next, local), next, "a chain past the bound answers the raw path");
}

// Links inside the kernel's own 40-link limit: resolved_in counts its hops itself, so 40 resolve and a 41st answers the raw path.
#[test]
fn the_hop_bound_is_forty_links_exactly() {
    let d = crate::backend::testdir::TestDir::new("extclass-bound");
    let local = "1 0 0:30 / / rw - ext4 /dev/a rw\n";
    let real = d.dir("real");
    let mut chains = Vec::new();
    for len in [40, 41] {
        let mut next = real.clone();
        for i in 0..len {
            let link = d.join(&format!("l{len}-{i:03}"));
            std::os::unix::fs::symlink(&next, &link).unwrap();
            next = link;
        }
        let (tx, rx) = std::sync::mpsc::channel();
        let probe = next.clone();
        std::thread::spawn(move || tx.send(resolved_in(&probe, local)).unwrap());
        chains.push((next, rx.recv_timeout(std::time::Duration::from_secs(10)).expect("a long chain answers, never hangs")));
    }
    assert_eq!(chains[0].1, real, "a 40-link chain resolves to its target");
    assert_eq!(chains[1].1, chains[1].0, "a 41-link chain answers the raw path");
}
