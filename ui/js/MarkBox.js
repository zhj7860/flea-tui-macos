.pragma library

// The picker's mark box: bodySmall plus a hairline inside a two-hairline border, which a Rectangle's size includes.
// Sample input: outer(13, 1) === 18.
function inner(bodySmall, hairline) { return bodySmall + hairline }
function border(hairline) { return 2 * hairline }
function outer(bodySmall, hairline) { return inner(bodySmall, hairline) + 2 * border(hairline) }
