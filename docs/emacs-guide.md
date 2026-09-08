# git-issue in Emacs and Magit

git-issue ships an Emacs package in two layers. `git-issue.el` runs the
CLI and turns its machine-readable output into Lisp data; it needs
nothing but Emacs. `magit-git-issue.el` puts issues into magit: a section
in the status buffer, list and detail buffers, a transient for every
action, and commit trailers. This guide covers setup, a first session,
every key, and how to build on the core without magit.

For the command line itself, see the [user guide](user-guide.md). The
contract behind the package is
[`rfc/draft-ndn-magit-integration-00.md`](rfc/draft-ndn-magit-integration-00.md).

## Contents

1. [Requirements](#requirements)
2. [Setup](#setup)
3. [A first session](#a-first-session)
4. [The status buffer section](#the-status-buffer-section)
5. [List, ready, and detail buffers](#list-ready-and-detail-buffers)
6. [The transient](#the-transient)
7. [Composing text](#composing-text)
8. [Commits and trailers](#commits-and-trailers)
9. [Several repositories](#several-repositories)
10. [Customization](#customization)
11. [Using the core without magit](#using-the-core-without-magit)
12. [Troubleshooting](#troubleshooting)

## Requirements

- Emacs 28.1 or later.
- git-issue on your `PATH`, at a version with `--porcelain` (1.0.0 or
  later). The package runs the `git-issue` binary directly, not `git
  issue`, so `exec-path` must reach it.
- For the magit layer: magit 4.0 and transient 0.7 or later. Nothing
  else; with-editor is not used.
- git 2.32 or later for `git commit --trailer`, which the commit options
  rely on.

## Setup

The installer places both files in `<prefix>/share/git-issue/emacs`,
next to the awk and hook directories. Homebrew's prefix is
`/opt/homebrew` on Apple silicon and `/usr/local` on Intel; `make
install PREFIX=$HOME/.local` puts it under `~/.local/share`.

```elisp
(add-to-list 'load-path "/opt/homebrew/share/git-issue/emacs")
(require 'magit-git-issue)
```

With `use-package`:

```elisp
(use-package magit-git-issue
  :load-path "/opt/homebrew/share/git-issue/emacs"
  :after magit)
```

If `git-issue` is not the binary you want, or is not on `exec-path`:

```elisp
(setq git-issue-program "/path/to/git-issue")
```

Loading the file does two things you can undo: it adds
`magit-git-issue-insert-issues` to `magit-status-sections-hook` after the
stashes section, and binds `x` to the transient in `magit-dispatch` and
in the status buffer. `x` shadows `magit-reset-quickly` in the status
buffer; `X` still opens the reset transient. To move it:

```elisp
(define-key magit-status-mode-map (kbd "x") #'magit-reset-quickly)
(define-key magit-status-mode-map (kbd "M-i") #'magit-git-issue-dispatch)
```

and to drop the section:

```elisp
(remove-hook 'magit-status-sections-hook #'magit-git-issue-insert-issues)
```

## A first session

1. Open magit in a repository that has issues: `C-x g`.
2. Find the `Issues (ready)` section below the stashes. Each line is
   `<id> <status> <priority> <title>`.
3. Move point onto a line and press `RET`. A detail buffer opens with the
   headers, the description, and one section per comment. `g` refreshes
   it, `q` closes it.
4. Back in the status buffer, on an issue line, press `x`. The transient
   lists every action; press `s` to start the issue. The section
   refreshes and the status reads `in_progress`.
5. Press `x m` to comment. A buffer opens; write, then `C-c C-c`. Press
   `RET` on the issue to see the comment.
6. Stage a change and press `c c`. In the commit transient press `-x`,
   pick the issue with completion, and commit. `git log -1` shows the
   `Fixes: #<id>` trailer.

## The status buffer section

The section shows one of two lists, chosen by the user option
`magit-git-issue-status-section`:

- `ready` (the default): open issues with no open blockers, the same
  list as `git issue ready`. This is the actionable queue.
- `open`: every issue not closed, with blocked ones dimmed.

The section is collapsible with `TAB` like any magit section. If
git-issue fails or is missing, the section is omitted and a one-line
message says why; the rest of the status buffer is unaffected.

`RET` on a line opens the detail buffer. The transient and every action
in it act on the issue at point.

## List, ready, and detail buffers

- `M-x magit-git-issue-list` opens a buffer with every issue in the
  repository; `M-x magit-git-issue-ready` opens the ready queue. Both
  are also on the transient as `L` and `R`.
- `C-u` before either asks for `--all`: every registered repository,
  with each line prefixed by its repository name. `RET` on such a line
  opens the issue in its own repository, and later actions run there.
- The detail buffer (`magit-git-issue-show`) has a headers section, the
  description verbatim, and one section per comment headed by its
  timestamp and author. `g` refreshes it from the CLI. `x` opens the
  transient here too, acting on the shown issue.

All three are magit-mode buffers: `TAB` folds sections, `n`/`p` move
between them, `q` buries the buffer.

## The transient

`x` in the status buffer, a list buffer, a detail buffer, or from
`magit-dispatch`. Actions use the issue at point when there is one and
otherwise prompt for an id with completion over open issues.

| Key | Action | Prompts |
|---|---|---|
| `s` | Start (status `in_progress`) | |
| `c` | Close | |
| `o` | Reopen | |
| `m` | Comment | edit buffer |
| `l` | Link to commit | the commit at point, else a commit |
| `S` | Set status | completion over the repository's statuses |
| `p` | Set priority | `low` `medium` `high` `critical` |
| `a` | Set assignee | free text |
| `r` | Set role | free text |
| `d` | Add dependency edge | type, then target id |
| `D` | Remove dependency edge | type, then target id |
| `n` | New issue | title, then an edit buffer for the description |
| `L` | List buffer | |
| `R` | Ready buffer | |
| `RET` | Show an issue | id |

Every action refreshes the current buffer on success. On failure the
CLI's own error text is shown in the echo area, without color codes.

## Composing text

Comments and new-issue descriptions are written in a dedicated buffer
that follows the conventions of magit's commit message buffer:

- `C-c C-c` sends the text and closes the buffer.
- `C-c C-k` aborts and closes the buffer.
- For a new issue, an empty description is skipped rather than stored.

If the CLI rejects the submission, the error is shown and the buffer
stays open with your text in it, so you can fix and press `C-c C-c`
again. Each composition gets its own buffer; starting a second comment
does not disturb the first.

## Commits and trailers

The commit transient (`c c`) gains three options:

| Key | Option | Trailer written |
|---|---|---|
| `-x` | `--fixes=<id>` | `Fixes: #<id>` |
| `-X` | `--closes=<id>` | `Closes: #<id>` |
| `-i` | `--issue=<id>` | `Issue: #<id>` |

Each reads an id with completion and is passed to git as `--trailer`, so
the line lands in the message as git writes it and `git issue
scan-commits` finds it afterward. Inside a commit message buffer, `C-c
C-x` runs `git-issue-insert-trailer`, which prompts for the kind and id
and inserts the line at the end of the message.

## Several repositories

Register repositories once from the command line:

```bash
git issue repo add tracker ~/src/git-issue-tracker
git issue repo add api ~/src/api
```

Then `C-u M-x magit-git-issue-ready` shows the ready work of every
registered repository in one buffer, and `RET` on a line takes you into
that repository. The status section stays per-repository.

## Customization

`M-x customize-group RET magit-git-issue`:

- `magit-git-issue-status-section`: `ready` or `open`.
- `magit-git-issue-statuses`, `magit-git-issue-priorities`, and
  `magit-git-issue-dependency-types`: the completion candidates offered
  when setting a status or priority or adding an edge. The statuses
  default to git-issue's standard six; edit them if a repository uses a
  different vocabulary.
- Faces `magit-git-issue-id`, `magit-git-issue-blocked`, and
  `magit-git-issue-repo`.

And in the `git-issue` group, `git-issue-program`.

## Using the core without magit

`(require 'git-issue)` alone gives you the data layer:

```elisp
(let ((default-directory "~/src/api/"))
  (dolist (i (git-issue-ready))
    (message "%s %s" (git-issue-issue-id i) (git-issue-issue-title i))))

(git-issue-detail-description (git-issue-show "a064d35"))
(git-issue-create "Title" "Optional\nmulti-line description")   ; returns the id
(git-issue-comment "a064d35" "Text")
(git-issue-format-trailer "fixes" "a064d35")                    ; "Fixes: #a064d35"
```

Every function runs `git-issue --porcelain` in `default-directory` and
signals `git-issue-error` with the CLI's message as plain text when the
command fails. Issue lines become `git-issue-issue` structs with an
accessor per column; `show` becomes a `git-issue-detail` with `fields`,
`description`, and `comments` as `(timestamp author text)`. The
functions and their names are a contract, specified in the RFC linked
above, so an org-mode agenda or a project sidebar can build on them
without magit.

## Troubleshooting

**No Issues section in the status buffer.** Either the repository has
no ready issues (switch `magit-git-issue-status-section` to `open` to
check), or git-issue could not run; look in `*Messages*` for a line
starting `git-issue:`.

**`git-issue: cannot run git-issue`.** The binary is not on
`exec-path`, or `git-issue-program` points somewhere wrong. Evaluate
`(executable-find git-issue-program)`.

**Columns look wrong or parsing errors mention 12 columns.** The
installed git-issue predates `--porcelain`. Upgrade it, or point
`git-issue-program` at a newer checkout's `bin/git-issue`.

**`x` does something else.** Another package bound it after this one
loaded; rebind as shown in Setup, or use `magit-dispatch` (`?` in the
status buffer) and press `x` there.

**A backtrace.** `M-x toggle-debug-on-error`, repeat the action, and
include the backtrace when reporting.
