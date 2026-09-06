# Input: front matter (parse_front_matter output) on stdin.
# Output: the same headers reordered into the format-2 canonical prefix:
# the "id:" line first, then the "v: 2" marker, then every other header in
# input order.  Any pre-existing "v:" line is dropped (the marker is emitted
# from here, exactly once) and the "description:" header is dropped along
# with its continuation lines, because the caller re-emits the description
# last, folded, after this prefix (R-format-marker, R-store-continuation).
# A note with no "id:" line (hand-authored import data) must not gain an
# empty first line, so the id is only printed when one was present.
/^id:/ { if (!have_id) { id = $0; have_id = 1 } skip = 0; next }
/^v:/ { skip = 1; next }
/^description:/ { skip = 1; next }
/^ / { if (!skip) rest[++n] = $0; next }
{ skip = 0; rest[++n] = $0 }
END {
    if (have_id) print id
    print "v: 2"
    for (i = 1; i <= n; i++) print rest[i]
}
