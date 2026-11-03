// Why a name is refused, one clause per fault, so a refusal never names a character the name does not hold.
pub fn name_refusal(name: &str) -> Option<&'static str> {
    if name.is_empty() { Some("a name cannot be empty") }
    else if name == "." || name == ".." { Some("a name cannot be a single dot or a double dot") }
    else if name.contains('/') { Some("a name cannot contain /") }
    else if name.contains('\0') { Some("a name cannot contain a null character") }
    else { None }
}

// The same clause as a whole sentence, for the lines a person reads as they stand.
pub fn name_refusal_sentence(name: &str) -> Option<String> {
    name_refusal(name).map(|clause| format!("A{}.", &clause[1..]))
}
