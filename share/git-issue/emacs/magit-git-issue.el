;;; magit-git-issue.el --- Magit interface for git-issue  -*- lexical-binding: t; -*-

;; Package-Requires: ((emacs "28.1") (magit "4.0") (transient "0.7") (with-editor "3.0"))
;; Keywords: tools, vc

;;; Commentary:
;; The magit user interface specified by draft-ndn-magit-integration-00.
;; Every process call and every parse lives in `git-issue'; this file only
;; renders the structs it returns as magit sections and moves point around.
;;
;; Loading this file adds `magit-git-issue-insert-issues' to
;; `magit-status-sections-hook' after the stashes section.  Remove it with
;; `remove-hook' to get the plain status buffer back.

;;; Code:

(require 'eieio)
(require 'seq)
(require 'subr-x)

(require 'git-issue)
(require 'magit)
(require 'transient)
(require 'with-editor)

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
    (git-issue-error (message "git-issue: %s" (cadr err)))
    ;; No git-issue on PATH at all: stay out of the status buffer's way.
    (file-missing nil)))

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

(provide 'magit-git-issue)
;;; magit-git-issue.el ends here
