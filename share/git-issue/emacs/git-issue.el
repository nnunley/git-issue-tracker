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
