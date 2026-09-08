;;; magit-git-issue-test.el --- ERT for the magit UI  -*- lexical-binding: t; -*-

;;; Commentary:
;; One test per normative bullet of the "Magit user interface" section of
;; draft-ndn-magit-integration-00, checked structurally where a live
;; keyboard is impossible in batch.  Run it with
;; contrib/emacs/test/run-ui-tests.sh (make test-emacs-ui), which installs
;; magit into a scratch directory and redirects HOME.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'subr-x)
(require 'magit)
(require 'magit-git-issue)

;;;; Helpers

;; Deliberately not the core suite's helper: loading git-issue-test.el here
;; would run the whole core suite again inside the UI job.
(defun magit-git-issue-test--repo ()
  "Create a git repository with one commit; return its directory."
  (let ((dir (file-name-as-directory (make-temp-file "magit-git-issue-test" t))))
    (let ((default-directory dir))
      (call-process "git" nil nil nil "init" "-q")
      (call-process "git" nil nil nil "config" "user.name" "ui tests")
      (call-process "git" nil nil nil "config" "user.email" "ui@tests.invalid")
      (call-process "git" nil nil nil "commit" "-q" "--allow-empty" "-m" "init"))
    ;; `magit-toplevel' resolves symlinks (/var -> /private/var on macOS);
    ;; do the same here so `default-directory' comparisons hold.
    (file-name-as-directory (file-truename dir))))

(defmacro magit-git-issue-test--with-repo (&rest body)
  "Run BODY in a fresh scratch repository, killing the buffers it opened."
  (declare (indent 0) (debug t))
  `(let ((default-directory (magit-git-issue-test--repo))
         (magit-git-issue-test--buffers (buffer-list)))
     (unwind-protect
         (progn ,@body)
       (dolist (buf (buffer-list))
         (unless (memq buf magit-git-issue-test--buffers)
           (let ((kill-buffer-query-functions nil))
             (kill-buffer buf)))))))

(defvar magit-git-issue-test--buffers nil)

(defun magit-git-issue-test--section-types ()
  "Every section type in the current magit buffer, outermost first."
  (let (types)
    (cl-labels ((walk (section)
                  (push (oref section type) types)
                  (dolist (child (oref section children))
                    (walk child))))
      (walk magit-root-section))
    (nreverse types)))

(defun magit-git-issue-test--goto (string)
  "Move point onto the line containing STRING; fail when there is none."
  (goto-char (point-min))
  (should (search-forward string nil t))
  (beginning-of-line))

(defun magit-git-issue-test--line ()
  "The current line, without text properties."
  (buffer-substring-no-properties (line-beginning-position)
                                  (line-end-position)))

(defun magit-git-issue-test--isolated-p ()
  "Non-nil when the runner redirected HOME away from the real registry."
  (getenv "GIT_ISSUE_UI_TEST_ISOLATED"))

;;;; Bullet 1: what the file requires, and what it must not contain

(ert-deftest magit-git-issue-requires-the-specified-features ()
  (should (featurep 'git-issue))
  (should (featurep 'magit))
  (should (featurep 'transient)))

(ert-deftest magit-git-issue-edit-mode-follows-with-editor-keys ()
  "The edit buffer follows magit's commit-buffer keys without with-editor.
`with-editor' drives an external editor process; there is none here, so
it is not a dependency and only the key conventions are shared."
  (should (fboundp 'magit-git-issue-edit-mode))
  (should (keymapp magit-git-issue-edit-mode-map))
  (should (eq (lookup-key magit-git-issue-edit-mode-map (kbd "C-c C-c"))
              #'magit-git-issue-edit-finish))
  (should (eq (lookup-key magit-git-issue-edit-mode-map (kbd "C-c C-k"))
              #'magit-git-issue-edit-abort)))

(defun magit-git-issue-test--code-matches-p (regexp)
  "Non-nil when REGEXP matches UI source outside a comment or string.
Docstrings and comments legitimately name the things the UI must not
call, so a whole-file regex would report them."
  (with-temp-buffer
    (insert-file-contents (locate-library "magit-git-issue.el" t))
    (delay-mode-hooks (emacs-lisp-mode))
    (goto-char (point-min))
    (let ((found nil))
      (while (and (not found) (re-search-forward regexp nil t))
        (let ((beg (match-beginning 0))
              (end (match-end 0))
              (text (match-string 0)))
          ;; `syntax-ppss' moves point, so drive the scan from END ourselves.
          (let ((state (save-excursion (syntax-ppss beg))))
            ;; nth 3 = inside a string (docstrings included), nth 4 = comment.
            (unless (or (nth 3 state) (nth 4 state))
              (setq found text)))
          (goto-char end)))
      found)))

(ert-deftest magit-git-issue-does-not-duplicate-the-core ()
  "The UI file must not run processes or parse porcelain itself."
  (dolist (forbidden '("\\_<call-process\\_>"
                       "\\_<start-process\\_>"
                       "\\_<shell-command\\_>"
                       "\\_<process-lines\\_>"
                       "\\_<git-issue-+parse"))
    (should-not (magit-git-issue-test--code-matches-p forbidden))))

;;;; Bullet 2: hooks and bindings, installed the removable way

(ert-deftest magit-git-issue-section-hook-installed-after-stashes ()
  (should (memq #'magit-git-issue-insert-issues magit-status-sections-hook))
  (let ((stashes (seq-position magit-status-sections-hook
                               #'magit-insert-stashes))
        (issues (seq-position magit-status-sections-hook
                              #'magit-git-issue-insert-issues)))
    (should stashes)
    (should issues)
    (should (> issues stashes))))

(ert-deftest magit-git-issue-section-hook-is-removable ()
  (let ((magit-status-sections-hook (copy-sequence magit-status-sections-hook)))
    (remove-hook 'magit-status-sections-hook #'magit-git-issue-insert-issues)
    (should-not (memq #'magit-git-issue-insert-issues
                      magit-status-sections-hook))))

(ert-deftest magit-git-issue-dispatch-bound-on-x ()
  (should (eq (lookup-key magit-status-mode-map (kbd "x"))
              #'magit-git-issue-dispatch))
  (should (eq (plist-get (cdr (transient-get-suffix 'magit-dispatch "x"))
                         :command)
              'magit-git-issue-dispatch)))

(transient-define-prefix magit-git-issue-test--anchorless ()
  "A transient with none of the keys this package probes for."
  [["Only group"
    ("q" "Quit" ignore)]])

(ert-deftest magit-git-issue-anchor-reports-a-miss-instead-of-signalling ()
  "A magit that renamed every probed key costs an anchor, not the load."
  (should (magit-git-issue--anchor 'magit-git-issue-test--anchorless '("z" "q")))
  (should-not (magit-git-issue--anchor 'magit-git-issue-test--anchorless
                                       '("!" "Q" "z"))))

(defun magit-git-issue-test--suffix-keys (prefix)
  "The :key of every suffix in PREFIX's layout, in layout order."
  (let (keys)
    (magit-git-issue--walk-layout
     (transient--get-layout prefix)
     (lambda (suffix) (push (plist-get (cdr suffix) :key) keys)))
    (nreverse keys)))

(ert-deftest magit-git-issue-add-suffixes-falls-back-to-the-last-group ()
  "With no anchor the suffixes still land, at the end of the last group."
  (should (magit-git-issue--add-suffixes
           'magit-git-issue-test--anchorless '("!" "Q" "z")
           '(("A" "First" ignore) ("B" "Second" ignore))))
  (should (transient-get-suffix 'magit-git-issue-test--anchorless "A"))
  (should (transient-get-suffix 'magit-git-issue-test--anchorless "B"))
  ;; In the order given, reading top to bottom.
  (should (equal (magit-git-issue-test--suffix-keys
                  'magit-git-issue-test--anchorless)
                 '("q" "A" "B"))))

(ert-deftest magit-git-issue-add-suffixes-warns-once-and-skips ()
  "A transient this package cannot place anything in warns; it does not fail.
`transient-append-suffix' reports an unusable location with a message
and no error, so a placement that quietly went nowhere has to be
detected by looking at the layout afterwards."
  (let ((magit-git-issue--placement-warned nil)
        (warnings nil)
        (before (magit-git-issue-test--suffix-keys
                 'magit-git-issue-test--anchorless)))
    (cl-letf (((symbol-function 'transient-append-suffix) #'ignore)
              ((symbol-function 'display-warning)
               (lambda (type message &rest _)
                 (push (cons type (format "%s" message)) warnings))))
      ;; No anchor, and appending places nothing: returns quietly nil.
      (should-not (magit-git-issue--add-suffixes
                   'magit-git-issue-test--anchorless '("!" "Q")
                   '(("C" "Third" ignore))))
      ;; A second failure does not warn again.
      (should-not (magit-git-issue--add-suffixes
                   'magit-git-issue-test--anchorless '("!" "Q")
                   '(("D" "Fourth" ignore)))))
    (should (equal (magit-git-issue-test--suffix-keys
                    'magit-git-issue-test--anchorless)
                   before))
    (should (= 1 (length warnings)))
    (should (eq 'magit-git-issue (car (car warnings))))
    (should (string-match-p "skipping" (cdr (car warnings))))))

(ert-deftest magit-git-issue-add-suffixes-without-the-layout-accessor ()
  "`transient--get-layout' is transient 0.9; the floor here is 0.7.
Magit 4.0, which this package requires, itself requires transient
0.7.4, so reading the layout has to be optional.  Without it the anchor
`transient-get-suffix' finds is taken at its word, and with no anchor
there is nowhere left to put anything -- which warns.  Calling it at
all was a `void-function' at load time, the exact failure the
degradation was for."
  (let ((magit-git-issue--placement-warned nil)
        (warned nil)
        (appended nil))
    (cl-letf (((symbol-function 'transient--get-layout) nil)
              ((symbol-function 'transient-append-suffix)
               (lambda (_prefix loc suffix) (push (cons loc suffix) appended)))
              ((symbol-function 'display-warning)
               (lambda (&rest _) (setq warned t))))
      (should-not (fboundp 'transient--get-layout))
      (should-not (magit-git-issue--layout-readable-p))
      (should-not (magit-git-issue--suffix-count 'magit-git-issue-test--anchorless))
      (should-not (magit-git-issue--last-suffix-location
                   'magit-git-issue-test--anchorless))
      ;; An anchor: `transient-get-suffix' works on old transient too.
      (cl-letf (((symbol-function 'transient-get-suffix)
                 (lambda (_prefix loc) (and (equal loc "q") 'a-suffix))))
        (should (magit-git-issue--add-suffixes
                 'magit-git-issue-test--anchorless '("z" "q")
                 '(("A" "First" ignore)))))
      (should (equal (mapcar #'car appended) '("q")))
      (should-not warned)
      ;; No anchor and no readable layout: nowhere to put them.
      (setq appended nil)
      (cl-letf (((symbol-function 'transient-get-suffix)
                 (lambda (&rest _) (error "not found"))))
        (should-not (magit-git-issue--add-suffixes
                     'magit-git-issue-test--anchorless '("!" "Q")
                     '(("B" "Second" ignore)))))
      (should-not appended)
      (should warned))))

(ert-deftest magit-git-issue-declares-the-transient-its-magit-floor-implies ()
  "The declared transient floor must not promise what magit 4.0 does not.
Magit 4.0 requires transient 0.7.4, so anything newer used here has to
be optional at run time rather than declared as a requirement."
  (with-temp-buffer
    (insert-file-contents (locate-library "magit-git-issue.el" t))
    (goto-char (point-min))
    (should (re-search-forward
             "^;; Package-Requires:.*(transient \"\\([0-9.]+\\)\")" nil t))
    (should (version< (match-string 1) "0.9"))))

(ert-deftest magit-git-issue-add-suffixes-survives-a-signalling-transient ()
  "A `transient-append-suffix' that signals is a warning, not a failed load."
  (let ((magit-git-issue--placement-warned nil)
        (warned nil))
    (cl-letf (((symbol-function 'transient-append-suffix)
               (lambda (&rest _) (error "no such place")))
              ((symbol-function 'display-warning)
               (lambda (&rest _) (setq warned t))))
      (should-not (magit-git-issue--add-suffixes
                   'magit-git-issue-test--anchorless '("!" "Q")
                   '(("E" "Fifth" ignore)))))
    (should warned)))

;;;; Outside a repository

(ert-deftest magit-git-issue-commands-refuse-to-run-outside-a-repository ()
  "Outside a repository the CLI would build a standalone tracker.
It writes one under `~/.local/share/git-issue' and a `.git-issue'
directory beside it.  From magit that is never what was meant, so every
entry point stops first -- and nothing is created."
  (skip-unless (magit-git-issue-test--isolated-p))
  (let* ((plain (file-name-as-directory (make-temp-file "not-a-repo" t)))
         (data (expand-file-name "git-issue" (getenv "XDG_DATA_HOME")))
         (default-directory plain))
    (should-not (magit-toplevel))
    (dolist (command '(magit-git-issue-insert-issues
                       magit-git-issue-list
                       magit-git-issue-ready
                       magit-git-issue-create
                       magit-git-issue-start
                       magit-git-issue-set-status))
      (let ((err (should-error (funcall command) :type 'user-error)))
        (should (string-match-p "Not inside a git repository" (cadr err)))))
    (let ((err (should-error (call-interactively #'magit-git-issue-show)
                             :type 'user-error)))
      (should (string-match-p "Not inside a git repository" (cadr err))))
    ;; The point of the guard: no tracker anywhere.
    (should-not (file-exists-p data))
    (should-not (file-exists-p (expand-file-name ".git-issue" plain)))))

;;;; Bullet 3: the status buffer section

(ert-deftest magit-git-issue-status-section-defaults-to-ready ()
  (should (eq (default-value 'magit-git-issue-status-section) 'ready)))

(ert-deftest magit-git-issue-status-section-honours-the-option ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task"))
          (b (git-issue-create "beta task")))
      (git-issue-dep-add a "blocks" b)
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (goto-char (point-min))
        (should (search-forward "Issues (ready)" nil t))
        (goto-char (point-min))
        (should (search-forward "alpha task" nil t))
        ;; `beta task' is blocked, so `ready' leaves it out.
        (goto-char (point-min))
        (should-not (search-forward "beta task" nil t))
        (setq-local magit-git-issue-status-section 'open)
        (magit-refresh-buffer)
        (goto-char (point-min))
        (should (search-forward "Issues (open)" nil t))
        (goto-char (point-min))
        (should (search-forward "beta task" nil t))))))

(ert-deftest magit-git-issue-status-section-omits-closed-issues ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task")))
      (git-issue-close a)
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (setq-local magit-git-issue-status-section 'open)
        (magit-refresh-buffer)
        (goto-char (point-min))
        (should-not (search-forward "alpha task" nil t))))))

(ert-deftest magit-git-issue-status-line-has-the-specified-format ()
  "`<id> <status> <priority> <title>', with no repo column in one repo."
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task")))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (magit-git-issue-test--goto "alpha task")
        (should (equal (magit-git-issue-test--line)
                       (format "%s open medium alpha task" a)))))))

(ert-deftest magit-git-issue-line-is-a-git-issue-section ()
  "Each line is a `magit-section' of type `git-issue' valued by the struct."
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task")))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (magit-git-issue-test--goto "alpha task")
        (let ((section (magit-current-section)))
          (should (eq (oref section type) 'git-issue))
          (should (git-issue-issue-p (oref section value))))
        (let ((issue (magit-git-issue-issue-at-point)))
          (should (git-issue-issue-p issue))
          (should (equal (git-issue-issue-id issue) a))
          (should (equal (git-issue-issue-title issue) "alpha task")))))))

(ert-deftest magit-git-issue-section-is-collapsible ()
  (magit-git-issue-test--with-repo
    (git-issue-create "alpha task")
    (with-current-buffer (magit-status-setup-buffer default-directory)
      (magit-git-issue-test--goto "Issues (ready)")
      (let ((section (magit-current-section)))
        (should (eq (oref section type) 'git-issues))
        (should-not (oref section hidden))
        (magit-section-hide section)
        (should (oref section hidden))
        (magit-section-show section)
        (should-not (oref section hidden))))))

(ert-deftest magit-git-issue-status-section-is-quiet-with-no-ready-work ()
  "No ready work is an empty section, not something to report.
This caught `ready --porcelain' exiting 1 on an empty result, which made
the section announce a failure in every repository with nothing ready."
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task"))
          (said nil))
      (git-issue-close a)
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest args)
                   (when format-string
                     (push (apply #'format format-string args) said)))))
        (magit-status-setup-buffer default-directory))
      (should-not (seq-find (lambda (line) (string-prefix-p "git-issue:" line))
                            said)))))

(ert-deftest magit-git-issue-status-section-survives-a-cli-failure ()
  "A broken CLI reports itself; it does not abort the status refresh.
Both halves matter: surviving silently would hide the breakage, so the
`message' has to happen as well as the rest of the buffer."
  (magit-git-issue-test--with-repo
    (let ((git-issue-program "git-issue-does-not-exist")
          (said nil))
      (cl-letf (((symbol-function 'message)
                 (lambda (format-string &rest args)
                   (when format-string
                     (push (apply #'format format-string args) said)))))
        (with-current-buffer (magit-status-setup-buffer default-directory)
          (goto-char (point-min))
          (should (search-forward "Recent commits" nil t))))
      (should (seq-find (lambda (line) (string-prefix-p "git-issue:" line))
                        said)))))

(ert-deftest magit-git-issue-status-section-survives-an-unrunnable-program ()
  "A program that exists but cannot be run must not abort the refresh.
`call-process' signals `permission-denied' for a non-executable file and
other `file-error' subtypes for a directory or a bad interpreter line;
catching only `file-missing' let those through."
  (magit-git-issue-test--with-repo
    (let ((unrunnable (make-temp-file "git-issue-not-executable"))
          (said nil))
      (unwind-protect
          (let ((git-issue-program unrunnable))
            (set-file-modes unrunnable #o644)
            (should-not (file-executable-p unrunnable))
            (cl-letf (((symbol-function 'message)
                       (lambda (format-string &rest args)
                         (when format-string
                           (push (apply #'format format-string args) said)))))
              (with-current-buffer (magit-status-setup-buffer default-directory)
                (goto-char (point-min))
                (should (search-forward "Recent commits" nil t))))
            (should (seq-find (lambda (line) (string-prefix-p "git-issue:" line))
                              said)))
        (delete-file unrunnable)))))

;;;; Bullet 4: the list and ready buffers

(ert-deftest magit-git-issue-list-and-ready-open-magit-buffers ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task"))
          (b (git-issue-create "beta task")))
      (git-issue-dep-add a "blocks" b)
      (with-current-buffer (magit-git-issue-list)
        (should (derived-mode-p 'magit-mode))
        (should (eq major-mode 'magit-git-issue-list-mode))
        (goto-char (point-min))
        (should (search-forward "alpha task" nil t))
        (goto-char (point-min))
        (should (search-forward "beta task" nil t)))
      (with-current-buffer (magit-git-issue-ready)
        (should (eq major-mode 'magit-git-issue-list-mode))
        (goto-char (point-min))
        (should (search-forward "alpha task" nil t))
        (goto-char (point-min))
        (should-not (search-forward "beta task" nil t))))))

(ert-deftest magit-git-issue-list-all-puts-the-repo-name-first ()
  (skip-unless (magit-git-issue-test--isolated-p))
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task")))
      ;; One registry is shared by the whole run; name each repo uniquely.
      (git-issue-run "repo" "add" "listed" ".")
      (should (assoc "listed" (git-issue-repo-paths)))
      (with-current-buffer (magit-git-issue-list t)
        (magit-git-issue-test--goto "alpha task")
        ;; The repo name comes FIRST: the spec says lines are prefixed
        ;; with it.
        (should (equal (magit-git-issue-test--line)
                       (format "listed %s open medium alpha task" a)))
        (should (string-prefix-p "listed " (magit-git-issue-test--line)))))))

(ert-deftest magit-git-issue-prefix-argument-means-all ()
  "A prefix argument to `list' and `ready' means --all, and nothing else does."
  (skip-unless (magit-git-issue-test--isolated-p))
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "prefixed alpha"))
          (second (magit-git-issue-test--repo)))
      (git-issue-run "repo" "add" "prefixa" ".")
      (let ((default-directory second))
        (git-issue-create "prefixed beta")
        (git-issue-run "repo" "add" "prefixb" "."))
      ;; No prefix argument: this repository only, and no repo column.
      (with-current-buffer (call-interactively #'magit-git-issue-list)
        (magit-git-issue-test--goto "prefixed alpha")
        (should (equal (magit-git-issue-test--line)
                       (format "%s open medium prefixed alpha" a)))
        (goto-char (point-min))
        (should-not (search-forward "prefixed beta" nil t)))
      (with-current-buffer (call-interactively #'magit-git-issue-ready)
        (magit-git-issue-test--goto "prefixed alpha")
        (should-not (string-prefix-p "prefixa " (magit-git-issue-test--line)))
        (goto-char (point-min))
        (should-not (search-forward "prefixed beta" nil t)))
      ;; With one: every registered repository, each line prefixed by name.
      (let ((current-prefix-arg '(4)))
        (with-current-buffer (call-interactively #'magit-git-issue-list)
          (magit-git-issue-test--goto "prefixed alpha")
          (should (string-prefix-p "prefixa " (magit-git-issue-test--line)))
          (magit-git-issue-test--goto "prefixed beta")
          (should (string-prefix-p "prefixb " (magit-git-issue-test--line)))))
      ;; `ready --all' reaches the other repository too.
      (let ((current-prefix-arg '(4)))
        (with-current-buffer (call-interactively #'magit-git-issue-ready)
          (magit-git-issue-test--goto "prefixed beta")
          (should (string-prefix-p "prefixb " (magit-git-issue-test--line))))))))

(ert-deftest magit-git-issue-visit-runs-in-the-registered-repository ()
  (skip-unless (magit-git-issue-test--isolated-p))
  (magit-git-issue-test--with-repo
    ;; A title of its own: `--all' also lists the repo the neighbouring
    ;; registry test registered, and both would otherwise say "alpha task".
    (let ((a (git-issue-create "visitable task"))
          (registered default-directory))
      (git-issue-run "repo" "add" "visited" ".")
      ;; Visit from a *different* repository: magit buffers must be set up
      ;; inside a worktree, and this is the real cross-repo case anyway.
      (let ((default-directory (magit-git-issue-test--repo)))
        (with-current-buffer (magit-git-issue-list t)
          (magit-git-issue-test--goto "visitable task")
          (magit-git-issue-visit)
          (should (eq major-mode 'magit-git-issue-show-mode))
          (should (equal (file-truename default-directory)
                         (file-truename registered)))
          (goto-char (point-min))
          (should (search-forward a nil t)))))))

(ert-deftest magit-git-issue-visit-names-a-registered-path-that-is-gone ()
  "A registry entry whose directory is gone is named, not passed to magit.
Without the check the dead path reaches `magit-setup-buffer' and comes
back as magit's generic outside-a-repository error, which says nothing
about which entry to fix."
  (skip-unless (magit-git-issue-test--isolated-p))
  (magit-git-issue-test--with-repo
    (let ((registered default-directory))
      (git-issue-create "vanishing task")
      (git-issue-run "repo" "add" "vanished" ".")
      (unwind-protect
          (let ((default-directory (magit-git-issue-test--repo)))
            (with-current-buffer (magit-git-issue-list t)
              (magit-git-issue-test--goto "vanishing task")
              ;; The registered directory goes away behind the buffer's back.
              (delete-directory registered t)
              (should (git-issue-repo-path-missing-p
                       (cdr (assoc "vanished" (git-issue-repo-paths)))))
              (let ((err (should-error (magit-git-issue-visit) :type 'user-error)))
                (should (string-match-p "vanished" (cadr err)))
                (should (string-match-p
                         (regexp-quote (directory-file-name registered))
                         (cadr err))))
              ;; `--all' names it too, rather than reporting the sweep's
              ;; nonzero exit as a bare CLI failure.
              (let ((err (should-error (magit-git-issue-list t) :type 'user-error)))
                (should (string-match-p "vanished" (cadr err))))))
        ;; One registry is shared by the whole run: leave no dead entry
        ;; behind for the other `--all' tests.  `default-directory' is the
        ;; directory this test deleted, so the process needs another one.
        (let ((default-directory temporary-file-directory))
          (ignore-errors (git-issue-run "repo" "rm" "vanished")))
        (should-not (assoc "vanished" (let ((default-directory
                                             temporary-file-directory))
                                        (git-issue-repo-paths))))))))

(ert-deftest magit-git-issue-list-mode-visits-on-ret ()
  (magit-git-issue-test--with-repo
    (git-issue-create "alpha task")
    (with-current-buffer (magit-git-issue-list)
      (magit-git-issue-test--goto "alpha task")
      (should (eq (key-binding (kbd "RET")) #'magit-git-issue-visit)))))

(ert-deftest magit-git-issue-status-buffer-visits-on-ret ()
  (magit-git-issue-test--with-repo
    (git-issue-create "alpha task")
    (with-current-buffer (magit-status-setup-buffer default-directory)
      (magit-git-issue-test--goto "alpha task")
      (should (eq (key-binding (kbd "RET")) #'magit-git-issue-visit)))))

;;;; Bullet 5: the detail buffer

(ert-deftest magit-git-issue-detail-buffer-renders-the-struct ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task" "first line\nsecond line")))
      (git-issue-comment a "one\ntwo")
      (with-current-buffer (magit-git-issue-show a)
        (should (derived-mode-p 'magit-mode))
        (should (eq major-mode 'magit-git-issue-show-mode))
        (let ((types (magit-git-issue-test--section-types)))
          (should (memq 'headers types))
          (should (memq 'description types))
          (should (memq 'comment types)))
        (goto-char (point-min))
        (should (search-forward "alpha task" nil t))
        ;; description verbatim, newlines and all
        (goto-char (point-min))
        (should (search-forward "first line\nsecond line" nil t))
        (goto-char (point-min))
        (should (search-forward "one\ntwo" nil t))))))

(ert-deftest magit-git-issue-detail-buffer-has-one-section-per-comment ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task")))
      (git-issue-comment a "one")
      (git-issue-comment a "two")
      (with-current-buffer (magit-git-issue-show a)
        (should (= 2 (seq-count (lambda (type) (eq type 'comment))
                                (magit-git-issue-test--section-types))))))))

(ert-deftest magit-git-issue-detail-buffer-refreshes-with-g ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task")))
      (with-current-buffer (magit-git-issue-show a)
        (goto-char (point-min))
        (should-not (search-forward "added later" nil t))
        (git-issue-comment a "added later")
        (should (eq (key-binding (kbd "g")) #'magit-refresh))
        (magit-refresh-buffer)
        (goto-char (point-min))
        (should (search-forward "added later" nil t))))))

;;;; Bullet 6: the dispatch transient and its actions

(ert-deftest magit-git-issue-dispatch-offers-every-specified-action ()
  (dolist (command '(magit-git-issue-create
                     magit-git-issue-start
                     magit-git-issue-close
                     magit-git-issue-reopen
                     magit-git-issue-comment
                     magit-git-issue-set-status
                     magit-git-issue-set-priority
                     magit-git-issue-set-assignee
                     magit-git-issue-set-role
                     magit-git-issue-dep-add
                     magit-git-issue-dep-rm
                     magit-git-issue-link
                     magit-git-issue-list
                     magit-git-issue-ready))
    (should (commandp command))
    ;; Located by command, not by key: the keys are not normative.
    (let ((suffix (transient-get-suffix 'magit-git-issue-dispatch command)))
      (should suffix)
      (should (eq (plist-get (cdr suffix) :command) command)))))

(ert-deftest magit-git-issue-actions-use-the-issue-at-point ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task")))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (magit-git-issue-test--goto "alpha task")
        ;; No prompt may be reached: the issue is at point.
        (cl-letf (((symbol-function 'git-issue-read-id)
                   (lambda (&rest _) (error "Should not prompt"))))
          (magit-git-issue-start))
        (should (equal (git-issue-issue-status (git-issue-show-issue a))
                       "in_progress"))))))

(ert-deftest magit-git-issue-actions-prompt-without-an-issue-at-point ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task"))
          (prompted nil))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (goto-char (point-min))
        (should-not (magit-git-issue-issue-at-point))
        (cl-letf (((symbol-function 'git-issue-read-id)
                   (lambda (&rest _) (setq prompted t) a)))
          (magit-git-issue-start))
        (should prompted)
        (should (equal (git-issue-issue-status (git-issue-show-issue a))
                       "in_progress"))))))

(ert-deftest magit-git-issue-actions-refresh-only-on-success ()
  "Every action refreshes the current magit buffer on success, and only then."
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task"))
          (refreshes 0))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (cl-letf (((symbol-function 'magit-refresh)
                   (lambda (&rest _) (setq refreshes (1+ refreshes)))))
          (magit-git-issue-test--goto "alpha task")
          (magit-git-issue-start)
          (should (= refreshes 1))
          (should (equal (git-issue-issue-status (git-issue-show-issue a))
                         "in_progress"))
          ;; A rejected action must leave the buffer alone.
          (setq refreshes 0)
          (goto-char (point-min))
          (should-not (magit-git-issue-issue-at-point))
          (cl-letf (((symbol-function 'git-issue-read-id)
                     (lambda (&rest _) "zzzzzzz")))
            (should-error (magit-git-issue-close) :type 'user-error))
          (should (= refreshes 0)))))))

(ert-deftest magit-git-issue-actions-report-the-cli-error ()
  (magit-git-issue-test--with-repo
    (git-issue-create "alpha task")
    (with-current-buffer (magit-status-setup-buffer default-directory)
      (goto-char (point-min))
      (cl-letf (((symbol-function 'git-issue-read-id) (lambda (&rest _) "zzzzzzz")))
        (let ((err (should-error (magit-git-issue-close) :type 'user-error)))
          (should (string-match-p "not found" (cadr err)))
          ;; The CLI's SGR escapes must not reach the echo area.
          (should-not (string-match-p "\e\\[" (cadr err))))))))

(ert-deftest magit-git-issue-actions-report-a-failure-while-prompting ()
  "A CLI failure while building the completion table is a `user-error' too.
With no issue at point the id comes from `git-issue-read-id', which
runs the CLI; reading it outside the handler let that escape as a raw
`git-issue-error'."
  (magit-git-issue-test--with-repo
    (git-issue-create "alpha task")
    (with-current-buffer (magit-status-setup-buffer default-directory)
      (goto-char (point-min))
      (should-not (magit-git-issue-issue-at-point))
      (cl-letf (((symbol-function 'git-issue-list)
                 (lambda (&rest _)
                   (signal 'git-issue-error (list "Error: registry is broken")))))
        (dolist (command '(magit-git-issue-start
                           magit-git-issue-close
                           magit-git-issue-set-status
                           magit-git-issue-comment))
          (let ((err (should-error (funcall command) :type 'user-error)))
            (should (string-match-p "registry is broken" (cadr err)))))
        (let ((err (should-error (call-interactively #'magit-git-issue-show)
                                 :type 'user-error)))
          (should (string-match-p "registry is broken" (cadr err))))))))

(ert-deftest magit-git-issue-set-priority-updates-the-issue ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task")))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (magit-git-issue-test--goto "alpha task")
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (&rest _) "high")))
          (magit-git-issue-set-priority))
        (should (equal (git-issue-issue-priority (git-issue-show-issue a))
                       "high"))))))

(ert-deftest magit-git-issue-set-role-completes-over-the-roles-in-use ()
  "The CLI does not constrain roles, so the prompt offers the ones in use."
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task"))
          (b (git-issue-create "beta task"))
          (offered nil))
      (git-issue-update a "role" "reviewer")
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (magit-git-issue-test--goto "beta task")
        (cl-letf (((symbol-function 'completing-read)
                   (lambda (_prompt collection &rest _)
                     (setq offered collection)
                     "reviewer")))
          (magit-git-issue-set-role))
        (should (member "reviewer" offered))
        (should (equal (git-issue-issue-role (git-issue-show-issue b))
                       "reviewer"))))))

(ert-deftest magit-git-issue-set-status-offers-the-repositorys-own-statuses ()
  "A status this repository uses completes even when the option omits it.
A repository can define its own status machine in `.git-issue/statuses',
and then its vocabulary is the one worth completing, so the fixed
defcustom is unioned with what the repository's issues actually carry."
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task"))
          (offered nil))
      (git-issue-update a "status" "review")
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (magit-git-issue-test--goto "alpha task")
        ;; `review' removed from the option: only the repository has it.
        (let ((magit-git-issue-statuses '("open" "closed")))
          (cl-letf (((symbol-function 'completing-read)
                     (lambda (_prompt collection &rest _)
                       (setq offered collection)
                       "open")))
            (magit-git-issue-set-status)))
        (should (member "review" offered))
        (should (member "open" offered))
        (should (member "closed" offered))
        (should (equal (git-issue-issue-status (git-issue-show-issue a))
                       "open"))))))

(ert-deftest magit-git-issue-dep-add-creates-the-edge ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task"))
          (b (git-issue-create "beta task")))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (magit-git-issue-test--goto "alpha task")
        (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "blocks"))
                  ((symbol-function 'git-issue-read-id) (lambda (&rest _) b)))
          (magit-git-issue-dep-add))
        (should (member (list a "blocks" b) (git-issue-deps)))))))

(ert-deftest magit-git-issue-link-uses-the-commit-at-point ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task"))
          (head (magit-rev-parse "HEAD")))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (magit-git-issue-test--goto "alpha task")
        (cl-letf (((symbol-function 'magit-commit-at-point) (lambda () head)))
          (magit-git-issue-link))
        (should (string-match-p "Linked to commit" (git-issue-run "show" a)))))))

;;;; Bullet 6: the edit buffer, finished with C-c C-c and aborted with C-c C-k

(ert-deftest magit-git-issue-comment-uses-an-edit-buffer ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task")))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (magit-git-issue-test--goto "alpha task")
        (magit-git-issue-comment)
        (should (eq major-mode 'magit-git-issue-edit-mode))
        (should (eq (key-binding (kbd "C-c C-c"))
                    #'magit-git-issue-edit-finish))
        (should (eq (key-binding (kbd "C-c C-k"))
                    #'magit-git-issue-edit-abort))
        (insert "one\ntwo")
        (call-interactively (key-binding (kbd "C-c C-c")))
        (should (equal (caddr (car (git-issue-detail-comments
                                    (git-issue-show a))))
                       "one\ntwo"))
        (should-not (get-buffer "*git-issue edit*"))))))

(ert-deftest magit-git-issue-a-second-composition-keeps-the-first ()
  "Starting a second edit must not silently discard an unfinished one."
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task"))
          (b (git-issue-create "beta task")))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (cl-letf (((symbol-function 'git-issue-read-id) (lambda (&rest _) a)))
          (magit-git-issue-comment))
        (let ((first (current-buffer)))
          (insert "text for alpha")
          (cl-letf (((symbol-function 'git-issue-read-id) (lambda (&rest _) b)))
            (magit-git-issue-comment))
          (let ((second (current-buffer)))
            (should-not (eq second first))
            (should (buffer-live-p first))
            (should (equal (with-current-buffer first
                             (buffer-substring-no-properties (point-min)
                                                             (point-max)))
                           "text for alpha"))
            (should (equal (with-current-buffer second
                             (buffer-substring-no-properties (point-min)
                                                             (point-max)))
                           ""))
            ;; Each finishes into its own issue.
            (insert "text for beta")
            (call-interactively (key-binding (kbd "C-c C-c")))
            (with-current-buffer first
              (call-interactively (key-binding (kbd "C-c C-c"))))
            (should (equal (caddr (car (git-issue-detail-comments
                                        (git-issue-show a))))
                           "text for alpha"))
            (should (equal (caddr (car (git-issue-detail-comments
                                        (git-issue-show b))))
                           "text for beta"))))))))

(ert-deftest magit-git-issue-edit-buffer-aborts-without-acting ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task")))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (magit-git-issue-test--goto "alpha task")
        (magit-git-issue-comment)
        (insert "discard me")
        (call-interactively (key-binding (kbd "C-c C-k")))
        (should-not (get-buffer "*git-issue edit*"))
        (should (null (git-issue-detail-comments (git-issue-show a))))))))

(ert-deftest magit-git-issue-edit-buffer-keeps-text-when-rejected ()
  "A rejection from the CLI must not destroy what the user composed."
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task")))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (magit-git-issue-test--goto "alpha task")
        (magit-git-issue-comment)
        (insert "carefully composed\ntext")
        ;; A transient failure: the CLI is broken while this finish runs.
        (let ((err (let ((git-issue-program "false"))
                     (should-error
                      (call-interactively (key-binding (kbd "C-c C-c")))
                      :type 'user-error))))
          (should (string-match-p (regexp-quote git-issue-silent-failure-message)
                                  (cadr err))))
        (let ((buffer (get-buffer "*git-issue edit*")))
          (should buffer)
          (with-current-buffer buffer
            (should (equal (buffer-substring-no-properties (point-min) (point-max))
                           "carefully composed\ntext"))
            ;; The cause is gone, so the *real* command finishes it: nothing
            ;; is put back by hand, which is what makes this a retry.
            (call-interactively (key-binding (kbd "C-c C-c")))))
        (should-not (get-buffer "*git-issue edit*"))
        (should (equal (caddr (car (git-issue-detail-comments
                                    (git-issue-show a))))
                       "carefully composed\ntext"))))))

(ert-deftest magit-git-issue-literal-doubles-every-percent ()
  (should (equal (magit-git-issue--literal "50%b done") "50%%b done"))
  (should (equal (magit-git-issue--literal "100%% sure") "100%%%% sure"))
  (should (equal (magit-git-issue--literal "plain") "plain")))

(ert-deftest magit-git-issue-edit-buffer-header-renders-a-percent-verbatim ()
  "A header line is a mode-line construct: `%b' in a title is not a spec.
An issue titled `50%b done' rendered the buffer name where its `%b' was.
`format-mode-line' returns the empty string in batch -- there is no
redisplay to run -- so the construct itself is what is checked: `%b'
appears only in its doubled, self-standing form."
  (magit-git-issue-test--with-repo
    (with-current-buffer (magit-status-setup-buffer default-directory)
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "50%b done")))
        (magit-git-issue-create))
      (should (eq major-mode 'magit-git-issue-edit-mode))
      (should (stringp header-line-format))
      (should (string-match-p (regexp-quote "50%%b done") header-line-format))
      ;; The unescaped spec is nowhere in it.
      (should-not (string-match-p "\\(\\`\\|[^%]\\)%b" header-line-format)))))

(ert-deftest magit-git-issue-create-skips-an-empty-description ()
  (magit-git-issue-test--with-repo
    (with-current-buffer (magit-status-setup-buffer default-directory)
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "titled only")))
        (magit-git-issue-create))
      (call-interactively (key-binding (kbd "C-c C-c")))
      (let ((id (car (git-issue-open-ids))))
        (should (equal (git-issue-issue-title (git-issue-show-issue id))
                       "titled only"))
        (should (null (git-issue-detail-description (git-issue-show id))))))))

(ert-deftest magit-git-issue-create-stores-the-description ()
  (magit-git-issue-test--with-repo
    (with-current-buffer (magit-status-setup-buffer default-directory)
      (cl-letf (((symbol-function 'read-string) (lambda (&rest _) "described")))
        (magit-git-issue-create))
      (insert "first line\nsecond line")
      (call-interactively (key-binding (kbd "C-c C-c")))
      (let ((id (car (git-issue-open-ids))))
        (should (equal (git-issue-detail-description (git-issue-show id))
                       "first line\nsecond line"))))))

;;;; Bullet 7: commit integration

(ert-deftest magit-git-issue-commit-options-are-present ()
  (dolist (entry '(("-x" . magit-git-issue:--fixes)
                   ("-X" . magit-git-issue:--closes)
                   ("-i" . magit-git-issue:--issue)))
    (let ((suffix (transient-get-suffix 'magit-commit (car entry))))
      (should suffix)
      (should (eq (plist-get (cdr suffix) :command) (cdr entry))))))

(ert-deftest magit-git-issue-commit-option-value-is-trailer-arguments ()
  (let ((obj (clone (get 'magit-git-issue:--fixes 'transient--suffix))))
    (should (null (transient-infix-value obj)))
    (oset obj value "a1b2c3d")
    (should (equal (transient-infix-value obj)
                   (git-issue-trailer-args "fixes" "a1b2c3d")))
    (should (equal (transient-infix-value obj)
                   '("--trailer" "Fixes: #a1b2c3d")))))

(ert-deftest magit-git-issue-commit-option-reads-an-id-with-completion ()
  ;; `transient-infix-read' itself cannot be called outside a live
  ;; transient -- transient wraps the generic in an `:around' method that
  ;; touches `transient--prefix' -- so the method is checked structurally
  ;; and its reader is exercised directly.
  (should (cl-find-method 'transient-infix-read nil
                          '(magit-git-issue--trailer-option)))
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task"))
          (obj (clone (get 'magit-git-issue:--closes 'transient--suffix)))
          (offered nil))
      (cl-letf (((symbol-function 'completing-read)
                 (lambda (_prompt collection &rest _)
                   (setq offered collection)
                   a)))
        (should (equal (magit-git-issue--read-trailer-id obj) a)))
      (should (member a offered))
      ;; A second read clears the option again.
      (oset obj value a)
      (should (null (magit-git-issue--read-trailer-id obj))))))

(ert-deftest magit-git-issue-commit-passes-the-trailer-to-git ()
  "The option's value must reach git as a real --trailer argument."
  (magit-git-issue-test--with-repo
    (let (argv)
      (cl-letf (((symbol-function 'magit-run-git-with-editor)
                 (lambda (&rest args)
                   (setq argv (magit-process-git-arguments args)))))
        (magit-commit-create
         (list "--allow-empty" (git-issue-trailer-args "fixes" "a1b2c3d"))))
      (should argv)
      (should (equal (last argv 4)
                     '("commit" "--allow-empty" "--trailer" "Fixes: #a1b2c3d"))))))

(ert-deftest magit-git-issue-insert-trailer-is-bound-in-git-commit-mode ()
  (should (commandp 'git-issue-insert-trailer))
  (should (eq (lookup-key git-commit-mode-map (kbd "C-c C-x"))
              #'git-issue-insert-trailer)))

(ert-deftest magit-git-issue-insert-trailer-appends-to-the-message ()
  (with-temp-buffer
    (setq-local comment-start "#")
    (insert "subject\n\nbody\n\n"
            "# Please enter the commit message for your changes.\n")
    (git-issue-insert-trailer "fixes" "a1b2c3d")
    (git-issue-insert-trailer "closes" "b2c3d4e")
    (goto-char (point-min))
    (should (search-forward "body\n\nFixes: #a1b2c3d\nCloses: #b2c3d4e\n" nil t))
    ;; and still before the comment block git strips
    (should (search-forward "# Please enter" nil t))))

(defun magit-git-issue-test--trailer-into (message kind id)
  "MESSAGE with the KIND trailer for ID inserted, as a string."
  (with-temp-buffer
    (setq-local comment-start "#")
    (insert message)
    (git-issue-insert-trailer kind id)
    (buffer-substring-no-properties (point-min) (point-max))))

(ert-deftest magit-git-issue-insert-trailer-ignores-a-comment-in-the-body ()
  "Only the *last* run of comment lines is the block Git strips.
Walking back to the earliest `#' line put the trailer above a `# Design'
heading the body happened to contain."
  (should (equal (magit-git-issue-test--trailer-into
                  "subject\n\n# Design\nkeep the parser out of the UI\n\n\
# Please enter the commit message for your changes.\n"
                  "fixes" "a1b2c3d")
                 "subject\n\n# Design\nkeep the parser out of the UI\n\n\
Fixes: #a1b2c3d\n\n# Please enter the commit message for your changes.\n")))

(ert-deftest magit-git-issue-insert-trailer-separates-prose-shaped-like-one ()
  "A prose line that merely looks like a trailer still gets a blank line.
Git reads the last paragraph as trailers only when the whole paragraph
is trailers, so `Note: see below' does not make one."
  (should (equal (magit-git-issue-test--trailer-into
                  "subject\n\nsome prose\nNote: see below\n"
                  "fixes" "a1b2c3d")
                 "subject\n\nsome prose\nNote: see below\n\nFixes: #a1b2c3d\n")))

(ert-deftest magit-git-issue-insert-trailer-stacks-under-a-trailer ()
  "A message ending in a real trailer paragraph takes the new one directly."
  (should (equal (magit-git-issue-test--trailer-into
                  "subject\n\nbody\n\nSigned-off-by: x <x@example.invalid>\n"
                  "fixes" "a1b2c3d")
                 "subject\n\nbody\n\nSigned-off-by: x <x@example.invalid>\n\
Fixes: #a1b2c3d\n")))

(ert-deftest magit-git-issue-insert-trailer-into-an-empty-message ()
  "An empty message opens no blank line above the trailer."
  (should (equal (magit-git-issue-test--trailer-into
                  "\n# Please enter the commit message for your changes.\n"
                  "fixes" "a1b2c3d")
                 "Fixes: #a1b2c3d\n\n\
# Please enter the commit message for your changes.\n")))

(ert-deftest magit-git-issue-insert-trailer-reads-kind-and-id ()
  (magit-git-issue-test--with-repo
    (let ((a (git-issue-create "alpha task")))
      (with-temp-buffer
        (setq-local comment-start "#")
        (insert "subject")
        (cl-letf (((symbol-function 'completing-read) (lambda (&rest _) "issue"))
                  ((symbol-function 'git-issue-read-id) (lambda (&rest _) a)))
          (call-interactively #'git-issue-insert-trailer))
        (should (string-suffix-p (format "Issue: #%s\n" a) (buffer-string)))))))

(provide 'magit-git-issue-test)
;;; magit-git-issue-test.el ends here
