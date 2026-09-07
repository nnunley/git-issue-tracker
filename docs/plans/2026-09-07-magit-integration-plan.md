# Magit Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement draft-ndn-magit-integration-00: a magit-free Elisp core proven by the RFC corpus, a magit UI checked by ERT, and the one CLI addition (`create --porcelain`).

**Architecture:** Two files under `contrib/emacs/`. `git-issue.el` runs `git-issue --porcelain` with `call-process`, parses every porcelain shape into structs and lists, and exposes one function per CLI command plus trailer helpers. `magit-git-issue.el` builds on it with a status section, `magit-mode` list/detail buffers, a transient on `x`, with-editor buffers for multi-line text, commit-transient options passing `--trailer`, and a cross-repo prefix argument. Installers ship both files to `share/git-issue/emacs`. The core's ERT tests and the corpus need only Emacs; the UI's ERT tests install magit from NonGNU ELPA into a scratch directory in CI.

**Tech Stack:** Emacs Lisp (Emacs 28.1 floor, lexical binding, cl-lib, ERT), magit 4.x, transient 0.7+, with-editor; bash for the CLI change; GitHub Actions.

**Spec:** `docs/rfc/draft-ndn-magit-integration-00.md` (binding). Also `docs/rfc/draft-ndn-porcelain-output-00.md` for the formats the core parses. Read the spec's transcripts before each task; they are the acceptance tests.

## Global Constraints

- Every corpus requirement: `[R-core-loads]` `[R-create-porcelain]` `[R-run-and-error]` `[R-parse-issue]` `[R-parse-lines]` `[R-parse-detail]` `[R-commands]` `[R-trailer]`. Their transcripts run `emacs -Q --batch -L "$EL" -l git-issue` with `EL="$(dirname "$(dirname "$(readlink -f "$(command -v git-issue)")")")/share/git-issue/emacs"`.
- `git-issue.el` MUST load with no packages beyond Emacs; `(featurep 'magit)` is nil after loading it.
- Function and struct names are the contract; use exactly the names in the spec: `git-issue-program`, `git-issue-run`, `git-issue-error`, `git-issue-issue` (accessors `git-issue-issue-repo` … `-title`, with `depends-on`, `parent-of`, `relates-to` hyphenated), `git-issue-parse-issue-line`, `git-issue-parse-issue-lines`, `git-issue-parse-edge-lines`, `git-issue-parse-reference-lines`, `git-issue-parse-kv-lines`, `git-issue-parse-detail`, `git-issue-detail` (accessors `-fields`, `-description`, `-comments`), `git-issue-list`, `git-issue-ready`, `git-issue-show`, `git-issue-deps`, `git-issue-create`, `git-issue-start`, `git-issue-close`, `git-issue-reopen`, `git-issue-comment`, `git-issue-update`, `git-issue-dep-add`, `git-issue-dep-rm`, `git-issue-link`, `git-issue-open-ids`, `git-issue-read-id`, `git-issue-format-trailer`, `git-issue-trailer-args`.
- UI names: `magit-git-issue-insert-issues`, `magit-git-issue-status-section` (`ready` | `open`, default `ready`), `magit-git-issue-dispatch` on `x`, `magit-git-issue-list`, `magit-git-issue-ready`, `magit-git-issue-show`, section type `git-issue`, commit options `--fixes=` `--closes=` `--issue=`, `git-issue-insert-trailer`.
- Trailer keys: `Issue`, `Fixes`, `Closes`, `Related-To`; line form `<Key>: #<id>`.
- Human output of `bin/git-issue` MUST NOT change except `create --porcelain`. `make test-all` is the oracle.
- No Claude attribution in commits. Bash 3.2 for shell; `lexical-binding: t` for Elisp; no external Elisp dependencies in the core.
- Verification commands:

```bash
# Corpus for this RFC (declared red until Task 9):
PATH="$PWD/bin:$PATH" ~/.claude/skills/authoring-rfcs/rfc-run docs/rfc/draft-ndn-magit-integration-00.md 2>&1 | grep -E '^(PASS|FAIL)'
# Whole gate:
PATH="$PWD/bin:$PATH" ~/.claude/skills/authoring-rfcs/rfc-check docs/rfc
# Core ERT (no magit):
emacs -Q --batch -L contrib/emacs -l ert -l contrib/emacs/test/git-issue-test.el -f ert-run-tests-batch-and-exit
# UI ERT (magit required; Task 8 adds the runner script):
contrib/emacs/test/run-ui-tests.sh
```

Locally, `readlink -f` and `emacs` exist (`/opt/homebrew/bin/emacs`). For the corpus to find the Elisp under `PATH="$PWD/bin:$PATH"`, the repo layout must mirror the install layout: Task 2 makes `share/git-issue/emacs` a real directory in the repo (the source of truth), with `contrib/emacs` holding only the tests. See Task 2 for the ruling.

---

## File map

| File | Responsibility |
|---|---|
| `share/git-issue/emacs/git-issue.el` | core: process, parsing, commands, trailers (source of truth, installed verbatim) |
| `share/git-issue/emacs/magit-git-issue.el` | magit UI |
| `contrib/emacs/test/git-issue-test.el` | core ERT (Emacs only) |
| `contrib/emacs/test/magit-git-issue-test.el` | UI ERT (magit) |
| `contrib/emacs/test/run-ui-tests.sh` | installs magit into a scratch dir, runs UI ERT |
| `bin/git-issue` | `create --porcelain` |
| `Makefile`, `install-git-issue.sh`, `Formula/git-issue.rb`, `git-issue-local.rb`, `tests/test_install_layout.sh` | ship and verify the emacs dir |
| `.github/workflows/test.yml` | Emacs in the conformance job; core and UI ERT in the test job |
| `README.md`, `man/man1/git-issue.1` | document the package |
| `docs/rfc/draft-ndn-magit-integration-00.md` | corpus flips green in Task 9 |

---

### Task 1: `create --porcelain`

**Files:**
- Modify: `bin/git-issue` (`create_issue`, around the `✓ Created issue` echo; the legacy `add` arm in `main` likewise)
- Test: `tests/test_porcelain.sh`

**Interfaces:**
- Produces: in porcelain mode, `create` prints only `<id>\n` on stdout.

- [ ] **Step 1: Failing test**

Append to `tests/test_porcelain.sh` before the final summary lines:

```bash
echo "Testing create --porcelain [R-create-porcelain]"
fresh_repo createp
out=$("$GI" create "alpha task" --porcelain 2>/dev/null)
eq "create prints the id alone" "1" "$(printf '%s\n' "$out" | grep -cE '^[0-9a-f]{7}$')"
eq "create prints one line" "1" "$(printf '%s\n' "$out" | wc -l | tr -d ' ')"
eq "created issue is listed" "alpha task" "$("$GI" list --porcelain | awk -F'\t' -v id="$out" '$2==id{print $12}')"
eq "create with description works in porcelain" "1" "$("$GI" create "beta" --description="$(printf 'l1\nl2')" --porcelain 2>/dev/null | grep -cE '^[0-9a-f]{7}$')"
eq "human create output unchanged" "1" "$("$GI" create "gamma" 2>/dev/null | grep -c 'Created issue #')"
```

- [ ] **Step 2: Run, expect failure**

`./tests/test_porcelain.sh` — the "prints the id alone" assertion fails (colored lines).

- [ ] **Step 3: Implement**

In `create_issue`, replace the two informational echoes (`Creating issue with hash ID` and the two lines after `write_issue_data`) with:

```bash
    if [[ -n "${GIT_ISSUE_PORCELAIN:-}" ]]; then
        : # records only
    else
        echo -e "${BLUE}Creating issue with hash ID: $id${NC}"
    fi
    ...
    write_issue_data "$id" "$issue_data"
    if [[ -n "${GIT_ISSUE_PORCELAIN:-}" ]]; then
        printf '%s\n' "$id"
    else
        echo -e "${GREEN}✓ Created issue #$id: $title${NC}"
        echo -e "${GRAY}   Use this ID for future operations: $id${NC}"
    fi
```

Keep the existing flow; only the output is gated. Do the same for the legacy `add` arm's `✓ Created issue` echo. Check whether `create` parses its flags after the title (`--description=`); `--porcelain` is already peeled by `_gi_dispatch`, so no flag parsing changes are needed.

- [ ] **Step 4: Verify**

`./tests/test_porcelain.sh && make test-all`; corpus listing: `create-porcelain` PASS.

- [ ] **Step 5: Commit**

```bash
git add bin/git-issue tests/test_porcelain.sh
git commit -m "feat(porcelain): create prints the new id alone

The only write command with a porcelain form: the Emacs core needs the
id back and the colored line is not a contract. Covers R-create-porcelain
of draft-ndn-magit-integration-00."
```

---

### Task 2: Core skeleton, install layout, and the process runner

**Files:**
- Create: `share/git-issue/emacs/git-issue.el`, `share/git-issue/emacs/magit-git-issue.el` (stub that only `(require 'git-issue)` and provides its feature; filled in Task 6)
- Create: `contrib/emacs/test/git-issue-test.el`
- Modify: `Makefile` (install target and a `test-emacs-core` target), `install-git-issue.sh`, `Formula/git-issue.rb`, `git-issue-local.rb`, `tests/test_install_layout.sh`

**Ruling recorded here:** the interview placed the package under `contrib/emacs/`. The corpus transcripts locate the Elisp relative to the binary at `share/git-issue/emacs`, and the repo runs the corpus with `PATH="$PWD/bin:$PATH"`, so the repo layout must match the install layout. The source therefore lives in `share/git-issue/emacs/` (like the awk programs), and `contrib/emacs/` holds the tests and the UI test runner. Cost if wrong: a `git mv` later.

**Interfaces:**
- Produces: `git-issue-program`, `git-issue-error`, `git-issue-run`.

- [ ] **Step 1: Failing core ERT test**

Create `contrib/emacs/test/git-issue-test.el`:

```elisp
;;; git-issue-test.el --- ERT for the git-issue core  -*- lexical-binding: t; -*-
(require 'ert)
(require 'git-issue)

(defun git-issue-test--scratch-repo ()
  "Create a git repository with one commit; return its directory (trailing slash)."
  (let ((dir (file-name-as-directory (make-temp-file "git-issue-test" t))))
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q")
      (call-process "git" nil nil nil "config" "user.name" "conformance")
      (call-process "git" nil nil nil "config" "user.email" "conformance@rfc")
      (call-process "git" nil nil nil "commit" "-q" "--allow-empty" "-m" "init"))
    dir))

(ert-deftest git-issue-run-returns-stdout ()
  (let ((default-directory (git-issue-test--scratch-repo)))
    (should (equal (git-issue-run "list") ""))))

(ert-deftest git-issue-run-signals-with-stderr ()
  (let ((default-directory (git-issue-test--scratch-repo)))
    (let ((err (should-error (git-issue-run "show" "nosuch") :type 'git-issue-error)))
      (should (string-match-p "not found" (cadr err))))))

(ert-deftest git-issue-core-does-not-load-magit ()
  (should-not (featurep 'magit)))

(provide 'git-issue-test)
;;; git-issue-test.el ends here
```

Run: `PATH="$PWD/bin:$PATH" emacs -Q --batch -L share/git-issue/emacs -l ert -l contrib/emacs/test/git-issue-test.el -f ert-run-tests-batch-and-exit`
Expected: fails to load `git-issue` (file missing).

- [ ] **Step 2: Create the core file**

Create `share/git-issue/emacs/git-issue.el`:

```elisp
;;; git-issue.el --- Core for git-issue: run the CLI, parse porcelain  -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1"))
;; Keywords: tools, vc

;;; Commentary:
;; The magit-free layer specified by draft-ndn-magit-integration-00.
;; Runs `git-issue --porcelain', parses every porcelain shape of
;; draft-ndn-porcelain-output-00 into Lisp data, and offers one function
;; per CLI command.  Nothing here requires magit.

;;; Code:

(require 'cl-lib)
(require 'subr-x)

(defgroup git-issue nil
  "Git-native issue tracking with git-issue."
  :group 'tools)

(defcustom git-issue-program "git-issue"
  "Program run for every git-issue operation."
  :type 'string)

(define-error 'git-issue-error "git-issue failed")

(defun git-issue-run (&rest args)
  "Run `git-issue-program' with --porcelain and ARGS in `default-directory'.
Return standard output as a string.  On nonzero exit signal
`git-issue-error' whose data is the trimmed standard error."
  (let ((err-file (make-temp-file "git-issue-stderr")))
    (unwind-protect
        (with-temp-buffer
          (let ((status (apply #'call-process git-issue-program nil
                               (list t err-file) nil "--porcelain" args)))
            (if (eql status 0)
                (buffer-string)
              (signal 'git-issue-error
                      (list (string-trim
                             (with-temp-buffer
                               (insert-file-contents err-file)
                               (buffer-string))))))))
      (delete-file err-file))))

(provide 'git-issue)
;;; git-issue.el ends here
```

Create `share/git-issue/emacs/magit-git-issue.el` as a stub:

```elisp
;;; magit-git-issue.el --- Magit interface for git-issue  -*- lexical-binding: t; -*-
;; Package-Requires: ((emacs "28.1") (magit "4.0") (transient "0.7") (with-editor "3.0"))
;;; Commentary:
;; Filled in by later tasks; see draft-ndn-magit-integration-00.
;;; Code:
(require 'git-issue)
(provide 'magit-git-issue)
;;; magit-git-issue.el ends here
```

- [ ] **Step 3: Ship the directory**

`Makefile` install target, after the awk lines:

```make
	install -d $(SHAREDIR)/emacs
	install -m 644 share/git-issue/emacs/*.el $(SHAREDIR)/emacs/
```

Add a target and wire it into `test-all`:

```make
test-emacs-core: ## Run the Elisp core ERT suite (Emacs only, no magit)
	PATH="$(CURDIR)/bin:$$PATH" emacs -Q --batch -L share/git-issue/emacs -l ert -l contrib/emacs/test/git-issue-test.el -f ert-run-tests-batch-and-exit
```

`install-git-issue.sh`, after the awk copy:

```bash
mkdir -p "$INSTALL_DIR/../share/git-issue/emacs"
cp "$(dirname "$0")"/share/git-issue/emacs/*.el "$INSTALL_DIR/../share/git-issue/emacs/"
```

`Formula/git-issue.rb` after line 23: `(share/"git-issue/emacs").install Dir["share/git-issue/emacs/*.el"]`. `git-issue-local.rb` likewise with `#{source_dir}`.

`tests/test_install_layout.sh`: beside each awk assertion add one for `share/git-issue/emacs/git-issue.el` (both the Makefile-install and the script-install checks).

- [ ] **Step 4: Verify**

Core ERT passes (3/3). `./tests/test_install_layout.sh` passes. Corpus listing: `core-loads` and `run-and-error` PASS (the transcripts use `readlink -f` on `bin/git-issue`, so `share/git-issue/emacs` resolves inside the repo). `make test-all` passes.

- [ ] **Step 5: Commit**

```bash
git add share/git-issue/emacs contrib/emacs Makefile install-git-issue.sh Formula/git-issue.rb git-issue-local.rb tests/test_install_layout.sh
git commit -m "feat(emacs): core skeleton with the process runner, shipped beside awk

git-issue.el runs git-issue --porcelain with call-process and surfaces
stderr as a git-issue-error. It lives in share/git-issue/emacs so the
install layout and the repo layout agree, which is what the corpus
transcripts and a user's load-path both rely on. Covers R-core-loads and
R-run-and-error."
```

---

### Task 3: Parsers

**Files:**
- Modify: `share/git-issue/emacs/git-issue.el`
- Test: `contrib/emacs/test/git-issue-test.el`

**Interfaces:**
- Produces: `git-issue-issue` struct and accessors; `git-issue-parse-issue-line`, `git-issue-parse-issue-lines`, `git-issue-parse-edge-lines`, `git-issue-parse-reference-lines`, `git-issue-parse-kv-lines`, `git-issue-detail` struct; `git-issue-parse-detail`.

- [ ] **Step 1: Failing tests**

Append to the test file:

```elisp
(ert-deftest git-issue-parse-issue-line-twelve-columns ()
  (let ((i (git-issue-parse-issue-line
            "\ta1b2c3d\tblocked\thigh\tconformance\tdev\t2026-01-01T00:00:00Z\t\tb2c3d4e,c3d4e5f\t\t\talpha task")))
    (should (null (git-issue-issue-repo i)))
    (should (equal (git-issue-issue-id i) "a1b2c3d"))
    (should (equal (git-issue-issue-status i) "blocked"))
    (should (equal (git-issue-issue-priority i) "high"))
    (should (equal (git-issue-issue-assignee i) "conformance"))
    (should (equal (git-issue-issue-role i) "dev"))
    (should (equal (git-issue-issue-updated i) "2026-01-01T00:00:00Z"))
    (should (null (git-issue-issue-blocks i)))
    (should (equal (git-issue-issue-depends-on i) '("b2c3d4e" "c3d4e5f")))
    (should (equal (git-issue-issue-title i) "alpha task"))))

(ert-deftest git-issue-parse-issue-line-repo-column ()
  (should (equal (git-issue-issue-repo (git-issue-parse-issue-line "tracker\ta\topen\tmedium\t\t\t\t\t\t\t\tx")) "tracker")))

(ert-deftest git-issue-parse-issue-line-rejects-wrong-width ()
  (should-error (git-issue-parse-issue-line "a\tb") :type 'git-issue-error))

(ert-deftest git-issue-parse-issue-lines-skips-blank ()
  (should (= 2 (length (git-issue-parse-issue-lines "\ta\topen\tmedium\t\t\t\t\t\t\t\tx\n\tb\topen\tmedium\t\t\t\t\t\t\t\ty\n")))))

(ert-deftest git-issue-parse-line-shapes ()
  (should (equal (git-issue-parse-edge-lines "a\tblocks\tb\nb\tdepends_on\ta\n")
                 '(("a" "blocks" "b") ("b" "depends_on" "a"))))
  (should (equal (git-issue-parse-reference-lines "0123456789012345678901234567890123456789\tfixes\ta1b2c3d\n")
                 '(("0123456789012345678901234567890123456789" "fixes" "a1b2c3d"))))
  (should (equal (git-issue-parse-kv-lines "enabled\ttrue\nissue-notes\t3\n")
                 '(("enabled" . "true") ("issue-notes" . "3")))))

(ert-deftest git-issue-parse-detail-unfolds ()
  (let ((d (git-issue-parse-detail
            "id: a1b2c3d\ntitle: alpha task\nstatus: open\ndescription: first line\n second line\ncomment: [2026-01-01T00:00:00Z] conformance: one\n two\ncomment: [2026-01-02T00:00:00Z] conformance: three\n")))
    (should (equal (cdr (assoc "title" (git-issue-detail-fields d))) "alpha task"))
    (should (null (assoc "description" (git-issue-detail-fields d))))
    (should (equal (git-issue-detail-description d) "first line\nsecond line"))
    (should (equal (git-issue-detail-comments d)
                   '(("2026-01-01T00:00:00Z" "conformance" "one\ntwo")
                     ("2026-01-02T00:00:00Z" "conformance" "three"))))))

(ert-deftest git-issue-parse-detail-no-description ()
  (let ((d (git-issue-parse-detail "id: a\ntitle: t\n")))
    (should (null (git-issue-detail-description d)))
    (should (null (git-issue-detail-comments d)))))
```

Run the core ERT; expect void-function failures.

- [ ] **Step 2: Implement**

Insert into `git-issue.el` after `git-issue-run`:

```elisp
;;;; Parsing

(cl-defstruct (git-issue-issue (:constructor git-issue-issue-create)
                               (:copier nil))
  "One issue as listed by `git issue list --porcelain'."
  repo id status priority assignee role updated
  blocks depends-on parent-of relates-to title)

(defun git-issue--split-ids (field)
  "Split a comma-joined id FIELD into a list; empty FIELD is nil."
  (and (not (string-empty-p field)) (split-string field ",")))

(defun git-issue-parse-issue-line (line)
  "Parse one twelve-column porcelain issue LINE into a `git-issue-issue'."
  (let ((f (split-string line "\t")))
    (unless (= (length f) 12)
      (signal 'git-issue-error
              (list (format "expected 12 columns, got %d: %S" (length f) line))))
    (git-issue-issue-create
     :repo (and (not (string-empty-p (nth 0 f))) (nth 0 f))
     :id (nth 1 f) :status (nth 2 f) :priority (nth 3 f)
     :assignee (nth 4 f) :role (nth 5 f) :updated (nth 6 f)
     :blocks (git-issue--split-ids (nth 7 f))
     :depends-on (git-issue--split-ids (nth 8 f))
     :parent-of (git-issue--split-ids (nth 9 f))
     :relates-to (git-issue--split-ids (nth 10 f))
     :title (nth 11 f))))

(defun git-issue--nonblank-lines (text)
  (seq-remove #'string-empty-p (split-string text "\n")))

(defun git-issue-parse-issue-lines (text)
  "Parse every issue line in TEXT."
  (mapcar #'git-issue-parse-issue-line (git-issue--nonblank-lines text)))

(defun git-issue-parse-edge-lines (text)
  "Parse edge lines in TEXT into (FROM TYPE TO) lists."
  (mapcar (lambda (l) (split-string l "\t")) (git-issue--nonblank-lines text)))

(defun git-issue-parse-reference-lines (text)
  "Parse reference lines in TEXT into (COMMIT TRAILER ID) lists."
  (mapcar (lambda (l) (split-string l "\t")) (git-issue--nonblank-lines text)))

(defun git-issue-parse-kv-lines (text)
  "Parse key-value lines in TEXT into an alist of strings."
  (mapcar (lambda (l)
            (let ((kv (split-string l "\t")))
              (cons (car kv) (or (cadr kv) ""))))
          (git-issue--nonblank-lines text)))

(cl-defstruct (git-issue-detail (:constructor git-issue-detail-create)
                                (:copier nil))
  "One issue as shown by `git issue show --porcelain'."
  fields description comments)

(defun git-issue--unfold-block (text)
  "Split a porcelain header block TEXT into (KEY . VALUE) records.
A line beginning with one space continues the previous value."
  (let (records)
    (dolist (line (split-string text "\n"))
      (cond
       ((string-empty-p line))
       ((string-prefix-p " " line)
        (when records
          (setcdr (car records)
                  (concat (cdar records) "\n" (substring line 1)))))
       ((string-match "\\`\\([a-z_]+\\):\\(?: \\(.*\\)\\)?\\'" line)
        (push (cons (match-string 1 line) (or (match-string 2 line) ""))
              records))))
    (nreverse records)))

(defun git-issue--parse-comment (value)
  "Parse a comment VALUE `[TIMESTAMP] AUTHOR: TEXT' into a list."
  (if (string-match "\\`\\[\\([^]]+\\)\\] \\([^:]+\\): \\(\\(?:.\\|\n\\)*\\)\\'" value)
      (list (match-string 1 value) (match-string 2 value) (match-string 3 value))
    (list nil nil value)))

(defun git-issue-parse-detail (text)
  "Parse a `show --porcelain' block TEXT into a `git-issue-detail'."
  (let (fields description comments)
    (dolist (rec (git-issue--unfold-block text))
      (pcase (car rec)
        ("description" (setq description (cdr rec)))
        ("comment" (push (git-issue--parse-comment (cdr rec)) comments))
        (_ (push rec fields))))
    (git-issue-detail-create :fields (nreverse fields)
                             :description description
                             :comments (nreverse comments))))
```

- [ ] **Step 3: Verify**

Core ERT all pass. Corpus listing: `parse-issue`, `parse-lines`, `parse-detail` PASS. Byte-check the `parse-detail` transcript's expected output against a local run of the exact `--eval` from the RFC; `princ` prints strings unquoted and lists with spaces, which the RFC's expected lines assume.

- [ ] **Step 4: Commit**

```bash
git add share/git-issue/emacs/git-issue.el contrib/emacs/test/git-issue-test.el
git commit -m "feat(emacs): parse every porcelain shape into Lisp data

Issue lines become git-issue-issue structs, edge, reference and
key-value lines become lists, and the show block becomes a
git-issue-detail with continuation lines unfolded. Covers R-parse-issue,
R-parse-lines and R-parse-detail."
```

---

### Task 4: Commands, completion, trailers

**Files:**
- Modify: `share/git-issue/emacs/git-issue.el`
- Test: `contrib/emacs/test/git-issue-test.el`

**Interfaces:**
- Produces: the command functions, `git-issue-open-ids`, `git-issue-read-id`, `git-issue-format-trailer`, `git-issue-trailer-args`.

- [ ] **Step 1: Failing tests**

```elisp
(ert-deftest git-issue-commands-round-trip ()
  (let* ((default-directory (git-issue-test--scratch-repo))
         (a (git-issue-create "alpha task" "first line\nsecond line"))
         (b (git-issue-create "beta task")))
    (should (string-match-p "\\`[0-9a-f]\\{7\\}\\'" a))
    (git-issue-dep-add a "blocks" b)
    (git-issue-comment a "one\ntwo")
    (should (equal (mapcar #'git-issue-issue-id (git-issue-ready)) (list a)))
    (should (equal (git-issue-detail-description (git-issue-show a)) "first line\nsecond line"))
    (should (equal (caddr (car (git-issue-detail-comments (git-issue-show a)))) "one\ntwo"))
    (should (member (list a "blocks" b) (git-issue-deps)))
    (git-issue-update b "priority" "high")
    (should (equal (git-issue-issue-priority (git-issue-show-issue b)) "high"))
    (git-issue-close b)
    (should (equal (git-issue-open-ids) (list a)))
    (git-issue-reopen b)
    (should (= 2 (length (git-issue-open-ids))))
    (git-issue-start a)
    (should (equal (git-issue-issue-status (git-issue-show-issue a)) "in_progress"))
    (git-issue-dep-rm a "blocks" b)
    (should-not (member (list a "blocks" b) (git-issue-deps)))))

(ert-deftest git-issue-link-records-commit ()
  (let* ((default-directory (git-issue-test--scratch-repo))
         (a (git-issue-create "alpha task"))
         (head (string-trim (with-output-to-string
                              (call-process "git" nil standard-output nil "rev-parse" "HEAD")))))
    (git-issue-link a head)
    (should (string-match-p head (git-issue-run "show" a)))))

(ert-deftest git-issue-trailers ()
  (should (equal (git-issue-format-trailer "fixes" "a1b2c3d") "Fixes: #a1b2c3d"))
  (should (equal (git-issue-format-trailer "related-to" "a1b2c3d") "Related-To: #a1b2c3d"))
  (should (equal (git-issue-trailer-args "closes" "a1b2c3d") '("--trailer" "Closes: #a1b2c3d")))
  (should-error (git-issue-format-trailer "bogus" "a1b2c3d") :type 'git-issue-error))
```

Note `git-issue-show-issue` is a convenience: the issue struct for one id from `list`. If the `link` test's `show` output does not include the commit, read how `link_issue` stores links in `bin/git-issue` and assert on that instead; say so in the report.

- [ ] **Step 2: Implement**

```elisp
;;;; Commands

(defun git-issue-list (&optional all)
  "Issues of the current repository, or of every registered one when ALL."
  (git-issue-parse-issue-lines
   (apply #'git-issue-run "list" (and all '("--all")))))

(defun git-issue-ready (&optional all)
  "Ready issues, or across every registered repository when ALL."
  (git-issue-parse-issue-lines
   (apply #'git-issue-run "ready" (and all '("--all")))))

(defun git-issue-show (id)
  "Detail of issue ID."
  (git-issue-parse-detail (git-issue-run "show" id)))

(defun git-issue-show-issue (id)
  "The `git-issue-issue' for ID from the list, or nil."
  (seq-find (lambda (i) (equal (git-issue-issue-id i) id)) (git-issue-list)))

(defun git-issue-deps (&optional id)
  "Dependency edges, restricted to those leaving ID when given."
  (git-issue-parse-edge-lines
   (apply #'git-issue-run "deps" (and id (list id)))))

(defun git-issue-create (title &optional description)
  "Create an issue with TITLE and optional DESCRIPTION; return its id."
  (string-trim
   (apply #'git-issue-run "create" title
          (and description (not (string-empty-p description))
               (list (concat "--description=" description))))))

(defun git-issue-start (id) "Set ID in progress." (git-issue-run "start" id) t)
(defun git-issue-close (id) "Close ID." (git-issue-run "close" id) t)
(defun git-issue-reopen (id) "Reopen ID." (git-issue-run "reopen" id) t)
(defun git-issue-comment (id text) "Add comment TEXT to ID." (git-issue-run "comment" id text) t)
(defun git-issue-update (id field value)
  "Set FIELD of ID to VALUE."
  (git-issue-run "update" id (format "--%s=%s" field value)) t)
(defun git-issue-dep-add (from type to) "Add edge FROM TYPE TO." (git-issue-run "dep" "add" from type to) t)
(defun git-issue-dep-rm (from type to) "Remove edge FROM TYPE TO." (git-issue-run "dep" "rm" from type to) t)
(defun git-issue-link (id commit) "Link ID to COMMIT." (git-issue-run "link" id commit) t)

(defun git-issue-open-ids ()
  "Ids of issues whose status is not closed."
  (mapcar #'git-issue-issue-id
          (seq-remove (lambda (i) (equal (git-issue-issue-status i) "closed"))
                      (git-issue-list))))

(defun git-issue-read-id (prompt)
  "Read an open issue id with PROMPT and completion."
  (completing-read prompt (git-issue-open-ids) nil t))

;;;; Trailers

(defconst git-issue-trailer-keys
  '(("issue" . "Issue") ("fixes" . "Fixes")
    ("closes" . "Closes") ("related-to" . "Related-To"))
  "Trailer kinds and the keys git-issue writes and scans.")

(defun git-issue-format-trailer (kind id)
  "The trailer line for KIND (issue, fixes, closes, related-to) and ID."
  (let ((key (cdr (assoc kind git-issue-trailer-keys))))
    (unless key (signal 'git-issue-error (list (format "unknown trailer kind: %s" kind))))
    (format "%s: #%s" key id)))

(defun git-issue-trailer-args (kind id)
  "Arguments that make `git commit' add the KIND trailer for ID."
  (list "--trailer" (git-issue-format-trailer kind id)))
```

- [ ] **Step 3: Verify**

Core ERT all pass; corpus listing: `commands`, `trailer` PASS, so all eight core blocks are green. `make test-all` passes.

- [ ] **Step 4: Commit**

```bash
git add share/git-issue/emacs/git-issue.el contrib/emacs/test/git-issue-test.el
git commit -m "feat(emacs): one function per command, completion, and trailers

Every command runs through git-issue-run and returns parsed data;
create returns the id from create --porcelain. Trailer helpers produce
the lines scan-commits reads back. Covers R-commands and R-trailer; the
core corpus is now fully green."
```

---

### Task 5: CI for the core and the corpus

**Files:**
- Modify: `.github/workflows/test.yml`

- [ ] **Step 1: Conformance job**

In the `RFC Conformance` job, before "Install git-issue (subject under test)", add:

```yaml
    - name: Install Emacs (the magit RFC's core transcripts run emacs --batch)
      run: sudo apt-get update && sudo apt-get install -y emacs-nox
```

- [ ] **Step 2: Test job**

In the main test job, after "Run install layout smoke test", add:

```yaml
    - name: Install Emacs
      run: sudo apt-get update && sudo apt-get install -y emacs-nox
    - name: Run Elisp core tests
      run: make test-emacs-core
```

Do the same in the macOS matrix job if it runs `make test-all`; on macOS use `brew install emacs` guarded by `command -v emacs || brew install emacs`. If `make test-all` already includes `test-emacs-core`, the extra step is redundant on jobs that run `test-all`; keep one path per job.

- [ ] **Step 3: Verify locally**

`make test-all` (includes `test-emacs-core`) and the full gate pass. CI verification happens on push; note in the report that it is unverified until then.

- [ ] **Step 4: Commit**

```bash
git add .github/workflows/test.yml
git commit -m "ci: install Emacs for the core ERT suite and the magit corpus"
```

---

### Task 6: Magit UI, part 1: status section, list, ready, and detail buffers

**Files:**
- Modify: `share/git-issue/emacs/magit-git-issue.el`

**Interfaces:**
- Produces: `magit-git-issue-status-section`, `magit-git-issue-insert-issues`, section type `git-issue` with the issue struct as value, `magit-git-issue-list`, `magit-git-issue-ready`, `magit-git-issue-show`, `magit-git-issue-list-mode`, `magit-git-issue-show-mode`, `magit-git-issue-issue-at-point`.

This task needs magit loaded interactively to try; the automated check is the ERT suite in Task 8. Implement against these magit facilities (all present in magit 4.x): `magit-add-section-hook`, `magit-insert-section`, `magit-insert-heading`, `magit-section-value`, `magit-current-section`, `magit-define-section-jumper` (optional), `magit-setup-buffer`, `magit-refresh-buffer` (a per-mode function named `<mode>-refresh-buffer`), `magit-mode` and `magit-mode-map`, `magit-toplevel`.

- [ ] **Step 1: Write the file**

Replace the stub body with, at minimum:

```elisp
(require 'git-issue)
(require 'magit)
(require 'transient)
(require 'with-editor)

(defgroup magit-git-issue nil "Magit interface for git-issue." :group 'git-issue :group 'magit-extensions)

(defcustom magit-git-issue-status-section 'ready
  "Which issues the status buffer section lists: `ready' or `open'."
  :type '(choice (const ready) (const open)))

(defface magit-git-issue-id '((t :inherit magit-hash)) "Face for issue ids.")
(defface magit-git-issue-blocked '((t :inherit magit-dimmed)) "Face for blocked issues.")

(defun magit-git-issue--issues-for-section ()
  (pcase magit-git-issue-status-section
    ('ready (git-issue-ready))
    ('open (seq-remove (lambda (i) (equal (git-issue-issue-status i) "closed")) (git-issue-list)))))

(defun magit-git-issue--insert-issue-line (issue &optional with-repo)
  "Insert one section line for ISSUE; prefix the repo name when WITH-REPO."
  (magit-insert-section (git-issue issue)
    (insert (propertize (git-issue-issue-id issue) 'font-lock-face 'magit-git-issue-id) " ")
    (when (and with-repo (git-issue-issue-repo issue))
      (insert (git-issue-issue-repo issue) " "))
    (insert (git-issue-issue-status issue) " " (git-issue-issue-priority issue) " ")
    (insert (if (equal (git-issue-issue-status issue) "blocked")
                (propertize (git-issue-issue-title issue) 'font-lock-face 'magit-git-issue-blocked)
              (git-issue-issue-title issue)))
    (insert "\n")))

(defun magit-git-issue-insert-issues ()
  "Insert the issues section into the status buffer."
  (condition-case err
      (let ((issues (magit-git-issue--issues-for-section)))
        (when issues
          (magit-insert-section (git-issues nil t)
            (magit-insert-heading (format "Issues (%s)" magit-git-issue-status-section))
            (dolist (i issues) (magit-git-issue--insert-issue-line i))
            (insert "\n"))))
    (git-issue-error (message "git-issue: %s" (cadr err)))))

(magit-add-section-hook 'magit-status-sections-hook #'magit-git-issue-insert-issues
                        #'magit-insert-stashes t)

(defun magit-git-issue-issue-at-point ()
  "The issue struct at point, or nil."
  (let ((s (magit-current-section)))
    (and s (eq (oref s type) 'git-issue) (oref s value))))
```

Then the list and show modes:

```elisp
(defvar magit-git-issue-list-mode-map
  (let ((m (make-sparse-keymap))) (set-keymap-parent m magit-mode-map)
       (define-key m (kbd "RET") #'magit-git-issue-visit) m))

(define-derived-mode magit-git-issue-list-mode magit-mode "Issues"
  "Major mode for listing git-issue issues.")

(defvar-local magit-git-issue--list-command nil)  ; 'list or 'ready
(defvar-local magit-git-issue--list-all nil)

(defun magit-git-issue-list-refresh-buffer ()
  (magit-insert-section (git-issues-buffer)
    (magit-insert-heading (format "%s%s" magit-git-issue--list-command (if magit-git-issue--list-all " --all" "")))
    (dolist (i (if (eq magit-git-issue--list-command 'ready)
                   (git-issue-ready magit-git-issue--list-all)
                 (git-issue-list magit-git-issue--list-all)))
      (magit-git-issue--insert-issue-line i magit-git-issue--list-all))))

(defun magit-git-issue--open-list (command all)
  (magit-setup-buffer #'magit-git-issue-list-mode nil
    (magit-git-issue--list-command command)
    (magit-git-issue--list-all all)))

;;;###autoload
(defun magit-git-issue-list (&optional all)
  "List issues; with prefix ALL, across every registered repository."
  (interactive "P") (magit-git-issue--open-list 'list all))

;;;###autoload
(defun magit-git-issue-ready (&optional all)
  "List ready issues; with prefix ALL, across every registered repository."
  (interactive "P") (magit-git-issue--open-list 'ready all))
```

Detail buffer: `magit-git-issue-show-mode` derived from `magit-mode`, `magit-git-issue-show (id)` setting a buffer-local id and calling `magit-setup-buffer`; its refresh function calls `git-issue-show`, inserts a `headers` section with one line per field, a `description` section with the text verbatim, and one `comment` section per comment headed `[timestamp] author`. `magit-git-issue-visit` on a list line: with the repo column set, look up the registered path (`git issue repo list` parsed as `<name> <path>` lines; add `git-issue-repo-paths` to the core in this task, returning an alist, and a core test for it) and bind `default-directory` to it before opening the detail buffer.

- [ ] **Step 2: Byte-compile and smoke-check**

`emacs -Q --batch -L share/git-issue/emacs -L <magit load path> --eval '(byte-compile-file "share/git-issue/emacs/magit-git-issue.el")'` with your local magit on the load path (find it under `~/.config/emacs/elpaca/builds/magit` and friends: `magit`, `magit-section`, `transient`, `with-editor`, `compat`, `llama` if present, `dash` if required). Zero warnings. Then open a magit status buffer in the repo interactively if you can, or defer to the ERT suite in Task 8.

- [ ] **Step 3: Commit**

```bash
git add share/git-issue/emacs/magit-git-issue.el share/git-issue/emacs/git-issue.el contrib/emacs/test/git-issue-test.el
git commit -m "feat(magit): issues section, list and ready buffers, detail buffer

The status section shows ready work by default or all open issues per
magit-git-issue-status-section; RET opens a detail buffer built from the
show block. A prefix argument lists across the registry, and visiting a
line then runs in that repository. Normative UI of
draft-ndn-magit-integration-00, checked by the ERT suite."
```

---

### Task 7: Magit UI, part 2: the transient, with-editor buffers, commit trailers

**Files:**
- Modify: `share/git-issue/emacs/magit-git-issue.el`

**Interfaces:**
- Produces: `magit-git-issue-dispatch` bound to `x`; suffix commands `magit-git-issue-create`, `-start`, `-close`, `-reopen`, `-comment`, `-set-status`, `-set-priority`, `-set-assignee`, `-set-role`, `-dep-add`, `-dep-rm`, `-link`; commit options; `git-issue-insert-trailer`.

- [ ] **Step 1: Write the transient**

```elisp
(defun magit-git-issue--id (&optional prompt)
  "Id of the issue at point, else read one with PROMPT."
  (let ((i (magit-git-issue-issue-at-point)))
    (if i (git-issue-issue-id i) (git-issue-read-id (or prompt "Issue: ")))))

(defmacro magit-git-issue--define-action (name doc prompt &rest body)
  "Define an interactive command NAME acting on an issue id bound as `id'."
  (declare (indent 3))
  `(defun ,name ()
     ,doc
     (interactive)
     (let ((id (magit-git-issue--id ,prompt)))
       (condition-case err
           (progn ,@body (magit-refresh))
         (git-issue-error (user-error "git-issue: %s" (cadr err)))))))

(magit-git-issue--define-action magit-git-issue-start "Start the issue at point." "Start issue: " (git-issue-start id))
(magit-git-issue--define-action magit-git-issue-close "Close the issue at point." "Close issue: " (git-issue-close id))
(magit-git-issue--define-action magit-git-issue-reopen "Reopen the issue at point." "Reopen issue: " (git-issue-reopen id))
(magit-git-issue--define-action magit-git-issue-set-priority "Set priority." "Issue: "
  (git-issue-update id "priority" (completing-read "Priority: " '("low" "medium" "high" "critical") nil t)))
(magit-git-issue--define-action magit-git-issue-set-status "Set status." "Issue: "
  (git-issue-update id "status" (read-string "Status: ")))
(magit-git-issue--define-action magit-git-issue-set-assignee "Set assignee." "Issue: "
  (git-issue-update id "assignee" (read-string "Assignee: ")))
(magit-git-issue--define-action magit-git-issue-set-role "Set role." "Issue: "
  (git-issue-update id "role" (read-string "Role: ")))
(magit-git-issue--define-action magit-git-issue-dep-add "Add a dependency edge." "From issue: "
  (git-issue-dep-add id (completing-read "Type: " '("blocks" "depends_on" "parent_of" "relates_to") nil t)
                     (git-issue-read-id "To issue: ")))
(magit-git-issue--define-action magit-git-issue-dep-rm "Remove a dependency edge." "From issue: "
  (git-issue-dep-rm id (completing-read "Type: " '("blocks" "depends_on" "parent_of" "relates_to") nil t)
                    (git-issue-read-id "To issue: ")))
(magit-git-issue--define-action magit-git-issue-link "Link the issue to a commit." "Issue: "
  (git-issue-link id (or (magit-commit-at-point) (magit-read-branch-or-commit "Commit"))))
```

Multi-line input via with-editor: implement `magit-git-issue--edit-text (title callback)` that creates a buffer `*git-issue edit*` in `text-mode` with `with-editor-mode` enabled, sets `with-editor-finish-noclient-hook` style behavior: simplest reliable pattern is a small major mode with `C-c C-c` bound to a command that captures `(buffer-string)`, kills the buffer, and calls CALLBACK, and `C-c C-k` that aborts. Use `with-editor`'s keybinding conventions (`C-c C-c` / `C-c C-k`) so muscle memory matches magit's commit buffer; the spec requires those keys, not that `with-editor` itself drives the process. Then:

```elisp
(defun magit-git-issue-comment ()
  "Comment on the issue at point."
  (interactive)
  (let ((id (magit-git-issue--id "Comment on issue: ")))
    (magit-git-issue--edit-text (format "Comment on #%s" id)
      (lambda (text) (git-issue-comment id text) (magit-refresh)))))

(defun magit-git-issue-create ()
  "Create an issue: title in the minibuffer, description in a buffer."
  (interactive)
  (let ((title (read-string "Title: ")))
    (magit-git-issue--edit-text (format "Description for %S (empty to skip)" title)
      (lambda (text)
        (let ((id (git-issue-create title (and (not (string-blank-p text)) text))))
          (message "Created #%s" id) (magit-refresh))))))

;;;###autoload (autoload 'magit-git-issue-dispatch "magit-git-issue" nil t)
(transient-define-prefix magit-git-issue-dispatch ()
  "git-issue commands."
  [["Issue at point"
    ("s" "Start" magit-git-issue-start)
    ("c" "Close" magit-git-issue-close)
    ("o" "Reopen" magit-git-issue-reopen)
    ("m" "Comment" magit-git-issue-comment)
    ("l" "Link to commit" magit-git-issue-link)]
   ["Set"
    ("S" "Status" magit-git-issue-set-status)
    ("p" "Priority" magit-git-issue-set-priority)
    ("a" "Assignee" magit-git-issue-set-assignee)
    ("r" "Role" magit-git-issue-set-role)]
   ["Dependencies"
    ("d" "Add edge" magit-git-issue-dep-add)
    ("D" "Remove edge" magit-git-issue-dep-rm)]
   ["Browse"
    ("n" "New issue" magit-git-issue-create)
    ("L" "List" magit-git-issue-list)
    ("R" "Ready" magit-git-issue-ready)]])

(transient-append-suffix 'magit-dispatch "!" '("x" "Issues" magit-git-issue-dispatch))
(define-key magit-status-mode-map (kbd "x") #'magit-git-issue-dispatch)
(define-key magit-git-issue-list-mode-map (kbd "x") #'magit-git-issue-dispatch)
```

Check the exact suffix location key in your magit's `magit-dispatch` (it has `"!" "Run"`); if `transient-append-suffix` errors because the key differs, append after `"Q"` or at the end of the last group.

- [ ] **Step 2: Commit integration**

```elisp
(defclass magit-git-issue--trailer-option (transient-option) ((kind :initarg :kind)))

(cl-defmethod transient-infix-read ((obj magit-git-issue--trailer-option))
  (git-issue-read-id (format "%s issue: " (capitalize (oref obj kind)))))

(cl-defmethod transient-infix-value ((obj magit-git-issue--trailer-option))
  (when-let ((id (oref obj value)))
    (git-issue-trailer-args (oref obj kind) id)))

(transient-define-infix magit-git-issue:--fixes ()
  :class 'magit-git-issue--trailer-option :kind "fixes" :description "Fixes issue" :key "-x" :argument "--fixes=")
(transient-define-infix magit-git-issue:--closes ()
  :class 'magit-git-issue--trailer-option :kind "closes" :description "Closes issue" :key "-X" :argument "--closes=")
(transient-define-infix magit-git-issue:--issue ()
  :class 'magit-git-issue--trailer-option :kind "issue" :description "References issue" :key "-i" :argument "--issue=")

(transient-append-suffix 'magit-commit "-A" '(magit-git-issue:--fixes))
(transient-append-suffix 'magit-commit '(magit-git-issue:--fixes) '(magit-git-issue:--closes))
(transient-append-suffix 'magit-commit '(magit-git-issue:--closes) '(magit-git-issue:--issue))
```

`transient-infix-value` returning the `("--trailer" "Fixes: #id")` list makes `magit-commit-arguments` carry both strings, which `magit-run-git-with-editor "commit" args` passes straight to git. Verify by reading `magit-commit-create` in your magit; if it flattens or filters arguments, adapt (for example by returning a single string `"--trailer=Fixes: #id"`, which git also accepts). Record what you did in the report.

The insert command:

```elisp
;;;###autoload
(defun git-issue-insert-trailer (kind id)
  "Insert a KIND trailer for ID at the end of the commit message."
  (interactive (list (completing-read "Trailer: " (mapcar #'car git-issue-trailer-keys) nil t)
                     (git-issue-read-id "Issue: ")))
  (save-excursion
    (goto-char (point-max))
    (skip-chars-backward "\n")
    (unless (bolp) (insert "\n"))
    (insert (git-issue-format-trailer kind id) "\n")))
```

Bind it in `git-commit-mode-map` on `C-c C-x` (check for conflicts; `C-c C-x` is unbound in git-commit by default; if taken, choose `C-c x` and record it).

- [ ] **Step 3: Byte-compile clean; commit**

```bash
git add share/git-issue/emacs/magit-git-issue.el
git commit -m "feat(magit): transient on x, editor buffers, commit trailers

Every git-issue action is reachable from the issue at point or by
completion; comments and descriptions edit in a buffer finished with
C-c C-c. The commit transient gains --fixes, --closes and --issue,
passed to git as --trailer, and git-commit-mode gains an insert command."
```

---

### Task 8: UI ERT suite and its CI job

**Files:**
- Create: `contrib/emacs/test/magit-git-issue-test.el`, `contrib/emacs/test/run-ui-tests.sh`
- Modify: `Makefile` (`test-emacs-ui`), `.github/workflows/test.yml`

- [ ] **Step 1: Runner script**

```bash
#!/usr/bin/env bash
# Install magit from NonGNU ELPA into a scratch user-emacs-directory and run
# the UI ERT suite. Emacs and git-issue must be on PATH.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SCRATCH="${GIT_ISSUE_EMACS_SCRATCH:-$(mktemp -d)}"
export PATH="$ROOT/bin:$PATH"
emacs -Q --batch \
  --eval "(setq user-emacs-directory \"$SCRATCH/\")" \
  --eval "(require 'package)" \
  --eval "(add-to-list 'package-archives '(\"nongnu\" . \"https://elpa.nongnu.org/nongnu/\") t)" \
  --eval "(package-initialize)" \
  --eval "(unless (package-installed-p 'magit) (package-refresh-contents) (package-install 'magit))" \
  -L "$ROOT/share/git-issue/emacs" \
  -l ert -l "$ROOT/contrib/emacs/test/magit-git-issue-test.el" \
  -f ert-run-tests-batch-and-exit
```

- [ ] **Step 2: Tests**

Cover each normative bullet of the spec's UI section, structurally where interaction is impossible in batch:

```elisp
(require 'ert) (require 'magit) (require 'magit-git-issue)
(load (expand-file-name "git-issue-test.el" (file-name-directory (or load-file-name buffer-file-name))))

(ert-deftest magit-git-issue-hooks-installed ()
  (should (memq #'magit-git-issue-insert-issues magit-status-sections-hook))
  (should (eq (lookup-key magit-status-mode-map (kbd "x")) #'magit-git-issue-dispatch))
  (should (transient-get-suffix 'magit-dispatch "x")))

(ert-deftest magit-git-issue-status-section-renders-ready ()
  (let* ((default-directory (git-issue-test--scratch-repo))
         (a (git-issue-create "alpha task")) (b (git-issue-create "beta task")))
    (git-issue-dep-add a "blocks" b)
    (with-current-buffer (magit-status-setup-buffer default-directory)
      (goto-char (point-min))
      (should (search-forward "Issues (ready)" nil t))
      (should (search-forward "alpha task" nil t))
      (goto-char (point-min))
      (should-not (search-forward "beta task" nil t))
      (let ((magit-git-issue-status-section 'open))
        (magit-refresh)
        (goto-char (point-min))
        (should (search-forward "beta task" nil t))))))

(ert-deftest magit-git-issue-section-value-is-issue ()
  (let* ((default-directory (git-issue-test--scratch-repo)) (a (git-issue-create "alpha task")))
    (with-current-buffer (magit-status-setup-buffer default-directory)
      (goto-char (point-min)) (search-forward "alpha task")
      (should (equal (git-issue-issue-id (magit-git-issue-issue-at-point)) a)))))

(ert-deftest magit-git-issue-detail-buffer ()
  (let* ((default-directory (git-issue-test--scratch-repo))
         (a (git-issue-create "alpha task" "first\nsecond")))
    (git-issue-comment a "one\ntwo")
    (with-current-buffer (magit-git-issue-show a)
      (should (eq major-mode 'magit-git-issue-show-mode))
      (goto-char (point-min))
      (should (search-forward "first\nsecond" nil t))
      (should (search-forward "one\ntwo" nil t)))))

(ert-deftest magit-git-issue-transient-has-every-action ()
  (dolist (cmd '(magit-git-issue-create magit-git-issue-start magit-git-issue-close magit-git-issue-reopen
                 magit-git-issue-comment magit-git-issue-set-status magit-git-issue-set-priority
                 magit-git-issue-set-assignee magit-git-issue-set-role magit-git-issue-dep-add
                 magit-git-issue-dep-rm magit-git-issue-link magit-git-issue-list magit-git-issue-ready))
    (should (commandp cmd))))

(ert-deftest magit-git-issue-commit-options-present ()
  (dolist (k '("-x" "-X" "-i")) (should (transient-get-suffix 'magit-commit k))))

(ert-deftest magit-git-issue-insert-trailer ()
  (with-temp-buffer
    (insert "subject\n\nbody")
    (cl-letf (((symbol-function 'git-issue-read-id) (lambda (&rest _) "a1b2c3d")))
      (git-issue-insert-trailer "fixes" "a1b2c3d"))
    (should (string-suffix-p "body\nFixes: #a1b2c3d\n" (buffer-string)))))

(ert-deftest magit-git-issue-list-all-prefixes-repo ()
  ;; registry isolation: HOME is the scratch tree in run-ui-tests.sh's CI env
  :expected-result (if (getenv "GIT_ISSUE_TEST_REGISTRY") :passed :failed)
  ...)
```

Design the `--all` test so it registers a scratch repo under an isolated `HOME` (set `HOME` and `XDG_CONFIG_HOME` in the runner script to the scratch dir, like tests/test_registry.sh does) and asserts the list buffer line begins with the registry name and that `magit-git-issue-visit` opens the detail buffer with `default-directory` equal to the registered path. Drop the `:expected-result` placeholder once the runner isolates HOME.

- [ ] **Step 3: Makefile and CI**

```make
test-emacs-ui: ## Run the magit UI ERT suite (installs magit into a scratch dir)
	chmod +x contrib/emacs/test/run-ui-tests.sh
	./contrib/emacs/test/run-ui-tests.sh
```

Do not add it to `test-all` (network). In `.github/workflows/test.yml`, add a job:

```yaml
  emacs-ui:
    runs-on: ubuntu-latest
    name: Emacs UI (magit)
    steps:
    - uses: actions/checkout@v3
    - name: Install Emacs
      run: sudo apt-get update && sudo apt-get install -y emacs-nox
    - name: Set up Git
      run: |
        git config --global user.name "Test User"
        git config --global user.email "test@example.com"
    - name: Cache magit
      uses: actions/cache@v4
      with:
        path: ~/.cache/git-issue-emacs
        key: magit-${{ runner.os }}-v1
    - name: Run UI tests
      run: GIT_ISSUE_EMACS_SCRATCH=$HOME/.cache/git-issue-emacs make test-emacs-ui
```

- [ ] **Step 4: Verify locally**

`make test-emacs-ui` passes (first run downloads magit). Fix any UI defect the suite surfaces in `magit-git-issue.el` in this task, and say what in the report.

- [ ] **Step 5: Commit**

```bash
git add contrib/emacs/test Makefile .github/workflows/test.yml share/git-issue/emacs/magit-git-issue.el
git commit -m "test(magit): ERT suite for the UI with magit from NonGNU ELPA

Checks the hooks and bindings, the status section under both settings,
the detail buffer, the transient's actions, the commit options, and
the trailer insert command. Runs in its own CI job with magit cached."
```

---

### Task 9: Flip the corpus, document, ledger

**Files:**
- Modify: `docs/rfc/draft-ndn-magit-integration-00.md` (masthead only), `README.md`, `man/man1/git-issue.1`, `AGENTS.md`

- [ ] **Step 1: Flip**

`**Corpus:** red (...)` → `**Corpus:** green`. No Changelog, no Date: the commit log is the history; findings go in the commit body.

- [ ] **Step 2: Gate**

`PATH="$PWD/bin:$PATH" ~/.claude/skills/authoring-rfcs/rfc-check docs/rfc` shows all three documents green; `make test-all` passes; three consecutive replays of the magit corpus are green.

- [ ] **Step 3: Docs**

README: an "Emacs and Magit" section (load-path line pointing at `<prefix>/share/git-issue/emacs`, `(require 'magit-git-issue)`, the `x` transient, the status section option, the commit options, the cross-repo prefix argument, and that `git-issue.el` is usable without magit). Man page: a FILES entry for the emacs directory and one paragraph under a new EMACS section. AGENTS.md: one line noting the Elisp core as the sanctioned way for Emacs-side agents to read state.

- [ ] **Step 4: Commit and ledger**

```bash
git add docs/rfc/draft-ndn-magit-integration-00.md README.md man/man1/git-issue.1 AGENTS.md
git commit -m "rfc: magit integration corpus is green

All eight core transcripts replay under emacs --batch, and the UI suite
passes against magit from NonGNU ELPA. Documents the package in the
README, man page, and agent instructions.

Findings from implementation: <bullets for anything the spec left open>"
ledger set magit-integration status=done --as git-issue-agent \
  --evidence "commit:$(git rev-parse --short HEAD)" \
  --evidence "run:rfc-check docs/rfc PASS, 8/8 magit blocks green" \
  --evidence "run:make test-emacs-core PASS; make test-emacs-ui PASS" \
  -m "draft-ndn-magit-integration-00 implemented on feat/magit-integration; corpus green; not yet merged."
```

Stop there. Merging is a separate decision.

---

## Self-review notes

**Spec coverage.** R-core-loads (Task 2), R-create-porcelain (Task 1), R-run-and-error (Task 2), R-parse-issue, R-parse-lines, R-parse-detail (Task 3), R-commands, R-trailer (Task 4). Eight of eight. The UI's normative bullets map to Tasks 6 and 7, each checked by a Task 8 test.

**Ordering.** The CLI change first so the core's `create` has something to parse; core before UI; the core's CI before the UI's, so a broken magit download never masks a core regression.

**Known risks.**
- The repo-vs-contrib location ruling in Task 2 deviates from the interview's "contrib/emacs"; the RFC's install-layout requirement forced it. The tests keep the `contrib/emacs` home.
- Transient option classes returning a list from `transient-infix-value` depend on how `magit-commit` assembles arguments; Task 7 names the fallback (a single `--trailer=` string).
- The UI suite depends on network access to NonGNU ELPA; it is its own CI job and not part of `test-all` for that reason.
- `magit-status-setup-buffer` in batch mode can require a `window-system`-free display path; if a test hangs, use `(magit-setup-buffer #'magit-status-mode ...)` with `magit-display-buffer-function` set to `#'ignore`.
