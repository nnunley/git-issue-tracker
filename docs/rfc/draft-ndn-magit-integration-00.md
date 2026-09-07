# draft-ndn-magit-integration-00: Emacs and Magit Integration for git-issue

**Status:** DRAFT
**Corpus:** green
**Category:** Standards-Track
**Authors:** Norman Nunley, Jr <nnunley@gmail.com>, Claude (drafting agent)

## Abstract

This RFC specifies an Emacs package for git-issue in two layers: a
magit-free core (`git-issue.el`) that runs the CLI in porcelain mode and
parses its output into Lisp data, and a magit user interface
(`magit-git-issue.el`) that adds an issues section to the status buffer,
list and detail buffers, a transient for every issue action, commit
trailers, and a cross-repository list. The core's functions are the
contract; the interface is specified normatively and checked by a test
suite. One small CLI addition, `create --porcelain`, gives the core a
parseable id.

## Motivation

git-issue keeps issues in the repository, so the natural place to read and
resolve them is the place where the repository is already open: magit.
Today that means leaving Emacs for a shell, reading colored output, and
typing ids back by hand. Closing an issue and referencing it in the commit
that fixes it are one motion in the head and three tools on the desk.

draft-ndn-porcelain-output-00 removed the parsing obstacle: every read
command now has a stable machine format. What remains is the Emacs side,
and it is worth a contract of its own because the parsing layer is useful
to any Elisp, not only magit, and because a second consumer (an org-mode
agenda, a project sidebar) should not have to reimplement it.

## Terminology

The key words "MUST", "MUST NOT", "REQUIRED", "SHALL", "SHALL NOT", "SHOULD",
"SHOULD NOT", "RECOMMENDED", "NOT RECOMMENDED", "MAY", and "OPTIONAL" in this
document are to be interpreted as described in BCP 14 (RFC 2119, RFC 8174)
when, and only when, they appear in all capitals, as shown here.

- **core** — `git-issue.el`: process invocation, parsing, and one function
  per CLI command; loads without magit.
- **UI** — `magit-git-issue.el`: everything that needs magit, transient, or
  with-editor.
- **issue struct** — the Lisp value the core returns for one porcelain
  issue line (`git-issue-issue`).
- **detail struct** — the Lisp value for one `show --porcelain` block
  (`git-issue-detail`).
- **Elisp directory** — where the installer places the two files:
  `<prefix>/share/git-issue/emacs`, beside the awk and hook directories.

## Specification

### Evidence conventions

Evidence conventions are governed by draft-ndn-authoring-rfcs-00, section
"Evidence conventions" (the process BCP). For this RFC: transcripts run
`emacs -Q --batch` with the Elisp directory on the load path, derived from
the installed binary exactly as the install-layout requirement below
states; the sandbox git identity is `conformance`. Emacs is on `PATH` for
the corpus (the conformance job installs it); magit is not, and the core
transcripts prove they do not need it. Generated ids and timestamps are
projected away with `cut`, `sed`, or `grep -c`.

### Install layout

The installer MUST place `git-issue.el` and `magit-git-issue.el` in
`<prefix>/share/git-issue/emacs`, where `<prefix>/bin` holds the
`git-issue` binary after symlinks are resolved, and `git-issue.el` MUST
load in a batch Emacs with no packages beyond Emacs itself. [R-core-loads]
The transcripts derive the directory with one expression, which is the
form a user's `load-path` configuration would use:

```transcript @R-core-loads
$ EL="$(dirname "$(dirname "$(readlink -f "$(command -v git-issue)")")")/share/git-issue/emacs"
$ test -f "$EL/git-issue.el"
$ test -f "$EL/magit-git-issue.el"
$ emacs -Q --batch -L "$EL" -l git-issue --eval '(princ (list (featurep (quote git-issue)) (featurep (quote magit))))'
(t nil)
```

### The create id

`create` MUST accept `--porcelain` and, in porcelain mode, MUST print the
new issue's id alone on stdout, followed by a newline, and nothing else.
[R-create-porcelain] This is the only write command with a porcelain form;
the core needs the id to return it, and the human line is not a contract.

```transcript @R-create-porcelain
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" --porcelain | grep -cE '^[0-9a-f]{7}$'
1
$ git issue create "beta task" --porcelain | wc -l | tr -d ' '
1
$ git issue list --porcelain | cut -f12 | sort
alpha task
beta task
```

### Running the CLI

`git-issue-run` MUST execute the program named by the user option
`git-issue-program` (default `git-issue`) with `--porcelain` followed by
its arguments, in `default-directory`, and return stdout as a string. A
nonzero exit MUST signal the error condition `git-issue-error` whose data
is the process's stderr, so callers see the CLI's own message.
[R-run-and-error]

```transcript @R-run-and-error
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" >/dev/null 2>&1
$ EL="$(dirname "$(dirname "$(readlink -f "$(command -v git-issue)")")")/share/git-issue/emacs"
$ emacs -Q --batch -L "$EL" -l git-issue --eval '(let ((default-directory "/tmp/gi-rfc/proj/")) (princ (git-issue-run "list")))' | cut -f12
alpha task
$ emacs -Q --batch -L "$EL" -l git-issue --eval '(let ((default-directory "/tmp/gi-rfc/proj/")) (condition-case e (git-issue-run "show" "nosuch") (git-issue-error (princ (cadr e)))))' | grep -c "not found"
1
```

### Parsing

The core MUST parse porcelain issue lines into `git-issue-issue` structs
with accessors named for the twelve columns of
draft-ndn-porcelain-output-00 (`repo`, `id`, `status`, `priority`,
`assignee`, `role`, `updated`, `blocks`, `depends-on`, `parent-of`,
`relates-to`, `title`); the four dependency fields are lists of ids, empty
when the column is empty; an empty `repo` column is `nil`. [R-parse-issue]
It MUST parse edge lines into `(from type to)` lists, reference lines into
`(commit trailer id)` lists, and key-value lines into an alist of
`(key . value)` with string keys. [R-parse-lines]

```transcript @R-parse-issue
$ EL="$(dirname "$(dirname "$(readlink -f "$(command -v git-issue)")")")/share/git-issue/emacs"
$ emacs -Q --batch -L "$EL" -l git-issue --eval '(let ((i (git-issue-parse-issue-line "\ta1b2c3d\tblocked\thigh\tconformance\tdev\t2026-01-01T00:00:00Z\t\tb2c3d4e,c3d4e5f\t\t\talpha task"))) (princ (list (git-issue-issue-repo i) (git-issue-issue-id i) (git-issue-issue-status i) (git-issue-issue-priority i) (git-issue-issue-role i) (git-issue-issue-blocks i) (git-issue-issue-depends-on i) (git-issue-issue-title i))))'
(nil a1b2c3d blocked high dev nil (b2c3d4e c3d4e5f) alpha task)
$ emacs -Q --batch -L "$EL" -l git-issue --eval '(princ (git-issue-issue-repo (git-issue-parse-issue-line "tracker\ta1b2c3d\topen\tmedium\t\t\t\t\t\t\t\tx")))'
tracker
```

```transcript @R-parse-lines
$ EL="$(dirname "$(dirname "$(readlink -f "$(command -v git-issue)")")")/share/git-issue/emacs"
$ emacs -Q --batch -L "$EL" -l git-issue --eval '(princ (git-issue-parse-edge-lines "a1b2c3d\tblocks\tb2c3d4e\nb2c3d4e\tdepends_on\ta1b2c3d\n"))'
((a1b2c3d blocks b2c3d4e) (b2c3d4e depends_on a1b2c3d))
$ emacs -Q --batch -L "$EL" -l git-issue --eval '(princ (git-issue-parse-reference-lines "0123456789012345678901234567890123456789\tfixes\ta1b2c3d\n"))'
((0123456789012345678901234567890123456789 fixes a1b2c3d))
$ emacs -Q --batch -L "$EL" -l git-issue --eval '(princ (git-issue-parse-kv-lines "enabled\ttrue\nissue-notes\t3\n"))'
((enabled . true) (issue-notes . 3))
```

The core MUST parse a `show --porcelain` block into a `git-issue-detail`
struct: an alist of the single-line fields, a `description` string with
continuation lines unfolded (joined by newline, leading space removed), and
`comments` as a list of `(timestamp author text)` lists in stored order,
each text unfolded the same way. [R-parse-detail]

```transcript @R-parse-detail
$ EL="$(dirname "$(dirname "$(readlink -f "$(command -v git-issue)")")")/share/git-issue/emacs"
$ emacs -Q --batch -L "$EL" -l git-issue --eval '(let ((d (git-issue-parse-detail "id: a1b2c3d\ntitle: alpha task\nstatus: open\ndescription: first line\n second line\ncomment: [2026-01-01T00:00:00Z] conformance: one\n two\ncomment: [2026-01-02T00:00:00Z] conformance: three\n"))) (princ (list (cdr (assoc "title" (git-issue-detail-fields d))) (git-issue-detail-description d) (git-issue-detail-comments d))))'
(alpha task first line
second line ((2026-01-01T00:00:00Z conformance one
two) (2026-01-02T00:00:00Z conformance three)))
```

### Commands

The core MUST provide one function per CLI command, each running through
`git-issue-run` and returning parsed data: `git-issue-list`,
`git-issue-ready` (both taking an `all` argument, which when non-nil adds
`--all`), `git-issue-show`, `git-issue-deps`, `git-issue-create` (title,
and a description that MAY be omitted; returns the new id), `git-issue-start`,
`git-issue-close`, `git-issue-reopen`, `git-issue-comment`,
`git-issue-update` (id, field, value), `git-issue-dep-add`,
`git-issue-dep-rm`, and `git-issue-link`. `git-issue-open-ids` MUST return
the ids of issues whose status is not `closed`, for completion.
[R-commands]

```transcript @R-commands
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ EL="$(dirname "$(dirname "$(readlink -f "$(command -v git-issue)")")")/share/git-issue/emacs"
$ emacs -Q --batch -L "$EL" -l git-issue --eval '(let* ((default-directory "/tmp/gi-rfc/proj/") (a (git-issue-create "alpha task" "first line\nsecond line")) (b (git-issue-create "beta task"))) (git-issue-dep-add a "blocks" b) (git-issue-comment a "one\ntwo") (git-issue-close b) (princ (list (length (git-issue-open-ids)) (git-issue-issue-status (car (git-issue-ready))) (git-issue-detail-description (git-issue-show a)) (length (git-issue-detail-comments (git-issue-show a))))))' 2>/dev/null
(1 open first line
second line 1)
$ git issue list --porcelain | awk -F'\t' '$12=="beta task"{print $3}'
closed
```

### Trailers

`git-issue-format-trailer` MUST return `<Key>: #<id>` for the kinds
`issue`, `fixes`, `closes`, and `related-to`, with the key spelled as
git-issue's `commit` subcommand writes it (`Issue`, `Fixes`, `Closes`,
`Related-To`), and `git-issue-trailer-args` MUST return the argument list
that passes such a trailer to `git commit` (`--trailer` followed by the
line), so both the transient option and the message-buffer command produce
what `scan-commits` recognizes. [R-trailer]

```transcript @R-trailer
$ EL="$(dirname "$(dirname "$(readlink -f "$(command -v git-issue)")")")/share/git-issue/emacs"
$ emacs -Q --batch -L "$EL" -l git-issue --eval '(princ (list (git-issue-format-trailer "fixes" "a1b2c3d") (git-issue-format-trailer "related-to" "a1b2c3d") (git-issue-trailer-args "closes" "a1b2c3d")))'
(Fixes: #a1b2c3d Related-To: #a1b2c3d (--trailer Closes: #a1b2c3d))
$ git init -q proj
$ cd proj
$ git commit -q --allow-empty -m init
$ git issue create "alpha task" >/dev/null 2>&1
$ a=$(git issue list --porcelain | cut -f2)
$ git commit -q --allow-empty -m work --trailer "Fixes: #$a"
$ git issue scan-commits --porcelain | cut -f2
fixes
$ test "$(git issue scan-commits --porcelain | cut -f3)" = "$a"
```

The witness is that the trailer the core formats is the trailer the CLI
scans back; the id is compared inside the shell because generated ids are
projected out of expected output.

### Magit user interface (normative, suite-checked)

The following requirements are normative but are checked by the ERT suite
under `contrib/emacs/test/`, run in the repository's test job with magit
installed, rather than by the corpus: they need a live magit and transient,
which the conformance sandbox does not provide.

- `magit-git-issue.el` MUST require `git-issue`, `magit`, `transient`, and
  `with-editor`, and MUST NOT duplicate any parsing or process code from
  the core.
- Loading it MUST add `magit-git-issue-insert-issues` to
  `magit-status-sections-hook` (after the stashes section) and bind `x`
  to `magit-git-issue-dispatch` in `magit-dispatch` and
  `magit-status-mode-map`. Both are done through `magit-add-section-hook`
  and `transient-append-suffix`, so a user can remove or rebind them.
- The status section MUST show the issues selected by the user option
  `magit-git-issue-status-section`, one of `ready` (default) or `open`,
  one line per issue in the form `<id> <status> <priority> <title>`, with
  the section collapsible and each line a `magit-section` of type
  `git-issue` whose value is the issue struct, so `RET` and the transient
  see the issue at point.
- `magit-git-issue-list` MUST open a `magit-mode`-derived buffer listing
  `list --porcelain`; `magit-git-issue-ready` the same for `ready`; both
  accept a prefix argument meaning `--all`, in which case lines are
  prefixed with the repo name and `RET` visits the issue with
  `default-directory` set to that repository's registered path.
- `RET` on an issue line MUST open `magit-git-issue-show`, a
  `magit-mode`-derived buffer rendering the detail struct: the fields as a
  headers section, the description verbatim, and the comments as one
  section each. `g` refreshes from the CLI.
- `magit-git-issue-dispatch` MUST offer, acting on the issue at point when
  there is one and prompting for an id with `git-issue-read-id` otherwise:
  create (title in the minibuffer, then a `with-editor` buffer for the
  description, `C-c C-c` to finish, `C-c C-k` to abort, empty description
  skipped), start, close, reopen, comment (a `with-editor` buffer), set
  status, set priority, set assignee, set role (minibuffer with
  completion where the CLI has a fixed vocabulary), dep add, dep rm
  (prompting for type and target id with completion), link to the commit
  at point (or a commit read with `magit-read-branch-or-commit`), and
  open the list and ready buffers. Every action refreshes the current
  magit buffer on success and displays the `git-issue-error` data on
  failure.
- The commit transient MUST gain three options `--fixes=`, `--closes=`,
  and `--issue=`, each reading an id with completion over
  `git-issue-open-ids`, and `magit-commit` MUST pass
  `git-issue-trailer-args` for each set option so the trailer lands in
  the message. `git-issue-insert-trailer` MUST be an interactive command
  available in `git-commit-mode` that inserts a trailer line at the end of
  the message after prompting for kind and id.

## Formal Grammar

```abnf
trailer-line = trailer-key ": #" id LF
trailer-key  = %s"Issue" / %s"Fixes" / %s"Closes" / %s"Related-To"
trailer-kind = %s"issue" / %s"fixes" / %s"closes" / %s"related-to"
id           = 1*( lower / DIGIT / "-" / "_" )
lower        = %x61-7A
```

`trailer-kind` is the argument the core accepts; `trailer-line` is what it
produces and what `scan-commits` recognizes. Witnesses are the `@R-trailer`
transcript.

## Alternatives Considered

### A forge backend

Forge already has topic lists, topic buffers, and comment threads. Its
data model assumes a remote host with numbered topics, users, and
notifications, and a local SQL cache of them; git-issue has none of those.
Making it fit would mean fighting the abstraction at every seam, and forge
upstream has declined local backends. Rejected.

### One file

A single `magit-git-issue.el` with the parser inside. Rejected: the parser
is the part any other Elisp consumer wants, and the corpus can only prove
what loads without magit. The split costs one `require`.

### Parsing the human output

Rejected on arrival; draft-ndn-porcelain-output-00 exists so that no
consumer does this again.

### A separate repository

What MELPA and most magit extensions expect. Rejected for now, per the
interview: the porcelain format and its first consumer change together,
and extraction to its own repository is cheap once the format is
published.

### Trailers via `git issue commit --fixes` after the fact

Rewrites the commit with git-issue's own command. Rejected: amending after
magit has committed surprises the user and loses the one-motion property;
git's `--trailer` puts the line in the message as it is written.

### Deriving the create id from `list` before and after

Avoids touching the CLI. Rejected: racy under concurrent writers and
fragile under hash collision retry; a one-line porcelain form for `create`
is the honest fix.

## Security Considerations

The core executes `git-issue` found on `exec-path` in the current
`default-directory`, and the cross-repository list sets
`default-directory` to paths from the registry. It therefore inherits the
trust boundary stated in draft-ndn-multi-project-registry-02: entering a
registered repository runs that repository's git configuration and hooks.
The package adds no new privilege, and never invokes a shell: arguments
are passed as a list to `call-process`, so a title or comment containing
shell metacharacters is data. Porcelain output is inserted into buffers as
text with properties and never evaluated; the porcelain contract strips
terminal styling, so no escape sequences reach a buffer. `with-editor`
buffers for comments and descriptions send their contents as an argument,
not through a temporary file the user could be induced to edit.

## References

- draft-ndn-porcelain-output-00 — the formats the core parses, and the
  contract this RFC extends with `create --porcelain`.
- draft-ndn-multi-project-registry-02 — `--all` and the trust boundary of
  registered paths.
- draft-ndn-authoring-rfcs-00 — evidence conventions and process.
- Magit manual, "Sections" and "Transient Commands"; transient manual;
  with-editor — the extension points used.
- git-commit(1), `--trailer` (git 2.32 and later).
- BCP 14 (RFC 2119, RFC 8174); RFC 5234/7405 (ABNF).
