# Required: -v FORMAT=1|2. Input: whole note on stdin.
# Output: comments after "## Comments" as folded records: a line beginning
# with "[" starts a record; in format 2 a line beginning with one space is a
# continuation and is passed through; in format 1 any other non-empty line
# is a legacy continuation and is emitted with one leading space added.
/^## Comments$/ { p = 1; next }
!p { next }
/^\[/ { print; started = 1; next }
started && FORMAT == 1 && $0 != "" { print " " $0; next }
started && /^ / { print; next }
