// The backend and flea --clip get|clear print this JSON shape; flea --clip set prints the bare token a shell script captures.
use super::control::OfferFiles;

pub fn reply_set(result: Result<&str, &str>) -> String {
    match result {
        Ok(token) => format!(r#"{{"t":"clip","op":"set","ok":true,"token":"{}"}}"#, crate::json::escape(token)),
        Err(error) => format!(r#"{{"t":"clip","op":"set","ok":false,"error":"{}"}}"#, crate::json::escape(error)),
    }
}

pub fn reply_get(result: Result<&OfferFiles, &str>) -> String {
    match result {
        Err(error) => format!(r#"{{"t":"clip","op":"get","ok":false,"error":"{}"}}"#, crate::json::escape(error)),
        Ok(got) => format!(r#"{{"t":"clip","op":"get","ok":true,"clip":"{}","paths":{},"token":"{}","skipped":{}}}"#,
            crate::json::escape(&got.op), crate::json::string_array(&got.paths),
            crate::json::escape(&got.token), got.skipped),
    }
}

pub fn reply_clear(result: Result<bool, &str>) -> String {
    match result {
        Ok(cleared) => format!(r#"{{"t":"clip","op":"clear","ok":true,"cleared":{}}}"#, cleared),
        Err(error) => format!(r#"{{"t":"clip","op":"clear","ok":false,"error":"{}"}}"#, crate::json::escape(error)),
    }
}

// Changed lines carry no ok field: the selection is what it is, and an error rides beside none.
pub fn changed(op: &str, paths: &[String], token: &str, skipped: usize) -> String {
    format!(r#"{{"t":"clip","op":"changed","clip":"{}","paths":{},"token":"{}","skipped":{}}}"#,
        crate::json::escape(op), crate::json::string_array(paths), crate::json::escape(token), skipped)
}

pub fn none_error(e: &str) -> String {
    format!(r#"{{"t":"clip","op":"changed","clip":"none","paths":[],"token":"","skipped":0,"error":"{}"}}"#,
        crate::json::escape(e))
}
