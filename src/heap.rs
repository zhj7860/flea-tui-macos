// mallopt(3) M_MMAP_THRESHOLD, the value at /usr/include/malloc.h line 136 on this box.
const M_MMAP_THRESHOLD: i32 = -3;
// A 100,000-name arena and its span vector both cross 128 KiB, so both are served by mmap and both go back to the OS on free.
const THRESHOLD_BYTES: i32 = 131072;

// mallopt(3) M_ARENA_MAX, the value at /usr/include/malloc.h line 141 on this box.
const M_ARENA_MAX: i32 = -8;

// std already links the system libc, so its two symbols are declared here rather than taking a crate.
extern "C" {
    fn mallopt(param: i32, value: i32) -> i32;
    fn malloc_trim(pad: usize) -> i32;
}

// Setting M_MMAP_THRESHOLD, M_TRIM_THRESHOLD or M_MMAP_MAX sets glibc's one no_dyn_threshold flag, so this stops the mmap ratchet that doubles the backend on a second large listing and freezes trim_threshold with it, the favourable direction; see AGENTS.md "The listing arena returns to the OS".
pub fn pin_mmap_threshold() {
    // corner: glibc 2.44 answers 1 for every parameter number here, including undefined ones, so there is no failure to report; see AGENTS.md.
    let _ = unsafe { mallopt(M_MMAP_THRESHOLD, THRESHOLD_BYTES) };
}

// Each glibc arena a helper thread opens keeps its pages after the thread ends; one arena serves a process with few threads.
pub fn one_arena() {
    // corner: as above, glibc answers 1 whatever the parameter, so there is no failure to report.
    let _ = unsafe { mallopt(M_ARENA_MAX, 1) };
}

// With one arena, the blocks a picture's encoding freed stay inside [heap] below live ones; malloc_trim(3) returns their pages.
pub fn give_back() {
    let _ = unsafe { malloc_trim(0) };
}

#[cfg(test)]
mod tests {
    use super::*;

    // The probe runs in a child behind this marker, because 127 other tests share this process's heap.
    const CHILD_MARKER: &str = "FLEA_HEAP_PROBE";
    const CHILD_TEST: &str = "heap::tests::a_freed_large_block_does_not_ratchet_the_mmap_threshold";
    // Larger than any threshold glibc adopts on its own, so freeing it is what would raise the threshold unpinned.
    const RATCHET_BYTES: usize = 8 * 1024 * 1024;
    // Above the pinned threshold even before the live heap size is added.
    const PROBE_FLOOR_BYTES: usize = 1024 * 1024;
    // Past every free chunk in the current heap, so only the threshold decides where the probe lands.
    const PROBE_MARGIN_BYTES: usize = 1024 * 1024;
    // Below the pinned threshold, so it must come from the arena that [heap] describes.
    const ARENA_BYTES: usize = 65536;

    // Sample input, one line of /proc/self/maps: "5601f0a21000-5601f0a42000 rw-p 00000000 00:00 0 [heap]"
    fn heap_span() -> Option<(usize, usize)> {
        let maps = std::fs::read_to_string("/proc/self/maps").ok()?;
        let line = maps.lines().find(|l| l.ends_with("[heap]"))?;
        let (lo, hi) = line.split_whitespace().next()?.split_once('-')?;
        Some((
            usize::from_str_radix(lo, 16).ok()?,
            usize::from_str_radix(hi, 16).ok()?,
        ))
    }

    fn in_heap(addr: usize) -> bool {
        match heap_span() {
            Some((lo, hi)) => addr >= lo && addr < hi,
            None => false,
        }
    }

    fn probe_bytes(heap_bytes: usize) -> usize {
        let probe_bytes = heap_bytes
            .checked_add(PROBE_MARGIN_BYTES)
            .expect("the heap size must leave room for a probe")
            .max(PROBE_FLOOR_BYTES);
        assert!(
            probe_bytes < RATCHET_BYTES,
            "the {} byte heap leaves no probe size below the {} byte ratchet",
            heap_bytes,
            RATCHET_BYTES
        );
        probe_bytes
    }

    #[test]
    fn probe_size_stays_between_the_live_heap_and_ratchet() {
        for heap_bytes in (ARENA_BYTES..RATCHET_BYTES - PROBE_MARGIN_BYTES).step_by(PROBE_MARGIN_BYTES) {
            let probe_bytes = probe_bytes(heap_bytes);
            assert!(probe_bytes > heap_bytes);
            assert!(probe_bytes < RATCHET_BYTES);
        }
    }

    // The guard itself: ratchet the threshold the way a first large listing does, then read where the probe landed.
    fn probe() {
        pin_mmap_threshold();
        let arena = vec![0u8; ARENA_BYTES];
        assert!(
            in_heap(arena.as_ptr() as usize),
            "a {} byte allocation at {:x} is outside [heap] {:x?}, so this thread is not on the main arena and the check below could not fail",
            ARENA_BYTES,
            arena.as_ptr() as usize,
            heap_span()
        );
        // glibc raises its mmap threshold to the size of any mmapped block it frees, unless a mallopt froze it.
        drop(std::hint::black_box(vec![0u8; RATCHET_BYTES]));
        let (lo, hi) = heap_span().expect("the probe needs a main heap");
        let probe_bytes = probe_bytes(hi - lo);
        let probed = vec![0u8; probe_bytes];
        assert!(
            !in_heap(probed.as_ptr() as usize),
            "a {} byte allocation came from [heap], so the mmap threshold ratcheted past it",
            probe_bytes
        );
        drop(arena);
        drop(probed);
    }

    // corner: this cannot redden for M_TRIM_THRESHOLD or M_MMAP_MAX, which freeze the ratchet by accident at the same default.
    #[test]
    fn a_freed_large_block_does_not_ratchet_the_mmap_threshold() {
        if std::env::var_os(CHILD_MARKER).is_some() {
            probe();
            return;
        }
        rerun(CHILD_MARKER, CHILD_TEST);
    }

    // Runs one test of this binary alone in a child behind its marker.
    fn rerun(marker: &str, test: &str) {
        let exe = std::env::current_exe().expect("a test binary knows its own path");
        let out = std::process::Command::new(exe)
            .args(["--exact", "--test-threads=1", "--nocapture", test])
            .env(marker, "1")
            // libtest runs a test on a spawned thread, which glibc would hand its own mmapped arena, and nothing that arena serves is ever in [heap].
            .env("MALLOC_ARENA_MAX", "1")
            .output()
            .expect("the test binary re-executes");
        let report = format!("{}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
        assert!(out.status.success(), "the probe child failed: {}", report);
        // Renaming the test would filter the child to nothing and exit 0, so it has to say it ran one.
        assert!(report.contains("1 passed"), "the probe child ran no test, so {} no longer names one: {}", test, report);
    }

    const ARENA_CHILD_MARKER: &str = "FLEA_ARENA_PROBE";
    const ARENA_REPORT: &str = "arenas before main: ";
    // Threads that allocate as a picture job does; each would open its own arena without the cap.
    const HELPER_THREADS: usize = 4;
    extern "C" {
        fn open_memstream(buf: *mut *mut std::ffi::c_char, size: *mut usize) -> *mut std::ffi::c_void;
        fn malloc_info(options: i32, stream: *mut std::ffi::c_void) -> i32;
        fn fclose(stream: *mut std::ffi::c_void) -> i32;
        fn free(ptr: *mut std::ffi::c_void);
    }

    // Sample output of malloc_info(3): '<malloc version="1">\n<heap nr="0">\n<sizes>...</heap>\n<heap nr="1">'
    fn arenas() -> usize {
        let mut buf: *mut std::ffi::c_char = std::ptr::null_mut();
        let mut size = 0usize;
        unsafe {
            let stream = open_memstream(&mut buf, &mut size);
            assert!(!stream.is_null(), "open_memstream failed");
            malloc_info(0, stream);
            fclose(stream);
            let text = std::slice::from_raw_parts(buf as *const u8, size).to_vec();
            free(buf.cast());
            text.windows(b"<heap nr=\"".len()).filter(|w| w == b"<heap nr=\"").count()
        }
    }

    // corner: libtest runs every test on a thread that already holds a second arena, where a cap of 2 changes nothing, so the probe runs before main on the one thread tui::run has when it calls one_arena.
    #[used]
    #[link_section = ".init_array"]
    static ARENA_PROBE_BEFORE_MAIN: extern "C" fn() = arena_probe_before_main;

    extern "C" fn arena_probe_before_main() {
        if std::env::var_os(ARENA_CHILD_MARKER).is_none() {
            return;
        }
        one_arena();
        let before = arenas();
        let helpers: Vec<_> = (0..HELPER_THREADS)
            .map(|_| std::thread::spawn(|| std::hint::black_box(vec![0u8; ARENA_BYTES]).len()))
            .collect();
        for helper in helpers {
            helper.join().expect("a helper thread finishes");
        }
        println!("{}{} then {}", ARENA_REPORT, before, arenas());
        std::process::exit(0);
    }

    #[test]
    fn helper_threads_share_one_arena() {
        let exe = std::env::current_exe().expect("a test binary knows its own path");
        // --list keeps a child that skipped the probe from running this test again.
        let out = std::process::Command::new(exe)
            .arg("--list")
            .env(ARENA_CHILD_MARKER, "1")
            .env_remove("MALLOC_ARENA_MAX")
            .env_remove("GLIBC_TUNABLES")
            .output()
            .expect("the test binary re-executes");
        let report = format!("{}{}", String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
        assert!(out.status.success(), "the arena probe child failed: {}", report);
        // The main arena alone before the helpers and after them; a missing or wider cap gives each helper its own.
        assert!(report.contains(&format!("{}1 then 1\n", ARENA_REPORT)), "a helper thread opened an arena of its own: {}", report);
    }

    const GIVE_BACK_MARKER: &str = "FLEA_GIVE_BACK_PROBE";
    const GIVE_BACK_TEST: &str = "heap::tests::a_sent_picture_returns_the_heap_pages_freed_below_live_blocks";
    // Under the pinned threshold, so every block comes from [heap]; 128 of them free 1 MiB below the block kept after them.
    const SMALL_BYTES: usize = 8192;
    const SMALL_BLOCKS: usize = 128;
    // Half the freed bytes in KiB, the least send must return.
    const GIVE_BACK_MIN_KB: usize = SMALL_BLOCKS * SMALL_BYTES / 2 / 1024;

    // Sample input, a mapping header then one of its fields in /proc/self/smaps: "5601f0a21000-5601f0a42000 rw-p 00000000 00:00 0 [heap]", "Anonymous:          1056 kB"
    fn heap_anonymous_kb() -> usize {
        let smaps = std::fs::read_to_string("/proc/self/smaps").expect("smaps is readable");
        let mut in_heap = false;
        for line in smaps.lines() {
            if line.split_whitespace().next().is_some_and(|range| range.contains('-') && range.bytes().all(|b| b == b'-' || b.is_ascii_hexdigit())) {
                in_heap = line.ends_with("[heap]");
            } else if let Some(kb) = line.strip_prefix("Anonymous:").filter(|_| in_heap) {
                return kb.trim().trim_end_matches("kB").trim().parse().expect("Anonymous is a number of kB");
            }
        }
        0
    }

    fn give_back_probe() {
        pin_mmap_threshold();
        let blocks: Vec<Vec<u8>> = (0..SMALL_BLOCKS).map(|_| std::hint::black_box(vec![1u8; SMALL_BYTES])).collect();
        let kept = std::hint::black_box(vec![1u8; SMALL_BYTES]);
        assert!(in_heap(blocks[0].as_ptr() as usize) && in_heap(kept.as_ptr() as usize), "the blocks are outside [heap], so the check below could not fail");
        drop(blocks);
        let before = heap_anonymous_kb();
        crate::tui::graphics::send(&mut Vec::new(), vec![1u8; 1]).expect("a Vec takes the write");
        let after = heap_anonymous_kb();
        assert!(after + GIVE_BACK_MIN_KB <= before, "[heap] kept {} of {} kB after a picture was sent", after, before);
    }

    #[test]
    fn a_sent_picture_returns_the_heap_pages_freed_below_live_blocks() {
        if std::env::var_os(GIVE_BACK_MARKER).is_some() {
            give_back_probe();
            return;
        }
        rerun(GIVE_BACK_MARKER, GIVE_BACK_TEST);
    }
}
