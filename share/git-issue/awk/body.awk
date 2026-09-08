# Required: -v FIELDS=<pipe-separated known field names>
BEGIN {
    known_re = "^(" FIELDS "):"
    # Never a trailing header: "id" is always written first, and
    # "description" is a format-2 top-block header only. Either one below the
    # body is body prose, so it must not anchor or extend a trailing block.
    # Must stay identical to front_matter.awk's not_trailing_re (and match
    # what extract_issues.awk drops in emit()): if the parsers disagree, one
    # puts a line in the body that another reads as a header, and the same
    # note means two different things.
    not_trailing_re = "^(id|description):"
}
{ lines[++n] = $0 }
END {
    # Find where comments start
    comments_at = n + 1
    for (i = 1; i <= n; i++) {
        if (lines[i] == "## Comments") { comments_at = i; break }
    }
    # Find trailing header block (same logic as parse_front_matter:
    # only KNOWN fields count, so body prose is not swallowed)
    scan = comments_at - 1
    while (scan > 0 && lines[scan] == "") scan--
    while (scan > 0 && (lines[scan] !~ known_re || lines[scan] ~ not_trailing_re)) scan--
    trail_end = scan
    trail_start = trail_end + 1
    for (i = trail_end; i > 0; i--) {
        if (lines[i] ~ known_re && lines[i] !~ not_trailing_re) {
            trail_start = i
        } else {
            break
        }
    }
    # Body starts after first blank line, ends before trailing headers
    body_start = 0
    for (i = 1; i <= n; i++) {
        if (lines[i] == "") { body_start = i + 1; break }
    }
    if (body_start == 0) body_start = n + 1
    # Only treat as trailing headers if they come after the body start
    if (trail_start > body_start) {
        body_end = trail_start - 1
    } else {
        body_end = comments_at - 1
    }
    if (body_end >= comments_at) body_end = comments_at - 1
    # Trim trailing blank lines from body
    while (body_end >= body_start && lines[body_end] == "") body_end--
    for (i = body_start; i <= body_end; i++) {
        print lines[i]
    }
}
