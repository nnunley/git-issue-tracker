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

(provide 'git-issue-test)
;;; git-issue-test.el ends here
