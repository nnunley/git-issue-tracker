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
(require 'seq)
(require 'subr-x)

(defgroup git-issue nil
  "Git-native issue tracking with git-issue."
  :group 'tools)

(defcustom git-issue-program "git-issue"
  "Program run for every git-issue operation."
  :type 'string)

(define-error 'git-issue-error "git-issue failed")

(defconst git-issue-silent-failure-message
  "git-issue failed without writing a diagnostic"
  "Message of `git-issue-error' when the CLI fails and says nothing.
A nonzero exit with both streams empty is a bug in the CLI -- every
read command exits 0 on an empty result per R-plain-stdout -- so this
gives such a failure a name rather than an empty message.  The exit
status is the second element of the error data.")

(defconst git-issue--escape-sequence-regexp
  "\e\\[[0-9;?]*[@-~]\\|\e][^\a\e]*\\(?:\a\\|\e\\\\\\)\\|\e[@-Z\\\\-_]"
  "Terminal escape sequences the CLI may leave in a diagnostic.
CSI (the SGR colours it prints), OSC, and the two-character escapes.")

(defun git-issue--plain (string)
  "STRING with terminal escape sequences removed.
The CLI colours its diagnostics whether or not it is on a tty, and
`git-issue-error' data is contractually plain text."
  (string-trim (replace-regexp-in-string git-issue--escape-sequence-regexp
                                         "" string t t)))

(defun git-issue-run (&rest args)
  "Run `git-issue-program' with --porcelain and ARGS in `default-directory'.
Return standard output as a string.  On nonzero exit signal
`git-issue-error' whose data is the standard error, falling back to
standard output for the subcommands that report failure there and to
`git-issue-silent-failure-message' when the CLI says nothing at all.
The message is always plain text: any terminal escape sequence the CLI
left in it is stripped here, so callers can display it as it is."
  (let ((err-file (make-temp-file "git-issue-stderr")))
    (unwind-protect
        (with-temp-buffer
          (let* ((status (apply #'call-process git-issue-program nil
                                (list t err-file) nil "--porcelain" args))
                 (out (git-issue--plain (buffer-string))))
            (if (eql status 0)
                (buffer-string)
              (let ((err (git-issue--plain
                          (with-temp-buffer
                            (insert-file-contents err-file)
                            (buffer-string)))))
                (signal 'git-issue-error
                        (cond ((not (string-empty-p err)) (list err))
                              ((not (string-empty-p out)) (list out))
                              (t (list git-issue-silent-failure-message
                                       status))))))))
      (delete-file err-file))))

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

;;;; Commands

(defun git-issue-list (&optional all)
  "Issues of the current repository, or of every registered one when ALL."
  (git-issue-parse-issue-lines
   (apply #'git-issue-run "list" (and all '("--all")))))

(defun git-issue-ready (&optional all)
  "Ready issues, or across every registered repository when ALL.
An empty result is the empty list: `git issue ready --porcelain' exits
0 with no output when nothing is ready, per R-plain-stdout."
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

(defun git-issue-repo-paths ()
  "Registered repositories as an alist of (NAME . PATH).
Parses the `repo list' contract lines `<name> <path>', where a path
that no longer exists is followed by the marker ` (missing)'.  The
marker is dropped; the recorded path is returned either way."
  (mapcar (lambda (line)
            (let* ((space (string-search " " line))
                   (name (if space (substring line 0 space) line))
                   (rest (if space (substring line (1+ space)) "")))
              (cons name
                    (if (string-suffix-p " (missing)" rest)
                        (substring rest 0 (- (length rest)
                                             (length " (missing)")))
                      rest))))
          (git-issue--nonblank-lines (git-issue-run "repo" "list"))))

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

(provide 'git-issue)
;;; git-issue.el ends here
