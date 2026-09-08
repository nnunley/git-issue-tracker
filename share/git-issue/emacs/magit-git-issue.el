;;; magit-git-issue.el --- Magit interface for git-issue  -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1") (magit "4.0") (transient "0.7"))
;; Keywords: tools, vc

;;; Commentary:
;; The magit user interface specified by draft-ndn-magit-integration-00.
;; Every process call and every parse lives in `git-issue'; this file only
;; renders the structs it returns as magit sections and moves point around.
;;
;; Loading this file adds `magit-git-issue-insert-issues' to
;; `magit-status-sections-hook' after the stashes section, appends
;; `magit-git-issue-dispatch' to `magit-dispatch' on `x', and appends three
;; trailer options to `magit-commit'.  All three go through the documented
;; magit and transient entry points, so `remove-hook' and
;; `transient-remove-suffix' take them back out again.

;;; Code:

(require 'eieio)
(require 'seq)
(require 'subr-x)

(require 'git-issue)
(require 'magit)
(require 'git-commit)
(require 'transient)

(defgroup magit-git-issue nil
  "Magit interface for git-issue."
  :group 'git-issue
  :group 'magit-extensions)

(defcustom magit-git-issue-status-section 'ready
  "Which issues `magit-git-issue-insert-issues' lists.
`ready' shows the issues `git issue ready' selects, that is the work
that is not blocked.  `open' shows every issue whose status is not
closed."
  :type '(choice (const :tag "Ready work" ready)
                 (const :tag "All open issues" open))
  :group 'magit-git-issue)

(defface magit-git-issue-id
  '((t :inherit magit-hash))
  "Face for the issue id at the start of an issue line."
  :group 'magit-git-issue)

(defface magit-git-issue-repo
  '((t :inherit magit-branch-remote))
  "Face for the repository name prefixed to an issue line."
  :group 'magit-git-issue)

(defface magit-git-issue-blocked
  '((t :inherit magit-dimmed))
  "Face for the title of an issue that is blocked."
  :group 'magit-git-issue)

;;;; Issue lines

(defun magit-git-issue--error-message (err)
  "The message carried by `git-issue-error' ERR.
`git-issue-run' guarantees it is plain text, escape sequences and all
stripped, so it goes to the echo area as it is."
  (or (cadr err) ""))

(defun magit-git-issue--issues-for-section ()
  "The issues `magit-git-issue-status-section' selects."
  (pcase magit-git-issue-status-section
    ('open (seq-remove (lambda (issue)
                         (equal (git-issue-issue-status issue) "closed"))
                       (git-issue-list)))
    (_ (git-issue-ready))))

(defun magit-git-issue--insert-issue-line (issue &optional with-repo)
  "Insert one `git-issue' section for ISSUE.
The line is `<id> <status> <priority> <title>', prefixed with the
repository name when WITH-REPO is non-nil and ISSUE carries one."
  (magit-insert-section (git-issue issue)
    (let ((repo (and with-repo (git-issue-issue-repo issue))))
      (when repo
        (insert (propertize repo 'font-lock-face 'magit-git-issue-repo) " ")))
    (insert (propertize (git-issue-issue-id issue)
                        'font-lock-face 'magit-git-issue-id)
            " "
            (git-issue-issue-status issue)
            " "
            (git-issue-issue-priority issue)
            " ")
    (let ((title (git-issue-issue-title issue)))
      (insert (if (equal (git-issue-issue-status issue) "blocked")
                  (propertize title 'font-lock-face 'magit-git-issue-blocked)
                title)))
    (insert "\n")))

(defun magit-git-issue--insert-issues (issues &optional with-repo)
  "Insert one section line per issue in ISSUES, passing WITH-REPO along."
  (dolist (issue issues)
    (magit-git-issue--insert-issue-line issue with-repo)))

;;;; Status buffer section

;;;###autoload
(defun magit-git-issue-insert-issues ()
  "Insert the git-issue section into the magit status buffer.
Which issues it lists is the user option
`magit-git-issue-status-section'.  A failing CLI is reported in the
echo area rather than aborting the whole status refresh."
  (condition-case err
      (when-let* ((issues (magit-git-issue--issues-for-section)))
        (magit-insert-section (git-issues)
          (magit-insert-heading
            (format "Issues (%s)" magit-git-issue-status-section))
          (magit-git-issue--insert-issues issues)
          (insert "\n")))
    (git-issue-error (message "git-issue: %s" (magit-git-issue--error-message err)))
    ;; `call-process' signals a `file-error' subtype when the program
    ;; cannot be run at all: `file-missing' when it is not on PATH,
    ;; `permission-denied' when it is not executable, and a bare
    ;; `file-error' for a directory or a broken interpreter line.  None of
    ;; those may take the whole status refresh down with them.
    (file-error
     (message "git-issue: cannot run %s: %s"
              git-issue-program (error-message-string err)))))

;; Added through `magit-add-section-hook' so `remove-hook' takes it back out.
(magit-add-section-hook 'magit-status-sections-hook
                        #'magit-git-issue-insert-issues
                        #'magit-insert-stashes
                        'append)

;;;; The issue at point

(defun magit-git-issue-issue-at-point ()
  "The `git-issue-issue' of the section at point, or nil."
  (when-let* ((section (magit-current-section))
              ((eq (oref section type) 'git-issue)))
    (oref section value)))

(defun magit-git-issue--repo-directory (issue)
  "The registered directory ISSUE lives in, or nil when it names no repo.
Signals a `user-error' when the repo column names a repository that
`git issue repo list' does not know."
  (when-let* ((name (git-issue-issue-repo issue)))
    (let ((path (cdr (assoc name (git-issue-repo-paths)))))
      (unless path
        (user-error "Repository `%s' is not registered" name))
      (file-name-as-directory path))))

(defun magit-git-issue-visit ()
  "Open a detail buffer for the issue at point.
When the line carries a repository name, the detail buffer runs with
`default-directory' set to that repository's registered path."
  (interactive)
  (let ((issue (magit-git-issue-issue-at-point)))
    (unless issue
      (user-error "No issue at point"))
    (let ((default-directory (or (magit-git-issue--repo-directory issue)
                                 default-directory)))
      (magit-git-issue-show (git-issue-issue-id issue)))))

;; Magit finds this by name: a section of type `git-issue' gets the keymap
;; named `magit-git-issue-section-map', so RET works in the status buffer
;; as well as in the list buffers.
(defvar magit-git-issue-section-map
  (let ((map (make-sparse-keymap)))
    (define-key map [remap magit-visit-thing] #'magit-git-issue-visit)
    map)
  "Keymap for sections of type `git-issue'.")

;;;; List and ready buffers

(defvar magit-git-issue-list-mode-map
  (let ((map (make-sparse-keymap)))
    (set-keymap-parent map magit-mode-map)
    (define-key map (kbd "RET") #'magit-git-issue-visit)
    map)
  "Keymap for `magit-git-issue-list-mode'.")

(define-derived-mode magit-git-issue-list-mode magit-mode "Issues"
  "Major mode for a list of git-issue issues.

\\<magit-git-issue-list-mode-map>\
Type \\[magit-refresh] to refresh the buffer, \
\\[magit-git-issue-visit] to open the issue at point.

\\{magit-git-issue-list-mode-map}"
  :interactive nil
  :group 'magit-git-issue
  (magit-hack-dir-local-variables))

(defvar-local magit-git-issue--list-command 'list
  "Which listing this buffer shows: the symbol `list' or `ready'.")

(defvar-local magit-git-issue--list-all nil
  "Non-nil when this buffer lists every registered repository.")

(defun magit-git-issue-list-refresh-buffer ()
  "Refresh a `magit-git-issue-list-mode' buffer.
Called by `magit-refresh-buffer' through the name of the major mode."
  (let ((all magit-git-issue--list-all)
        (ready (eq magit-git-issue--list-command 'ready)))
    (magit-set-header-line-format
     (format "git issue %s%s" (if ready "ready" "list") (if all " --all" "")))
    (magit-insert-section (git-issues)
      (magit-insert-heading
        (format "%s issues%s" (if ready "Ready" "All") (if all " (all repositories)" "")))
      (magit-git-issue--insert-issues
       (if ready (git-issue-ready all) (git-issue-list all))
       all))))

(defun magit-git-issue--setup-list-buffer (command all)
  "Open a list buffer for COMMAND (`list' or `ready'), across ALL repos."
  (magit-setup-buffer #'magit-git-issue-list-mode nil
    (magit-git-issue--list-command command)
    (magit-git-issue--list-all (and all t))))

;;;###autoload
(defun magit-git-issue-list (&optional all)
  "List the issues of this repository.
With a prefix argument ALL, list every registered repository's issues
and prefix each line with the repository name."
  (interactive "P")
  (magit-git-issue--setup-list-buffer 'list all))

;;;###autoload
(defun magit-git-issue-ready (&optional all)
  "List the ready issues of this repository.
With a prefix argument ALL, list every registered repository's ready
issues and prefix each line with the repository name."
  (interactive "P")
  (magit-git-issue--setup-list-buffer 'ready all))

;;;; Detail buffer

(define-derived-mode magit-git-issue-show-mode magit-mode "Issue"
  "Major mode for the detail of one git-issue issue.

\\<magit-mode-map>\
Type \\[magit-refresh] to refresh the buffer from the CLI.

\\{magit-git-issue-show-mode-map}"
  :interactive nil
  :group 'magit-git-issue
  (magit-hack-dir-local-variables))

(defvar-local magit-git-issue--show-id nil
  "The id of the issue this detail buffer shows.")

(cl-defmethod magit-buffer-value (&context (major-mode magit-git-issue-show-mode))
  magit-git-issue--show-id)

(defun magit-git-issue--insert-headers (detail)
  "Insert the fields of DETAIL as a headers section."
  (magit-insert-section (headers)
    (magit-insert-heading "Headers")
    (pcase-dolist (`(,key . ,value) (git-issue-detail-fields detail))
      (magit-insert-section (git-issue-field key)
        (insert (propertize (format "%s:" key) 'font-lock-face 'magit-section-heading)
                " " value "\n")))
    (insert "\n")))

(defun magit-git-issue--insert-description (detail)
  "Insert the description of DETAIL verbatim, when it has one."
  (when-let* ((description (git-issue-detail-description detail))
              ((not (string-empty-p description))))
    (magit-insert-section (description)
      (magit-insert-heading "Description")
      (insert description)
      (unless (string-suffix-p "\n" description)
        (insert "\n"))
      (insert "\n"))))

(defun magit-git-issue--insert-comments (detail)
  "Insert one section per comment of DETAIL."
  (dolist (comment (git-issue-detail-comments detail))
    (pcase-let ((`(,timestamp ,author ,text) comment))
      (magit-insert-section (comment comment)
        (magit-insert-heading
          (if (and timestamp author)
              (format "[%s] %s" timestamp author)
            "comment"))
        (insert text)
        (unless (string-suffix-p "\n" text)
          (insert "\n"))
        (insert "\n")))))

(defun magit-git-issue-show-refresh-buffer ()
  "Refresh a `magit-git-issue-show-mode' buffer.
Called by `magit-refresh-buffer' through the name of the major mode."
  (let ((detail (git-issue-show magit-git-issue--show-id)))
    (magit-set-header-line-format (format "issue %s" magit-git-issue--show-id))
    (magit-insert-section (git-issue-detail magit-git-issue--show-id)
      (magit-git-issue--insert-headers detail)
      (magit-git-issue--insert-description detail)
      (magit-git-issue--insert-comments detail))))

;;;###autoload
(defun magit-git-issue-show (id)
  "Show issue ID in a `magit-git-issue-show-mode' buffer."
  (interactive (list (git-issue-read-id "Show issue: ")))
  (magit-setup-buffer #'magit-git-issue-show-mode nil
    (magit-git-issue--show-id id)))

;;;; Vocabularies

(defcustom magit-git-issue-priorities
  '("low" "medium" "high" "critical")
  "Priorities `magit-git-issue-set-priority' completes over.
The CLI validates against exactly this fixed list, so the prompt
requires a match."
  :type '(repeat string)
  :group 'magit-git-issue)

(defcustom magit-git-issue-statuses
  '("open" "in_progress" "review" "blocked" "deferred" "closed")
  "Statuses `magit-git-issue-set-status' completes over.
These are the ones the shipped status machine defines.  A repository
can define its own in `.git-issue/statuses', so the prompt offers
these as completions without requiring a match."
  :type '(repeat string)
  :group 'magit-git-issue)

(defcustom magit-git-issue-dependency-types
  '("blocks" "depends_on" "parent_of" "relates_to")
  "Edge types `git issue dep add' and `dep rm' accept."
  :type '(repeat string)
  :group 'magit-git-issue)

(defun magit-git-issue--field-values (accessor)
  "Distinct non-empty values of ACCESSOR across the issues of this repo.
Used to offer completion for fields the CLI does not constrain."
  (delete-dups
   (seq-remove #'string-empty-p
               (delq nil (mapcar accessor (ignore-errors (git-issue-list)))))))

;;;; Actions

(defun magit-git-issue--id (&optional prompt)
  "The id of the issue at point, else one read with PROMPT."
  (let ((issue (magit-git-issue-issue-at-point)))
    (if issue
        (git-issue-issue-id issue)
      (git-issue-read-id (or prompt "Issue: ")))))

(defmacro magit-git-issue--define-action (name doc prompt &rest body)
  "Define interactive command NAME with docstring DOC.
The issue at point, or one read with PROMPT, is bound to `id' while
BODY runs.  A `git-issue-error' from BODY becomes a `user-error'
carrying the CLI's message; success refreshes the magit buffers."
  (declare (indent 3) (doc-string 2))
  `(defun ,name ()
     ,doc
     (interactive)
     (let ((id (magit-git-issue--id ,prompt)))
       (condition-case err
           (progn ,@body (magit-refresh))
         (git-issue-error (user-error "git-issue: %s" (magit-git-issue--error-message err)))))))

(magit-git-issue--define-action magit-git-issue-start
    "Move the issue at point into progress." "Start issue: "
  (git-issue-start id))

(magit-git-issue--define-action magit-git-issue-close
    "Close the issue at point." "Close issue: "
  (git-issue-close id))

(magit-git-issue--define-action magit-git-issue-reopen
    "Reopen the issue at point." "Reopen issue: "
  (git-issue-reopen id))

;; `git-issue-update' interpolates the field name into `--<field>=', so
;; these names have to be the CLI's own flag names.
(magit-git-issue--define-action magit-git-issue-set-status
    "Set the status of the issue at point." "Set status of issue: "
  (git-issue-update id "status"
                    (completing-read "Status: " magit-git-issue-statuses)))

(magit-git-issue--define-action magit-git-issue-set-priority
    "Set the priority of the issue at point." "Set priority of issue: "
  (git-issue-update id "priority"
                    (completing-read "Priority: " magit-git-issue-priorities
                                     nil t)))

(magit-git-issue--define-action magit-git-issue-set-assignee
    "Set the assignee of the issue at point." "Set assignee of issue: "
  (git-issue-update id "assignee"
                    (completing-read
                     "Assignee: "
                     (magit-git-issue--field-values #'git-issue-issue-assignee))))

(magit-git-issue--define-action magit-git-issue-set-role
    "Set the role of the issue at point." "Set role of issue: "
  (git-issue-update id "role"
                    (completing-read
                     "Role: "
                     (magit-git-issue--field-values #'git-issue-issue-role))))

(magit-git-issue--define-action magit-git-issue-dep-add
    "Add a dependency edge leaving the issue at point." "Edge from issue: "
  (git-issue-dep-add id
                     (completing-read "Type: " magit-git-issue-dependency-types
                                      nil t)
                     (git-issue-read-id "To issue: ")))

(magit-git-issue--define-action magit-git-issue-dep-rm
    "Remove a dependency edge leaving the issue at point." "Edge from issue: "
  (git-issue-dep-rm id
                    (completing-read "Type: " magit-git-issue-dependency-types
                                     nil t)
                    (git-issue-read-id "To issue: ")))

(magit-git-issue--define-action magit-git-issue-link
    "Link the issue at point to a commit." "Link issue: "
  (git-issue-link id (or (magit-commit-at-point)
                         (magit-read-branch-or-commit "Link to commit"))))

;;;; Multi-line input

;; The spec requires `C-c C-c' to finish and `C-c C-k' to abort, matching
;; magit's commit message buffer.  There is no editor process to drive
;; here -- the text goes straight into an argument -- so this is a small
;; major mode following those key conventions, and `with-editor' is not a
;; dependency of this package.

(defvar-local magit-git-issue--edit-callback nil
  "Function called with the buffer text when the edit buffer is finished.")

(defvar-local magit-git-issue--edit-winconf nil
  "Window configuration to restore when the edit buffer is done.")

(defvar magit-git-issue-edit-mode-map
  (let ((map (make-sparse-keymap)))
    (define-key map (kbd "C-c C-c") #'magit-git-issue-edit-finish)
    (define-key map (kbd "C-c C-k") #'magit-git-issue-edit-abort)
    map)
  "Keymap for `magit-git-issue-edit-mode'.")

(define-derived-mode magit-git-issue-edit-mode text-mode "Git-Issue-Edit"
  "Major mode for composing git-issue text.

\\<magit-git-issue-edit-mode-map>\
Type \\[magit-git-issue-edit-finish] to use the text, \
\\[magit-git-issue-edit-abort] to abort.

\\{magit-git-issue-edit-mode-map}"
  :group 'magit-git-issue)

(defun magit-git-issue--edit-text (title callback)
  "Pop to an edit buffer titled TITLE; call CALLBACK with its text.
CALLBACK runs in the buffer that was current when this was called, so
that `default-directory' and `magit-refresh' still mean the right
thing.

Each composition gets a buffer of its own: starting a second comment
while a first is unfinished must not silently discard the first, and a
rejected submission stays in its buffer until it is finished or
aborted."
  (let ((buffer (generate-new-buffer "*git-issue edit*"))
        (directory default-directory)
        (origin (current-buffer))
        (winconf (current-window-configuration)))
    (with-current-buffer buffer
      (magit-git-issue-edit-mode)
      (setq default-directory directory)
      (setq magit-git-issue--edit-winconf winconf)
      (setq magit-git-issue--edit-callback
            (lambda (text)
              (if (buffer-live-p origin)
                  (with-current-buffer origin (funcall callback text))
                ;; The buffer we were invoked from is gone; keep the
                ;; repository the composition belongs to.
                (let ((default-directory directory))
                  (funcall callback text)))))
      (setq header-line-format
            (concat title
                    (substitute-command-keys
                     "   \\[magit-git-issue-edit-finish] to finish, \
\\[magit-git-issue-edit-abort] to abort"))))
    (pop-to-buffer buffer)))

(defun magit-git-issue--edit-quit ()
  "Kill the edit buffer and restore the window configuration."
  (let ((winconf magit-git-issue--edit-winconf))
    (kill-buffer (current-buffer))
    (when winconf
      (set-window-configuration winconf))))

(defun magit-git-issue-edit-finish ()
  "Finish the edit buffer and hand its text to the pending action.
The action runs first and the buffer is only killed once it succeeds,
so a comment the CLI rejects leaves the composed text in place to fix
and retry, the way magit's commit buffer survives a failed commit."
  (interactive)
  (unless magit-git-issue--edit-callback
    (user-error "Not in a git-issue edit buffer"))
  (funcall magit-git-issue--edit-callback
           (buffer-substring-no-properties (point-min) (point-max)))
  (magit-git-issue--edit-quit))

(defun magit-git-issue-edit-abort ()
  "Abort the edit buffer without running the pending action."
  (interactive)
  (magit-git-issue--edit-quit)
  (message "Aborted"))

(defun magit-git-issue-comment ()
  "Comment on the issue at point, composing the text in a buffer."
  (interactive)
  (let ((id (magit-git-issue--id "Comment on issue: ")))
    (magit-git-issue--edit-text
     (format "Comment on #%s" id)
     (lambda (text)
       (when (string-blank-p text)
         (user-error "Empty comment; nothing added"))
       (condition-case err
           (progn (git-issue-comment id text) (magit-refresh))
         (git-issue-error (user-error "git-issue: %s" (magit-git-issue--error-message err))))))))

(defun magit-git-issue-create ()
  "Create an issue: the title in the minibuffer, the description in a buffer.
An empty description buffer creates the issue with a title only."
  (interactive)
  (let ((title (read-string "Title: ")))
    (when (string-blank-p title)
      (user-error "An issue needs a title"))
    (magit-git-issue--edit-text
     (format "Description for %S (leave empty to skip)" title)
     (lambda (text)
       (condition-case err
           (let ((id (git-issue-create
                      title (and (not (string-blank-p text)) text))))
             (message "Created issue #%s" id)
             (magit-refresh))
         (git-issue-error (user-error "git-issue: %s" (magit-git-issue--error-message err))))))))

;;;; The dispatch transient

;;;###autoload (autoload 'magit-git-issue-dispatch "magit-git-issue" nil t)
(transient-define-prefix magit-git-issue-dispatch ()
  "Act on git-issue issues.
Every action uses the issue at point when there is one and prompts
for an id with completion otherwise."
  [["Issue at point"
    ("s" "Start"          magit-git-issue-start)
    ("c" "Close"          magit-git-issue-close)
    ("o" "Reopen"         magit-git-issue-reopen)
    ("m" "Comment"        magit-git-issue-comment)
    ("l" "Link to commit" magit-git-issue-link)]
   ["Set"
    ("S" "Status"   magit-git-issue-set-status)
    ("p" "Priority" magit-git-issue-set-priority)
    ("a" "Assignee" magit-git-issue-set-assignee)
    ("r" "Role"     magit-git-issue-set-role)]
   ["Dependencies"
    ("d" "Add edge"    magit-git-issue-dep-add)
    ("D" "Remove edge" magit-git-issue-dep-rm)]
   ["Browse"
    ("n" "New issue" magit-git-issue-create)
    ("L" "List"      magit-git-issue-list)
    ("R" "Ready"     magit-git-issue-ready)
    ("RET" "Show"    magit-git-issue-show)]])

(defun magit-git-issue--anchor (prefix keys)
  "The first of KEYS that names an existing suffix of transient PREFIX."
  (or (seq-find (lambda (key)
                  (ignore-errors (transient-get-suffix prefix key)))
                keys)
      (error "magit-git-issue: no anchor in `%s' among %S" prefix keys)))

;; Appended, not redefined, so `transient-remove-suffix' undoes it.
(transient-append-suffix 'magit-dispatch
  (magit-git-issue--anchor 'magit-dispatch '("!" "Q" "z"))
  '("x" "Issues" magit-git-issue-dispatch))

;; `x' is `magit-reset-quickly' in `magit-mode-map'; the spec puts the
;; issue transient on it in the status buffer, where reset-quickly stays
;; reachable through `X' and `magit-dispatch'.
(define-key magit-status-mode-map (kbd "x") #'magit-git-issue-dispatch)
(define-key magit-git-issue-list-mode-map (kbd "x") #'magit-git-issue-dispatch)
(define-key magit-git-issue-show-mode-map (kbd "x") #'magit-git-issue-dispatch)

;;;; Commit trailers

(defclass magit-git-issue--trailer-option (transient-option)
  ((kind :initarg :kind
         :documentation "Trailer kind passed to `git-issue-format-trailer'."))
  "A `magit-commit' option whose value is an issue id.
Its `transient-infix-value' is the pair of git arguments that writes
the trailer, not the option string itself.")

(defun magit-git-issue--read-trailer-id (obj)
  "Read an issue id for trailer option OBJ, or nil to unset it.
An option that already carries an id reads as nil, so pressing its key
a second time clears it.  Kept out of the `transient-infix-read' method
because transient wraps that generic in an `:around' method that only
works inside a live transient, and this is the part worth testing."
  (and (not (and (slot-boundp obj 'value) (oref obj value)))
       (git-issue-read-id
        (format "%s issue: " (capitalize (oref obj kind))))))

(cl-defmethod transient-infix-read ((obj magit-git-issue--trailer-option))
  "Read an issue id for OBJ, or unset it when it already has one."
  (magit-git-issue--read-trailer-id obj))

(cl-defmethod transient-infix-value ((obj magit-git-issue--trailer-option))
  "The git arguments OBJ contributes: (\"--trailer\" \"Key: #id\") or nil."
  (and-let* (((slot-boundp obj 'value))
             (id (oref obj value)))
    (git-issue-trailer-args (oref obj kind) id)))

(transient-define-infix magit-git-issue:--fixes ()
  :class 'magit-git-issue--trailer-option
  :kind "fixes"
  :description "Fixes issue"
  :key "-x"
  :argument "--fixes=")

(transient-define-infix magit-git-issue:--closes ()
  :class 'magit-git-issue--trailer-option
  :kind "closes"
  :description "Closes issue"
  :key "-X"
  :argument "--closes=")

(transient-define-infix magit-git-issue:--issue ()
  :class 'magit-git-issue--trailer-option
  :kind "issue"
  :description "References issue"
  :key "-i"
  :argument "--issue=")

;; Inserted in reverse so they read fixes, closes, issue top to bottom.
(let ((anchor (magit-git-issue--anchor 'magit-commit '("-C" "-R" "-n" "-a"))))
  (transient-append-suffix 'magit-commit anchor '(magit-git-issue:--issue))
  (transient-append-suffix 'magit-commit anchor '(magit-git-issue:--closes))
  (transient-append-suffix 'magit-commit anchor '(magit-git-issue:--fixes)))

;;;###autoload
(defun git-issue-insert-trailer (kind id)
  "Insert the KIND trailer for issue ID at the end of the commit message.
The message ends where the trailing comment block that Git strips
begins, so the trailer lands there and not after the comments.  A
blank line is opened first unless the message already ends in a
trailer, which is what makes Git parse the line as one."
  (interactive
   (list (completing-read "Trailer: " (mapcar #'car git-issue-trailer-keys)
                          nil t)
         (git-issue-read-id "Issue: ")))
  (let ((line (git-issue-format-trailer kind id))
        (comment-re (concat "^" (regexp-quote (or comment-start "#")))))
    (save-excursion
      ;; Skip any leading comment block; the message starts after it.
      (goto-char (point-min))
      (while (and (not (eobp)) (looking-at-p comment-re))
        (forward-line))
      (let ((body-start (point)))
        ;; Walk back to the first line of the trailing comment block.
        (goto-char (point-max))
        (while (re-search-backward comment-re body-start t))
        (skip-chars-backward "\n" body-start)
        (cond
          ((= (point) body-start))      ; empty message: no leading blank
          ((save-excursion
             (beginning-of-line)
             (looking-at-p "[A-Za-z][A-Za-z-]*: "))
           (insert "\n"))               ; stack under the existing trailers
          (t (insert "\n\n")))
        (insert line)
        (unless (and (not (eobp)) (eq (char-after) ?\n))
          (insert "\n"))))))

(define-key git-commit-mode-map (kbd "C-c C-x") #'git-issue-insert-trailer)

(provide 'magit-git-issue)
;;; magit-git-issue.el ends here
