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
  (should (featurep 'transient))
  (should (featurep 'with-editor)))

(ert-deftest magit-git-issue-does-not-duplicate-the-core ()
  "The UI file must not run processes or parse porcelain itself."
  (let ((source (with-temp-buffer
                  (insert-file-contents
                   (locate-library "magit-git-issue.el" t))
                  (buffer-string))))
    (dolist (forbidden '("call-process" "start-process" "shell-command"
                         "process-lines" "git-issue-parse"))
      (should-not (string-match-p (regexp-quote forbidden) source)))))

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
  "A broken CLI reports itself; it does not abort the status refresh."
  (magit-git-issue-test--with-repo
    (let ((git-issue-program "git-issue-does-not-exist"))
      (with-current-buffer (magit-status-setup-buffer default-directory)
        (goto-char (point-min))
        (should (search-forward "Recent commits" nil t))))))

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
        (goto-char (point-min))
        (cl-letf (((symbol-function 'git-issue-read-id) (lambda (&rest _) "zzzzzzz")))
          (magit-git-issue-comment))
        (insert "carefully composed\ntext")
        (let ((err (should-error
                    (call-interactively (key-binding (kbd "C-c C-c")))
                    :type 'user-error)))
          (should (string-match-p "not found" (cadr err))))
        (let ((buffer (get-buffer "*git-issue edit*")))
          (should buffer)
          (with-current-buffer buffer
            (should (equal (buffer-substring-no-properties (point-min) (point-max))
                           "carefully composed\ntext"))
            ;; The same buffer can be finished again once the cause is gone.
            (setq magit-git-issue--edit-callback
                  (lambda (text) (git-issue-comment a text)))
            (call-interactively (key-binding (kbd "C-c C-c")))))
        (should-not (get-buffer "*git-issue edit*"))
        (should (equal (caddr (car (git-issue-detail-comments
                                    (git-issue-show a))))
                       "carefully composed\ntext"))))))

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
