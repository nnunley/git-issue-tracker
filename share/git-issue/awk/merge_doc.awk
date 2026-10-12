# Three-way merge of issue documents (docs/plans/2026-10-11-multi-user-sync-design.md §3).
# Usage: awk -f merge_doc.awk -v LIST_FIELDS="labels blocks ..." -v CONFLICTS=<path> BASE LOCAL REMOTE
# All three inputs are canonical format-2 documents: a header block of
# "key: value" lines (a line beginning with one space continues the value
# above it), then optionally a blank line, "## Comments" and comment records
# ("[ts] author: text" plus continuation lines).
#
# Output: the merged document on stdout. Each header field is compared with
# the base: a field one side changed takes that side's value, a field both
# sides set alike takes it, and a field both changed differently is a
# conflict: the local value is printed and the field goes to CONFLICTS as
# "field: <name>", "local: <value>", "remote: <value>" (values folded, as in
# the document). "updated" takes the later value; list fields are merged as
# sets against the base; comments are the union of whole records, ordered by
# timestamp. Exit 1 when there is a conflict, else 0.

function absent() { return "\001" }

# Split a comma list into set S (element -> 1) and order O[1..n]; returns n
function split_list(v, S, O,    parts, n, i, e, k) {
    k = 0
    n = split(v, parts, ",")
    for (i = 1; i <= n; i++) {
        e = parts[i]; gsub(/^[ \t]+|[ \t]+$/, "", e)
        if (e == "" || (e in S)) continue
        S[e] = 1; O[++k] = e
    }
    return k
}

# The set merge of one list field: (base ∩ local ∩ remote) ∪ (local − base) ∪
# (remote − base), in local's order, then the remote's additions
function merge_list(b, l, r,    BS, BO, LS, LO, RS, RO, nb, nl, nr, i, e, out) {
    nb = split_list(b == absent() ? "" : b, BS, BO)
    nl = split_list(l == absent() ? "" : l, LS, LO)
    nr = split_list(r == absent() ? "" : r, RS, RO)
    out = ""
    for (i = 1; i <= nl; i++) {
        e = LO[i]
        if (!(e in BS) || (e in RS)) out = out (out == "" ? "" : ",") e
    }
    for (i = 1; i <= nr; i++) {
        e = RO[i]
        if (!(e in BS) && !(e in LS)) out = out (out == "" ? "" : ",") e
    }
    if (out == "" && b == absent() && l == absent() && r == absent()) return absent()
    return out == "" ? absent() : " " out
}

function record_ts(rec) {
    if (match(rec, /^\[[^]]*\]/)) return substr(rec, 2, RLENGTH - 2)
    return ""
}

# Collect one input file into side s (1 base, 2 local, 3 remote)
{
    if (FNR == 1) { side++; part = "head"; key = ""; nrec[side] = 0 }
    if (part == "head") {
        if ($0 == "") { part = "gap"; next }
        if (substr($0, 1, 1) == " " && key != "") { val[side, key] = val[side, key] "\n" $0; next }
        i = index($0, ":")
        if (i == 0) next
        key = substr($0, 1, i - 1)
        val[side, key] = substr($0, i + 1)
        if (!((side, key) in seen)) { seen[side, key] = 1; order[side, ++nkeys[side]] = key }
        next
    }
    if ($0 == "## Comments") { part = "comments"; next }
    if (part != "comments") next
    if (substr($0, 1, 1) == " " && nrec[side] > 0) { rec[side, nrec[side]] = rec[side, nrec[side]] "\n" $0; next }
    rec[side, ++nrec[side]] = $0
}

function value(s, k) { return ((s, k) in seen) ? val[s, k] : absent() }

function put(k, v) { if (v != absent()) printf "%s:%s\n", k, v }

function note_conflict(k, l, r) {
    nconf++
    printf "field: %s\nlocal:%s\nremote:%s\n", k, (l == absent() ? "" : l), (r == absent() ? "" : r) > CONFLICTS
}

END {
    nlist = split(LIST_FIELDS, lf, " ")
    for (i = 1; i <= nlist; i++) is_list[lf[i]] = 1

    # Header keys: local's order, then keys only the remote has
    nk = 0
    for (i = 1; i <= nkeys[2]; i++) { k = order[2, i]; keys[++nk] = k; listed[k] = 1 }
    for (i = 1; i <= nkeys[3]; i++) { k = order[3, i]; if (!(k in listed)) { keys[++nk] = k; listed[k] = 1 } }
    # A key only the base had was removed by both sides: it stays removed

    for (i = 1; i <= nk; i++) {
        k = keys[i]; b = value(1, k); l = value(2, k); r = value(3, k)
        if (k == "updated") {
            put(k, (l == absent()) ? r : (r == absent() || l >= r) ? l : r)
        } else if (k in is_list) {
            put(k, merge_list(b, l, r))
        } else if (l == r || r == b) {
            put(k, l)
        } else if (l == b) {
            put(k, r)
        } else {
            note_conflict(k, l, r)
            put(k, l)
        }
    }

    # Comments: union of whole records, stable-sorted by timestamp
    n = 0
    for (i = 1; i <= nrec[2]; i++) { c = rec[2, i]; if (!(c in have)) { have[c] = 1; out[++n] = c } }
    for (i = 1; i <= nrec[3]; i++) { c = rec[3, i]; if (!(c in have)) { have[c] = 1; out[++n] = c } }
    for (i = 2; i <= n; i++) {
        c = out[i]; t = record_ts(c)
        for (j = i - 1; j >= 1 && record_ts(out[j]) > t; j--) out[j + 1] = out[j]
        out[j + 1] = c
    }
    if (n > 0) {
        print ""
        print "## Comments"
        for (i = 1; i <= n; i++) print out[i]
    }
    exit (nconf > 0 ? 1 : 0)
}
