// One flash write: its job, its failures and the stream into the pipeline.
use crate::backend::flash::STALL_SECS;
use crate::backend::flashpump::{drive, Feed, Unpacker};
use std::sync::atomic::AtomicBool;
use std::time::Duration;

// What one flash phase can end in; flashop maps each to its flashdone err.
#[derive(Debug)]
pub enum Fail {
    Cancelled,
    Io(String),
    // The first differing offset a verify found, a whole chunk's own start.
    Mismatch(u64),
    NoSpace,
    Decompress(String),
    Sandbox,
}

// One flash write's inputs, bundled so the functions below stay under the argument limit.
pub(crate) struct Job<'a> {
    pub image: &'a std::path::Path,
    pub kind: &'a str,
    pub member: &'a str,
    pub dest: &'a std::fs::File,
    pub drive_bytes: u64,
    pub cancel: &'a AtomicBool,
    // The probe total when the probe knew it; a short stream is refused against it.
    pub probe_total: u64,
    pub probe_known: bool,
    pub stall: Duration,
    // A test build's stand-in decompressor argv, carried here so parallel tests never share it.
    #[cfg(test)]
    pub decompressor: Option<Vec<String>>,
    // A test build's hook, called with the bytes read each time the reader finds every buffer in use.
    #[cfg(test)]
    pub on_starved: crate::backend::flashpump::Starved,
}

impl<'a> Job<'a> {
    pub(crate) fn new(image: &'a std::path::Path, kind: &'a str, member: &'a str, dest: &'a std::fs::File, drive_bytes: u64, cancel: &'a AtomicBool) -> Job<'a> {
        Job {
            image,
            kind,
            member,
            dest,
            drive_bytes,
            cancel,
            probe_total: 0,
            probe_known: false,
            stall: stall_limit(),
            #[cfg(test)]
            decompressor: None,
            #[cfg(test)]
            on_starved: None,
        }
    }

    // The hook the reader calls when it finds no free buffer; only a test build has one.
    #[cfg(test)]
    pub(crate) fn starved_hook(&self) -> crate::backend::flashpump::Starved {
        self.on_starved.clone()
    }

    #[cfg(not(test))]
    pub(crate) fn starved_hook(&self) -> crate::backend::flashpump::Starved {
        None
    }
}

// Writes the image to dest and answers one XXH64 per 4 MiB for the verify plus the written byte count.
pub fn write_stream(job: &Job, on_progress: &mut dyn FnMut(u64, u64)) -> Result<(Vec<u64>, u64), Fail> {
    if job.kind == "iso" || job.kind == "img" {
        let src = std::fs::File::open(job.image).map_err(|e| Fail::Io(e.to_string()))?;
        return drive(Feed { source: Box::new(src), unpacker: None }, job, on_progress, &mut || {});
    }
    let (mut child, input) = super::flashpipe::spawn_producer(job)?;
    let Some(pipe) = child.stdout.take() else {
        super::flashpipe::try_kill(&mut child);
        return Err(Fail::Decompress("the unpacker has no output".to_string()));
    };
    let feed = Feed { source: Box::new(pipe), unpacker: Some(Unpacker { stall: job.stall, input: input.as_ref() }) };
    let out = drive(feed, job, on_progress, &mut || super::flashpipe::try_kill(&mut child));
    let status = child.wait().map_err(|e| Fail::Decompress(e.to_string()))?;
    let done = out?;
    if !status.success() {
        return Err(Fail::Decompress(format!("the unpacker exited with status {status}")));
    }
    Ok(done)
}

pub fn stall_limit() -> Duration {
    Duration::from_secs(STALL_SECS)
}

#[cfg(test)]
#[path = "flashwrite_tests.rs"]
mod tests;
