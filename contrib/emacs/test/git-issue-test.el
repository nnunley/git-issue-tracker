;;; git-issue-test.el --- ERT for the git-issue core  -*- lexical-binding: t; -*-
(require 'ert)
(require 'cl-lib)
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

(ert-deftest git-issue-run-falls-back-to-stdout ()
  ;; Some subcommands have reported failure on stdout rather than stderr;
  ;; the fallback keeps the message either way.
  (let ((default-directory (git-issue-test--scratch-repo)))
    (let ((err (should-error (git-issue-run "comment" "zzzzzzz" "hi")
                             :type 'git-issue-error)))
      (should (string-match-p "not found" (cadr err))))))

(ert-deftest git-issue-error-data-is-plain-text ()
  "Error data carries no terminal escape sequence, whatever the CLI printed."
  (let ((default-directory (git-issue-test--scratch-repo)))
    (dolist (command '(("comment" "zzzzzzz" "hi")
                       ("show" "zzzzzzz")
                       ("link" "zzzzzzz" "HEAD")
                       ("update" "zzzzzzz" "--priority=high")))
      (let ((err (should-error (apply #'git-issue-run command)
                               :type 'git-issue-error)))
        (should (string-match-p "not found" (cadr err)))
        (should-not (string-match-p "\e" (cadr err)))))))

(ert-deftest git-issue-plain-strips-escape-sequences ()
  (should (equal (git-issue--plain "\e[0;31mError: nope\e[0m") "Error: nope"))
  (should (equal (git-issue--plain "  plain  ") "plain"))
  (should (equal (git-issue--plain "") "")))

(ert-deftest git-issue-run-always-signals-something ()
  (let ((git-issue-program "false")
        (default-directory (git-issue-test--scratch-repo)))
    (let ((err (should-error (git-issue-run "list") :type 'git-issue-error)))
      (should (equal (cadr err) git-issue-silent-failure-message))
      (should (equal (caddr err) 1)))))

(ert-deftest git-issue-ready-is-empty-when-nothing-is-ready ()
  ;; No workaround here on purpose: `ready --porcelain' exits 0 with no
  ;; output when nothing is ready (R-plain-stdout), so this passes only
  ;; while the CLI keeps that contract.  It regressed once.
  (let ((default-directory (git-issue-test--scratch-repo)))
    (should (null (git-issue-ready)))
    (let ((a (git-issue-create "alpha task")))
      (should (equal (mapcar #'git-issue-issue-id (git-issue-ready)) (list a)))
      (git-issue-close a)
      (should (null (git-issue-ready))))))

(ert-deftest git-issue-ready-signals-real-failures ()
  (let ((default-directory (git-issue-test--scratch-repo)))
    ;; An unknown flag is a real failure and must still signal.
    (should-error (git-issue-run "ready" "--nonsense")
                  :type 'git-issue-error)))

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
  ;; `link_issue' in bin/git-issue stores the link as a comment
  ;; "Linked to commit: <short-hash>" using `git rev-parse --short', not
  ;; the full commit id, so assert on the short hash it actually records.
  (let* ((default-directory (git-issue-test--scratch-repo))
         (a (git-issue-create "alpha task"))
         (head (string-trim (with-output-to-string
                              (call-process "git" nil standard-output nil "rev-parse" "HEAD"))))
         (short (string-trim (with-output-to-string
                               (call-process "git" nil standard-output nil "rev-parse" "--short" "HEAD")))))
    (git-issue-link a head)
    (should (string-match-p (regexp-quote short) (git-issue-run "show" a)))))

(ert-deftest git-issue-repo-paths-parses-registry-lines ()
  ;; `repo list' prints "<name> <path>" and appends " (missing)" when the
  ;; path is gone; the marker must not end up in the parsed path.
  (cl-letf (((symbol-function 'git-issue-run)
             (lambda (&rest _)
               "tracker /home/u/tracker\ngone /home/u/old repo (missing)\n")))
    (should (equal (git-issue-repo-paths)
                   '(("tracker" . "/home/u/tracker")
                     ("gone" . "/home/u/old repo"))))))

(ert-deftest git-issue-repo-paths-round-trips-through-the-cli ()
  (let* ((home (file-name-as-directory (make-temp-file "git-issue-home" t)))
         (process-environment (cons (concat "HOME=" home) process-environment))
         (default-directory (git-issue-test--scratch-repo)))
    (should (null (git-issue-repo-paths)))
    (git-issue-run "repo" "add" "scratch" ".")
    (let ((paths (git-issue-repo-paths)))
      (should (equal (mapcar #'car paths) '("scratch")))
      (should (file-directory-p (cdar paths))))))

(ert-deftest git-issue-trailers ()
  (should (equal (git-issue-format-trailer "fixes" "a1b2c3d") "Fixes: #a1b2c3d"))
  (should (equal (git-issue-format-trailer "related-to" "a1b2c3d") "Related-To: #a1b2c3d"))
  (should (equal (git-issue-trailer-args "closes" "a1b2c3d") '("--trailer" "Closes: #a1b2c3d")))
  (should-error (git-issue-format-trailer "bogus" "a1b2c3d") :type 'git-issue-error))

(provide 'git-issue-test)
;;; git-issue-test.el ends here
