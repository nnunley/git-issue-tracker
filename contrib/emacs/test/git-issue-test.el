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
