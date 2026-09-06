# Required: -v FORMAT=1|2. Input: whole note on stdin.
# Output: comments after "## Comments" as folded records: a line beginning
# with "[" starts a record; in format 2 a line beginning with one space is a
# continuation and is passed through; in format 1 every other line inside a
# started record is a legacy continuation, emitted with one leading space
# added, so that folding and then unfolding is the identity (a blank line
# becomes the lone-space continuation " ", which format 2 also accepts).
/^## Comments$/ { p = 1; next }
!p { next }
/^\[/ { print; started = 1; next }
started && FORMAT == 1 { print " " $0; next }
started && /^ / { print; next }
