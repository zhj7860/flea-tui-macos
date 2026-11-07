// The system clipboard as text, and on macOS as a file list too: Finder and every Mac application
// read the pasteboard's file list, so a copy made here pastes as files elsewhere and a copy made
// elsewhere pastes here. pbcopy and wl-copy are both spawned argv-direct with the text on stdin;
// a session holding neither says so instead of dropping it.
use std::io::{self, Write};
use std::process::{Command, Stdio};

// macOS takes both flavours through AppKit: the paths are a file list Finder and every Mac
// application paste as files, and the same paths as text so a text field gets them. The script is
// run as a file with the paths as argv, so no name can ever be read as script text.
#[cfg(target_os = "macos")]
const MACOS_CLIPBOARD: &str = r#"use framework "AppKit"
use scripting additions

on run argv
	set pb to current application's NSPasteboard's generalPasteboard()
	if (count of argv) is 0 then
		set out to ""
		try
			set ys to the clipboard as list
			repeat with y in ys
				try
					set out to out & (POSIX path of y) & linefeed
				end try
			end repeat
			if out is not "" then return out
		end try
		try
			set xs to the clipboard as «class furl»
			set t to POSIX path of xs
			if (class of t) is list then
				repeat with one in t
					set out to out & (one as text) & linefeed
				end repeat
			else
				set out to (t as text) & linefeed
			end if
		on error
			return ""
		end try
		return out
	else
		set paths to {}
		repeat with p in argv
			set end of paths to (p as text)
		end repeat
		set pl to current application's NSArray's arrayWithArray:paths
		set {d, e} to current application's NSPropertyListSerialization's dataWithPropertyList:pl format:(current application's NSPropertyListXMLFormat_v1_0) options:0 |error|:(reference)
		pb's clearContents()
		pb's declareTypes:{current application's NSFilenamesPboardType, current application's NSStringPboardType} owner:(missing value)
		pb's setData:d forType:(current application's NSFilenamesPboardType)
		pb's setString:(pl's componentsJoinedByString:linefeed) forType:(current application's NSStringPboardType)
		return "ok"
	end if
end run
"#;

// The script runs by path, and is rewritten only when its text changes, so a copy pays one read.
#[cfg(target_os = "macos")]
fn macos_script() -> io::Result<std::path::PathBuf> {
    let dir = crate::userfile::cache_home().join("flea");
    std::fs::create_dir_all(&dir)?;
    let path = dir.join("clipboard.applescript");
    let current = std::fs::read(&path).map(|bytes| bytes == MACOS_CLIPBOARD.as_bytes()).unwrap_or(false);
    if !current {
        let temp = dir.join(format!("clipboard.applescript.{}.tmp", std::process::id()));
        std::fs::write(&temp, MACOS_CLIPBOARD)?;
        std::fs::rename(&temp, &path)?;
    }
    Ok(path)
}

// Puts the files on the pasteboard as a file list and as text, which is what Finder itself writes.
#[cfg(target_os = "macos")]
pub fn copy_files(paths: &[String]) -> io::Result<()> {
    if paths.is_empty() {
        return Ok(());
    }
    let script = macos_script()?;
    let output = Command::new("osascript")
        .arg(&script)
        .args(paths)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::piped())
        .output()?;
    if output.status.success() {
        return Ok(());
    }
    let why = String::from_utf8_lossy(&output.stderr).trim().to_string();
    Err(io::Error::other(if why.is_empty() { "osascript refused the file list".to_string() } else { why }))
}

#[cfg(not(target_os = "macos"))]
pub fn copy_files(paths: &[String]) -> io::Result<()> {
    copy_text(&paths.join("\n"))
}

// The files a copy made anywhere put on the pasteboard, as absolute paths. An empty answer is a
// clipboard holding text, a single non-file item, or no macOS to ask; an item that is gone is
// dropped, the way a paste of a deleted file is nothing to copy.
#[cfg(target_os = "macos")]
pub fn read_files() -> Vec<String> {
    let Ok(script) = macos_script() else { return Vec::new() };
    let Ok(output) = Command::new("osascript")
        .arg(&script)
        .stdin(Stdio::null())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .output()
    else {
        return Vec::new();
    };
    if !output.status.success() {
        return Vec::new();
    }
    // AppleScript's text line separator is a carriage return and its paths join with one, so both
    // endings end an item.
    String::from_utf8_lossy(&output.stdout)
        .split(|c| c == '\n' || c == '\r')
        .map(str::trim)
        .filter(|line| !line.is_empty() && std::path::Path::new(line).exists())
        .map(str::to_owned)
        .collect()
}

#[cfg(not(target_os = "macos"))]
pub fn read_files() -> Vec<String> {
    Vec::new()
}

pub fn copy_text(text: &str) -> io::Result<()> {
    let program = if cfg!(target_os = "macos") { "pbcopy" } else { "wl-copy" };
    let mut child = Command::new(program)
        .stdin(Stdio::piped())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .spawn()?;
    if let Some(mut stdin) = child.stdin.take() {
        // A tool that stopped reading is reported by its status below; the write's error is not ours.
        let _ = stdin.write_all(text.as_bytes());
    }
    let status = child.wait()?;
    if status.success() {
        Ok(())
    } else {
        Err(io::Error::other(format!("{program} refused the text")))
    }
}
