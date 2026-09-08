# Required: -v FORMAT=1|2. Input: whole note on stdin.
# Output: comments after "## Comments" as folded records: a line beginning
# with "[" starts a record; in format 2 a line beginning with one space is a
# continuation and is passed through; in format 1 every other line inside a
# started record is a legacy continuation, emitted with one leading space
# added, so that folding and then unfolding is the identity (a blank line
# becomes the lone-space continuation " ", which format 2 also accepts).
#
# Text before the first "[" record (a hand-edited format-1 note whose
# ## Comments section opens with prose) used to be dropped on read and on
# upgrade. The rule now: the first non-blank such line starts a record and is
# printed verbatim, with no "[ts] author:" prefix invented for it, and the
# lines after it fold as continuations. Nothing is lost, and consumers
# already tolerate a record that does not match the "[ts] author: text"
# shape — the Elisp parser returns (nil nil text) for one. Blank lines ahead
# of the first record are separators, not text, and are still dropped; a
# record must not begin with nothing.
/^## Comments$/ { p = 1; next }
!p { next }
/^\[/ { print; started = 1; next }
!started && /^[[:space:]]*$/ { next }
!started { print; started = 1; next }
started && FORMAT == 1 { print " " $0; next }
started && /^ / { print; next }
