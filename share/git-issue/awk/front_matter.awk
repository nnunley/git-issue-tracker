# Required: -v FIELDS=<pipe-separated known field names>
BEGIN { known_re = "^(" FIELDS "):" }
{ lines[++n] = $0 }
END {
    # Find where comments start (if any)
    comments_at = n + 1
    for (i = 1; i <= n; i++) {
        if (lines[i] == "## Comments") { comments_at = i; break }
    }
    # Collect top headers (before first blank line)
    top_count = 0
    for (i = 1; i <= n; i++) {
        if (lines[i] == "") break
        if (lines[i] ~ /^[a-z_]+:/) {
            top_count++
            top_headers[top_count] = lines[i]
            # Extract key for dedup
            split(lines[i], kv, ": *")
            top_keys[top_count] = kv[1]
        }
    }
    # Find trailing header block: scan backwards from end/comments,
    # skip any non-header lines (stray text), then collect contiguous headers.
    # Only KNOWN fields count as trailing headers, so body prose like
    # "note: remember this" is not swallowed out of the body.
    scan = comments_at - 1
    while (scan > 0 && lines[scan] == "") scan--
    while (scan > 0 && lines[scan] !~ known_re) scan--
    trail_end = scan
    trail_start = trail_end + 1
    for (i = trail_end; i > 0; i--) {
        if (lines[i] ~ known_re) {
            trail_start = i
        } else {
            break
        }
    }
    # Find first blank line to know where top headers end
    first_blank = n + 1
    for (i = 1; i <= n; i++) {
        if (lines[i] == "") { first_blank = i; break }
    }
    # Only treat as trailing headers if they come after the top block
    # id never legitimately appears below the body (every write path
    # emits it first), so trailing "id:" lines are body content, not headers
    trail_count = 0
    if (trail_start > first_blank && trail_start <= trail_end) {
        for (i = trail_start; i <= trail_end; i++) {
            if (lines[i] ~ known_re && lines[i] !~ /^id:/) {
                trail_count++
                trail_headers[trail_count] = lines[i]
                split(lines[i], kv, ": *")
                trail_key_set[kv[1]] = 1
            }
        }
    }
    # Print top headers, skipping any overridden by trailing
    for (i = 1; i <= top_count; i++) {
        if (!(top_keys[i] in trail_key_set)) {
            print top_headers[i]
        }
    }
    # Print trailing headers
    for (i = 1; i <= trail_count; i++) {
        print trail_headers[i]
    }
}
