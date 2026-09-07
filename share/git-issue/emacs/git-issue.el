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

(provide 'git-issue)
;;; git-issue.el ends here
