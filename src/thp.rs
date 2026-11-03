use std::os::raw::c_ulong;

// prctl(2) PR_SET_THP_DISABLE, with arg2 the boolean and the last three arguments unused.
const PR_SET_THP_DISABLE: i32 = 41;
const DISABLED: u64 = 1;
const ENABLED: u64 = 0;

// std already links the system libc, so the one symbol is declared here rather than taking a crate.
extern "C" {
    fn prctl(option: i32, ...) -> i32;
}

// Each qs thread stack lands on its own 2 MB huge page here, which measured tens of MB of PSS.
pub fn disable() {
    // corner: a failure costs memory and never the launch, see AGENTS.md "Transparent huge pages".
    if unsafe { prctl(PR_SET_THP_DISABLE, DISABLED as c_ulong, 0 as c_ulong, 0 as c_ulong, 0 as c_ulong) } != 0 {
        eprintln!("flea: transparent huge pages stayed on, the window will use more memory");
    }
}

// The setting is inherited across exec, so a foreign program gets it back before it runs.
pub fn enable() {
    // corner: a failure costs the child memory and never the launch, see AGENTS.md "Transparent huge pages".
    if unsafe { prctl(PR_SET_THP_DISABLE, ENABLED as c_ulong, 0 as c_ulong, 0 as c_ulong, 0 as c_ulong) } != 0 {
        eprintln!("flea: transparent huge pages stayed off for the program being opened");
    }
}
