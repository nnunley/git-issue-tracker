# Required: -v FIELDS=<pipe-separated known field names>. Input: __ISSUE__-delimited batch stream on stdin. Output: US(\037)-separated: id status title priority assignee role depends_on
function reset(   i) {
    split("", top); split("", trail_k); split("", trail_v)
    ntrail = 0; in_body = 0; pending_blank = 0; in_comments = 0
}
function emit(   i, status) {
    # Trailing headers override top headers (split front matter).
    # id never legitimately appears below the body — every write path
    # emits it first — so an "id:" line down there is body content and
    # must not let one issue masquerade as (or hide) another.
    for (i = 1; i <= ntrail; i++)
        if (trail_k[i] != "id") top[trail_k[i]] = trail_v[i]
    if (top["id"] != "") {
        status = (top["status"] != "") ? top["status"] : top["state"]
        print top["id"] OFS status OFS top["title"] OFS top["priority"] OFS top["assignee"] OFS top["role"] OFS top["depends_on"]
    }
    reset()
}
BEGIN { OFS = "\037"; header_re = "^(" FIELDS "): ?"; reset() }
{ gsub(/[[:cntrl:]]/, "") }
substr($0, 1, 10) == "__ISSUE__ " && length($0) == 50 && substr($0, 11) ~ /^[0-9a-f]+$/ {
    emit(); next
}
$0 == "## Comments" { in_comments = 1 }
in_comments == 1 { next }
in_body == 0 {
    if ($0 == "") { in_body = 1; next }
    if ($0 ~ header_re) {
        key = $0; sub(/:.*/, "", key)
        val = $0; sub(/^[a-z_]+: ?/, "", val)
        top[key] = val
    }
    next
}
{
    if ($0 == "") { pending_blank = 1; next }
    if ($0 ~ header_re) {
        # A blank line breaks trailing-block contiguity: restart
        if (pending_blank) { ntrail = 0; pending_blank = 0 }
        ntrail++
        key = $0; sub(/:.*/, "", key)
        val = $0; sub(/^[a-z_]+: ?/, "", val)
        trail_k[ntrail] = key; trail_v[ntrail] = val
    } else {
        # Prose line: whatever came before it was body, not headers
        ntrail = 0; pending_blank = 0
    }
}
