# Field-level diff of two issue documents (docs/plans/2026-10-11-multi-user-sync-design.md §6).
# Usage: awk -f diff_doc.awk OLD NEW
# Both inputs are canonical format-2 documents (see merge_doc.awk). Prints
# one change per line, header fields in NEW's order, then one "comment" line
# per comment record NEW adds:
#   <field>: <old> → <new>     a changed field
#   <field>: + <new>           a field NEW adds
#   <field>: - <old>           a field NEW drops
#   description changed        (its text is not repeated)
# "updated" and the "v" format marker are bookkeeping and never listed.

{
    if (FNR == 1) { side++; part = "head"; key = "" }
    if (part == "head") {
        if ($0 == "") { part = "gap"; next }
        if (substr($0, 1, 1) == " " && key != "") { val[side, key] = val[side, key] "\n" $0; next }
        i = index($0, ":")
        if (i == 0) next
        key = substr($0, 1, i - 1)
        v = substr($0, i + 1); sub(/^ /, "", v)
        val[side, key] = v
        if (!((side, key) in seen)) { seen[side, key] = 1; order[side, ++nkeys[side]] = key }
        next
    }
    if ($0 == "## Comments") { part = "comments"; next }
    if (part != "comments") next
    if (substr($0, 1, 1) == " " && n[side] > 0) { rec[side, n[side]] = rec[side, n[side]] "\n" $0; next }
    rec[side, ++n[side]] = $0
}

function skip(k) { return k == "updated" || k == "v" }

END {
    for (i = 1; i <= nkeys[2]; i++) {
        k = order[2, i]
        if (skip(k)) continue
        if (!((1, k) in seen)) {
            if (k == "description") print "description changed"; else print k ": + " val[2, k]
        } else if (val[1, k] != val[2, k]) {
            if (k == "description") print "description changed"; else print k ": " val[1, k] " → " val[2, k]
        }
    }
    for (i = 1; i <= nkeys[1]; i++) {
        k = order[1, i]
        if (skip(k) || ((2, k) in seen)) continue
        if (k == "description") print "description changed"; else print k ": - " val[1, k]
    }
    for (i = 1; i <= n[1]; i++) had[rec[1, i]] = 1
    for (i = 1; i <= n[2]; i++) if (!(rec[2, i] in had)) print "comment"
}
