// What a registry child serves, so a fault in the shared start, wait and stop code names the list read or the launch that met it.
#[derive(Clone, Copy)]
pub(super) enum Work { List, Launch }

impl Work {
    // A list child owns its group and its pipes; a launcher's descendants can inherit both, so neither applies there.
    pub(super) fn group(self) -> bool { matches!(self, Work::List) }
    pub(super) fn unstarted(self, cause: &std::io::Error) -> String {
        let cause = crate::error::io_message(cause);
        match self {
            Work::List => format!("Could not start the application list: {}.", cause),
            Work::Launch => format!("The application could not be started: {}.", cause),
        }
    }
    pub(super) fn unobserved(self, cause: &std::io::Error) -> String {
        let cause = crate::error::io_message(cause);
        match self {
            Work::List => format!("The application list could not be read: {}.", cause),
            Work::Launch => format!("Flea could not tell whether the application started: {}.", cause),
        }
    }
    pub(super) fn unstopped(self, cause: &std::io::Error) -> String {
        let cause = crate::error::io_message(cause);
        match self {
            Work::List => format!("Could not stop the application list: {}.", cause),
            Work::Launch => format!("The application could not be stopped: {}.", cause),
        }
    }
    pub(super) fn check(self, cancel: &super::trashmanifest::Cancellation) -> Result<(), String> {
        cancel.check().map_err(|_| match self {
            Work::List => "Reading the application list was cancelled.".to_string(),
            Work::Launch => "Opening the application was cancelled.".to_string(),
        })
    }
}
