# draft-ndn-porcelain-output-00: Porcelain Output for git-issue Read Commands

**Status:** DRAFT
**Corpus:** green
**Category:** Standards-Track
**Authors:** Norman Nunley, Jr <nnunley@gmail.com>, Claude (drafting agent)

## Abstract

Every git-issue read command prints colored, decorated text meant for a
terminal; nothing prints a format a program can rely on. This RFC adds a
`--porcelain` flag, in the sense git-status(1) gives the word, to every read
command: a stable, tab-separated or `key: value` output with a frozen
column order, no styling, and git's leading-space continuation rule for
multi-line values. The same continuation rule is adopted for the stored
note format, so multi-line comments and descriptions are unambiguous at
rest and not only on the way out.

## Motivation

The first consumer is an Emacs integration (a magit extension, specified
separately), which needs to list, show, and act on issues from a buffer.
Today that consumer would have to strip ANSI escapes and parse prose such
as `#10a45d6 [blocked] Add Beads round-trip tests (P: medium) → Norman`,
a format that changes whenever the display does. Agents driving the tool
from a shell have the same problem: `list --all` grew a `[<name>] ` prefix
in draft-ndn-multi-project-registry-02 precisely because nothing else in
the output was parseable.

A second problem surfaced while researching the first. The stored note
has no continuation convention: `git issue comment <id> "$(printf 'one\ntwo')"`
writes the second line verbatim into the `## Comments` section, where it
is indistinguishable from stray text. Any porcelain `show` built on that
storage inherits the ambiguity. Git resolved the same problem for commit
headers (a continuation line begins with one space); this RFC adopts that
rule in both places.

## Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174)
when, and only when, they appear in all capitals, as shown here.

- **read command** — a command that prints repository state and writes
  nothing: `list`, `show`, `ready`, `queue`, `topo`, `deps`, `dep list`,
  `scan-commits`, `repo list`, `setup-sync status`.
- **porcelain mode** — the output mode selected by `--porcelain`.
- **record** — one line of porcelain output for the line-oriented shapes,
  or the whole header block for `show`.
- **single-line field** — a header field whose value can never span lines:
  every known field except `description`.
- **continuation line** — a line beginning with exactly one space, which
  extends the value on the preceding line; the space is not part of the
  value.
- **note** — the blob stored at `refs/notes/issue-<id>` that holds one
  issue.
- **format marker** — the header `v: 2`, whose presence declares that a
  note uses the layout of this RFC; a note without it uses the layout
  that preceded this RFC (format 1).

## Specification

### Evidence conventions

Evidence conventions are governed by draft-ndn-authoring-rfcs-00, section
"Evidence conventions" (the process BCP). For this RFC: every transcript
block provisions its own repository, and the sandbox git identity is
`conformance`, which is the value the tool records in `author` and
`assignee`. Generated identifiers and timestamps are projected away with
`cut`, `sed`, or `awk`; tabs are projected to `|` or a space where a line
would otherwise be unreadable, and one block asserts the raw tab count.

### The flag

`--porcelain` MUST be accepted both before and after the subcommand, on the
same terms as `--repo` in draft-ndn-multi-project-registry-02, and
`--porcelain=v1` MUST mean the same thing. [R-flag-position] Any other
version MUST be rejected with an error naming the supported versions and a
nonzero exit, so a consumer written against a future v2 fails loudly on an
old tool. [R-version-frozen] The v1 formats in this document are frozen at
publication; a change to any column, order, or framing is a new version,
never an edit to v1.

```transcript @R-flag-position
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" >/dev/null 2>&1
$ git issue --porcelain list | cut -f12
alpha task
$ git issue list --porcelain | cut -f12
alpha task
$ git issue list --porcelain=v1 | cut -f12
alpha task
```

```transcript @R-version-frozen
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue list --porcelain=v2
! Error: unsupported porcelain version 'v2' (supported: v1)
? 1
```

### Plain stdout

In porcelain mode, stdout MUST carry records and nothing else: no ANSI
styling, no headings, no `(none)` placeholders, no tips. An empty result
MUST produce empty stdout and exit 0. [R-plain-stdout] Informational
banners (repository detection, status compilation) are suppressed in
porcelain mode; errors remain on stderr and their wording is not part of
the contract.

```transcript @R-plain-stdout
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue list --porcelain | wc -c | tr -d ' '
0
$ git issue ready --porcelain | wc -c | tr -d ' '
0
$ git issue create "alpha task" >/dev/null 2>&1
$ git issue list --porcelain | grep -c "$(printf '\033')"
0
? 1
```

### Issue lines

`list`, `ready`, `queue`, and `topo` MUST emit one issue per line with
exactly twelve tab-separated columns in this order: `repo`, `id`,
`status`, `priority`, `assignee`, `role`, `updated`, `blocks`,
`depends_on`, `parent_of`, `relates_to`, `title`. An unset field is empty;
the four dependency fields are comma-joined ids with no spaces; `title` is
last because it is the only free-text column. [R-issue-line] `list` orders
by id; `ready` and `queue` keep their priority ordering; `topo` emits its
topological order, so line position carries the rank and no rank number
is printed. [R-issue-line-shared]

```transcript @R-issue-line
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" >/dev/null 2>&1
$ git issue list --porcelain | awk -F'\t' '{print NF}'
12
$ git issue list --porcelain | cut -f1,3-6,8-12 | tr '\t' '|'
|open|medium|conformance||||||alpha task
$ git issue create "beta task" >/dev/null 2>&1
$ a=$(git issue list --porcelain | awk -F'\t' '$12=="alpha task"{print $2}')
$ b=$(git issue list --porcelain | awk -F'\t' '$12=="beta task"{print $2}')
$ git issue dep add "$a" blocks "$b" >/dev/null 2>&1
$ git issue list --porcelain | awk -F'\t' -v a="$a" -v b="$b" '{ gsub(a,"A"); gsub(b,"B"); print $12 "|" $3 "|" $8 "|" $9 }' | sort
alpha task|open|B|
beta task|blocked||A
```

```transcript @R-issue-line-shared
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" >/dev/null 2>&1
$ git issue create "beta task" >/dev/null 2>&1
$ a=$(git issue list --porcelain | awk -F'\t' '$12=="alpha task"{print $2}')
$ b=$(git issue list --porcelain | awk -F'\t' '$12=="beta task"{print $2}')
$ git issue update "$b" --role=dev >/dev/null 2>&1
$ git issue dep add "$a" blocks "$b" >/dev/null 2>&1
$ git issue ready --porcelain | awk -F'\t' '{print NF, $12}'
12 alpha task
$ git issue queue dev --porcelain | awk -F'\t' '{print NF, $12}'
$ git issue topo --porcelain | awk -F'\t' '{print NF, $12}'
12 alpha task
12 beta task
```

### Aggregation

Under `--all`, the `repo` column MUST carry the registry name of the
repository each line came from, and the `[<name>] ` prefix of the human
format MUST NOT appear. Outside `--all` the column MUST be present and
empty, so one parser serves both cases. [R-all-column]

```transcript @R-all-column
$ git init -q a
$ cd a
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" >/dev/null 2>&1
$ cd ..
$ git issue repo add a /tmp/gi-rfc/a
Registered 'a' -> /tmp/gi-rfc/a
$ git issue list --all --porcelain 2>/dev/null | cut -f1,3,12 | tr '\t' '|'
a|open|alpha task
$ git issue --repo a list --porcelain | cut -f1,3,12 | tr '\t' '|'
|open|alpha task
```

### Edge lines

`deps` and `dep list` MUST emit one dependency edge per line as
`from`, `type`, `to`, tab-separated, one line per relationship recorded in
an issue's headers; a synchronized pair (`A blocks B` and `B depends_on A`)
therefore appears as two lines. `deps` with no id emits every edge;
`deps <id>` and `dep list <id>` emit the edges whose `from` is `<id>`.
`--dot` is unchanged. [R-edge-line]

```transcript @R-edge-line
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" >/dev/null 2>&1
$ git issue create "beta task" >/dev/null 2>&1
$ a=$(git issue list --porcelain | awk -F'\t' '$12=="alpha task"{print $2}')
$ b=$(git issue list --porcelain | awk -F'\t' '$12=="beta task"{print $2}')
$ git issue dep add "$a" blocks "$b" >/dev/null 2>&1
$ git issue deps --porcelain | awk -F'\t' -v a="$a" -v b="$b" '{ gsub(a,"A"); gsub(b,"B"); print }' | sort
A	blocks	B
B	depends_on	A
$ git issue dep list "$b" --porcelain | awk -F'\t' -v a="$a" -v b="$b" '{ gsub(a,"A"); gsub(b,"B"); print }'
B	depends_on	A
```

### Reference lines

`scan-commits` MUST emit one line per issue trailer found, as the full
commit hash, the trailer key in lowercase (`issue`, `fixes`, `closes`,
`related-to`), and the issue id, tab-separated. [R-ref-line]

```transcript @R-ref-line
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" >/dev/null 2>&1
$ a=$(git issue list --porcelain | cut -f2)
$ git commit -q --allow-empty -m "work" -m "Fixes: $a"
$ git issue scan-commits --porcelain | awk -F'\t' -v a="$a" '{print length($1), $2, ($3==a)}'
40 fixes 1
```

### Key-value lines

`setup-sync status` MUST emit `key`, `value` pairs, tab-separated, with
the keys `enabled`, `post-merge-hook`, `pre-push-hook`, `auto-fetch`
(each `true` or `false`) and `issue-notes` (a count), in that order.
[R-kv-line] `repo list` already has a contractual line format
(draft-ndn-multi-project-registry-02, requirement `R-list-missing`);
`--porcelain`
MUST be accepted there and MUST NOT change its output.

```transcript @R-kv-line
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" >/dev/null 2>&1
$ git issue setup-sync status --porcelain | tr '\t' ' '
enabled false
post-merge-hook false
pre-push-hook false
auto-fetch false
issue-notes 1
```

### Show

`show --porcelain` MUST emit a single header block: one `key: value` line
per known field that has a value, in the canonical field order of the
Formal Grammar, excluding the format marker (it describes the note's
encoding, not the issue), then `description`, then one `comment` line per comment in
stored order whose value is `[<timestamp>] <author>: <text>`. Any value
containing a newline MUST be emitted with each subsequent line as a
continuation line. No blank line, section heading, or decoration appears.
[R-show-block] A consumer reads the block with one rule: a line beginning
with a space continues the previous value.

```transcript @R-show-block
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" --description="$(printf 'first line\nsecond line')" >/dev/null 2>&1
$ a=$(git issue list --porcelain | cut -f2)
$ git issue comment "$a" "$(printf 'one\ntwo')" >/dev/null 2>&1
$ git issue show "$a" --porcelain | grep -vE '^(id|created|updated): ' | sed -E 's/^(comment: )\[[^]]+\]/\1[T]/'
title: alpha task
status: open
priority: medium
author: conformance
assignee: conformance
hash_source: content
description: first line
 second line
comment: [T] conformance: one
 two
```

### Storage: format marker and continuation at rest

A note written by this version MUST carry the format marker `v: 2` as the
second header line, immediately after `id:`, so the id-first invariant the
parsers rely on is untouched. Every write MUST emit format 2, including a
write that updates a note stored in format 1; the note is upgraded in
place, and its legacy comments are re-encoded under the rule of
[R-legacy-read]. [R-format-marker] The marker is the only signal a reader
uses to choose a layout; it never guesses from which headers are present.

```transcript @R-format-marker
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" >/dev/null 2>&1
$ a=$(git issue list --porcelain | cut -f2)
$ git cat-file -p "refs/notes/issue-$a:issue" | sed -n '2p'
v: 2
$ git cat-file -p "refs/notes/issue-$a:issue" | grep -c '^id:'
1
$ blob=$(printf 'id: abc1234\ntitle: legacy\nstatus: open\npriority: medium\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\nauthor: conformance\n\nold body\n' | git hash-object -w --stdin)
$ tree=$(printf '100644 blob %s\tissue\n' "$blob" | git mktree)
$ git update-ref refs/notes/issue-abc1234 "$(git commit-tree "$tree" -m legacy </dev/null)"
$ git issue update abc1234 --priority=high >/dev/null 2>&1
$ git cat-file -p refs/notes/issue-abc1234:issue | sed -n '2p'
v: 2
$ git cat-file -p refs/notes/issue-abc1234:issue | grep -c '^description: old body$'
1
```

In format 2, every write path MUST store a multi-line value with the same
continuation encoding: `description` is written as a header in the top
block with continuation lines, and a comment under `## Comments` is
written as its `[<timestamp>] <author>: <text>` line followed by
continuation lines. [R-store-continuation] A description line that begins
with `#` or matches a header key is therefore never mistaken for a section
marker or a header, because it is prefixed by the continuation space.

```transcript @R-store-continuation
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" --description="$(printf 'first line\n## Comments')" >/dev/null 2>&1
$ a=$(git issue list --porcelain | cut -f2)
$ git issue comment "$a" "$(printf 'one\ntwo')" >/dev/null 2>&1
$ git cat-file -p "refs/notes/issue-$a:issue" | grep -A1 '^description:'
description: first line
 ## Comments
$ git cat-file -p "refs/notes/issue-$a:issue" | sed -n '/^## Comments$/,$p' | sed -E 's/^\[[^]]+\]/[T]/'
## Comments
[T] conformance: one
 two
```

A note without the format marker MUST be read as format 1: the
description is the body region after the first blank line, and in the
`## Comments` section a line beginning with `[` starts a comment while any
other non-empty line continues the preceding comment verbatim.
[R-legacy-read] The one format-1 case that stays ambiguous is a raw
continuation line that itself begins with `[`; such a line reads as a new
comment, and no format-2 write can produce it.

```transcript @R-legacy-read
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ blob=$(printf 'id: abc1234\ntitle: legacy\nstatus: open\npriority: medium\ncreated: 2026-01-01T00:00:00Z\nupdated: 2026-01-01T00:00:00Z\nauthor: conformance\n\nold body\n\n## Comments\n[2026-01-01T00:00:00Z] conformance: one\ntwo\n' | git hash-object -w --stdin)
$ tree=$(printf '100644 blob %s\tissue\n' "$blob" | git mktree)
$ git update-ref refs/notes/issue-abc1234 "$(git commit-tree "$tree" -m legacy </dev/null)"
$ git issue show abc1234 --porcelain | sed -n '/^description/,$p'
description: old body
comment: [2026-01-01T00:00:00Z] conformance: one
 two
```

### Single-line fields

A tab, carriage return, or newline in a single-line field would break the
column contract, so write paths MUST replace each such character with one
space before storing, and porcelain issue lines MUST apply the same
replacement on read for notes written before this RFC. [R-field-normalize]

<!-- evidence: @R-field-normalize -->
| stored or given value      | emitted value    |
|----------------------------|------------------|
| `alpha task`               | `alpha task`     |
| `tab<HT>here`              | `tab here`       |
| `two<LF>lines`             | `two lines`      |
| `cr<CR>lf<LF>`             | `cr lf `         |
| (empty)                    | (empty)          |

```transcript @R-field-normalize
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "$(printf 'tab\there')" >/dev/null 2>&1
$ git issue list --porcelain | awk -F'\t' '{print NF, $12}'
12 tab here
$ a=$(git issue list --porcelain | cut -f2)
$ git issue update "$a" --assignee="$(printf 'two\nlines')" >/dev/null 2>&1
$ git issue list --porcelain | cut -f5
two lines
$ git cat-file -p "refs/notes/issue-$a:issue" | grep -c '^title: tab here$'
1
```

## Formal Grammar

```abnf
porcelain-flag = %s"--porcelain" [ "=" version ]
version        = %s"v1"

issue-line     = repo HTAB id HTAB status HTAB priority HTAB assignee
                 HTAB role HTAB updated HTAB ids HTAB ids HTAB ids
                 HTAB ids HTAB title LF
repo           = [ name ]
id             = name
ids            = [ id *( "," id ) ]
status         = field
priority       = field
assignee       = field
role           = field
title          = field
updated        = [ timestamp ]
timestamp      = 4DIGIT "-" 2DIGIT "-" 2DIGIT %s"T" 2DIGIT ":" 2DIGIT ":"
                 2DIGIT %s"Z"

edge-line      = id HTAB edge-type HTAB id LF
edge-type      = %s"blocks" / %s"depends_on" / %s"parent_of"
               / %s"relates_to"

ref-line       = commit HTAB trailer HTAB id LF
commit         = 40HEXDIG
trailer        = %s"issue" / %s"fixes" / %s"closes" / %s"related-to"

kv-line        = key HTAB field LF
key            = 1*( lower / DIGIT / "-" )

show-block     = 1*header
header         = hkey ":" SP field LF *continuation
continuation   = SP field LF
format-marker  = %s"v: 2" LF
hkey           = %s"id" / %s"title" / %s"status" / %s"priority"
               / %s"created" / %s"updated" / %s"author" / %s"assignee"
               / %s"role" / %s"labels" / %s"hash_source" / %s"github_id"
               / %s"github_url" / %s"jira_id" / %s"jira_url"
               / %s"gitlab_id" / %s"gitlab_url" / %s"blocks"
               / %s"depends_on" / %s"parent_of" / %s"relates_to"
               / %s"issue_type" / %s"external_ref" / %s"waits_for"
               / %s"description" / %s"comment"

name           = 1*( lower / DIGIT / "-" / "_" )
lower          = %x61-7A
field          = *field-char
field-char     = %x20-7E / %x80-10FFFF
```

The order of alternatives in `hkey` is the canonical field order for
`show`. `format-marker` is the second line of a stored format-2 note and
never appears in `show` output. `field-char` excludes HTAB, CR, and LF by construction; a value
holding those characters is either normalized ([R-field-normalize]) or
continued ([R-show-block]). Witnesses for `field` normalization are the
evidence table under Single-line fields.

## Alternatives Considered

### JSON output

A `--json` flag emitting one object per issue. Rejected for now: it means
a second serializer maintained in bash with its own escaping rules, and
shell consumers gain a dependency on `jq` where `cut` and `read` already
work. Nothing here precludes adding it later beside porcelain.

### `-z` NUL termination

Git's spelling for "the path may contain anything". Rejected in both
flavors. NUL-terminated records with tab-separated fields protect
nothing, since the hazard is a tab inside a field, not a newline between
records. NUL-separated fields do protect, but force a consumer to carry
two parsers. Forbidding tabs and newlines in single-line fields
([R-field-normalize]) closes the hazard with one rule and no flag.

### Length-prefixed sections

The `git cat-file --batch` framing: a byte count, then that many bytes.
Fully unambiguous, but the producer is bash, where `${#var}` counts
characters rather than bytes under a UTF-8 locale, so every length needs
`LC_ALL=C` care; and shell consumers cannot read it with line tools.
Continuation lines give the same unambiguity with none of that.

### Porcelain on `list`, `ready`, and `show` only

The minimum the first consumer needs. Rejected during the interview: a
buffer that renders dependencies or commit references would then parse
the human format for `deps` and `scan-commits`, which is the situation
this RFC exists to end.

### Keeping the description in the body region

Storing the description after the blank line as today, and applying
continuation only to comments. Rejected: the body region has two latent
ambiguities of its own (a body line equal to `## Comments`, and trailing
body lines that look like headers), and a description header with
continuation removes both while the reader keeps accepting the old
layout ([R-legacy-read]).

### Detecting the layout from the headers present

Reading a note as format 2 whenever it carries a `description` header,
with no marker. Rejected in review: a format-1 note with no description
and a format-2 note with no description are then indistinguishable, and
the comments rule would have to be chosen by a different heuristic again.
An explicit `v: 2` marker ([R-format-marker]) selects both rules at once,
costs four bytes, and is the convention git itself uses for on-disk
formats (`core.repositoryformatversion`, the index header version).

### `[<name>] ` prefix retained under `--all`

Zero new code. Rejected: the consumer would split the prefix off the first
column by regex, which is the human-format parsing porcelain replaces.

## Security Considerations

Porcelain mode is output-only and executes nothing new; it adds no trust
boundary. Two consequences of the format itself deserve care. First,
values are emitted verbatim apart from tab and newline normalization, so a
title or comment can carry terminal escape sequences into a consumer that
prints them raw; a consumer that renders porcelain into a terminal or a
buffer with escape interpretation should strip or quote control
characters, as it would for any git output. Second, the storage change
alters the bytes written into notes refs that may be pushed to shared
remotes ([R-store-continuation]); the encoding is plain text with no
executable content, and a reader that predates this RFC degrades to
showing the first line of a value rather than misbehaving.

## Compatibility

Without `--porcelain`, every read command's output is unchanged. Two
changes are observable regardless of the flag:

- Notes written after this RFC carry `v: 2` and store `description` as a
  header with continuation lines and no body region; a write to a
  format-1 note upgrades it ([R-format-marker]). The reader in this
  version accepts both layouts ([R-legacy-read]). A git-issue predating
  this RFC ignores the marker as an unknown header and reads such a note
  with an empty description, because its body region is empty; installs
  sharing notes over a remote should upgrade together.
- Single-line fields are normalized on write ([R-field-normalize]); a
  title containing a tab was previously stored as given.

Existing notes are not rewritten. Removing the feature would leave notes
in the header-description layout readable by any version carrying the
reader, and the porcelain flag would simply be rejected as unknown.

## References

- git-status(1), "Porcelain Format Version 1" and "Version 2" — the
  sense of "porcelain" and the versioning convention adopted here.
- git commit object format, `Documentation/gitformat-commit` — header
  continuation by leading space, the rule adopted for values at rest and
  in `show` output.
- RFC 5322, section 2.2.3 — folding of long header fields, the same idea
  in mail headers.
- draft-ndn-multi-project-registry-02 — `--repo`, `--all`, and the
  `repo list` line format this RFC leaves untouched.
- draft-ndn-authoring-rfcs-00 — evidence conventions and the process
  this document follows.
- BCP 14 (RFC 2119, RFC 8174); RFC 5234/7405 (ABNF).
