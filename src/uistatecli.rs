use crate::jsondoc;
use crate::shelfplugin;
use crate::uistore;

// flea --ui-state, the window's path to the state file (the TUI writes it directly): no argument reads it, a JSON patch merges under the lock.
pub fn ui_state(args: &[String]) -> i32 {
    let store = match uistore::Store::user() {
        Ok(store) => store,
        Err(e) => {
            eprintln!("flea: {}", e);
            return 2;
        }
    };
    if args.len() > 3 {
        crate::usage("--ui-state takes nothing, or one JSON object");
    }
    let before = store.read();
    let was = shelf_enabled(&before);
    let state = match args.get(2) {
        None => before,
        Some(patch) => {
            let merged = jsondoc::parse(patch)
                .map_err(|e| format!("the ui.json patch is not JSON ({})", e))
                .and_then(|p| store.update(&p));
            match merged {
                Ok(next) => next,
                Err(e) => {
                    eprintln!("flea: {}", e);
                    return 2;
                }
            }
        }
    };
    // B1: only the window's Settings switch installs the shelf plugin, and its writes all come through here, so the bar follows it.
    let now = shelf_enabled(&state);
    if now != was {
        if let Err(e) = shelfplugin::sync(now) {
            if now {
                eprintln!("flea: the shelf plugin was not installed ({})", e);
            } else {
                eprintln!("flea: the shelf plugin was not removed ({})", e);
            }
        }
    }
    print!("{}", jsondoc::render(&state));
    0
}

// Directive 38: the shelf ships off, so anything but a stored true is off.
pub fn shelf_enabled(state: &jsondoc::Json) -> bool {
    state.get("shelf").and_then(|s| s.get("enabled")).and_then(|v| v.as_bool()) == Some(true)
}
