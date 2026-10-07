;;; prinbox-test.el --- Tests for prinbox.el  -*- lexical-binding: t; -*-

;;; Commentary:

;; Run by Tests/Adapters/run.sh in batch Emacs against the stub command: every command runs asynchronously, so
;; each step pumps the process loop until the buffer shows what it waits for.

;;; Code:

(require 'ert)
(require 'cl-lib)
(require 'seq)
(require 'prinbox)

(defvar prinbox-test--root
  (expand-file-name "../../.." (file-name-directory (or load-file-name buffer-file-name)))
  "The repository root.")

(defvar prinbox-test--stub (expand-file-name "Tests/Adapters/bin/prinbox" prinbox-test--root)
  "The stub command.")

(defvar prinbox-test--log (make-temp-file "prinbox-stub-log")
  "Where the stub records its calls.")

(defvar prinbox-test--opened nil
  "URLs handed to `browse-url'.")

(defun prinbox-test--wait (predicate)
  "Pump the process loop until PREDICATE holds or five seconds pass; fail if it never holds."
  (let ((deadline (+ (float-time) 5)))
    (while (and (not (funcall predicate)) (< (float-time) deadline))
      (accept-process-output nil 0.05))
    (should (funcall predicate))))

(defun prinbox-test--log-lines ()
  "The stub's log, one call per line."
  (with-temp-buffer
    (insert-file-contents prinbox-test--log)
    (split-string (buffer-string) "\n" t)))

(defun prinbox-test--reset ()
  "Point the package at the stub and start from nothing.
A run left over from the previous test finishes first, so its log line and its
count cannot leak into this one."
  (prinbox-test--wait
   (lambda () (not (seq-some (lambda (process) (and (string-prefix-p "prinbox" (process-name process))
                                                     (process-live-p process)))
                             (process-list)))))
  (accept-process-output nil 0.05) ; the last sentinel runs
  (setq prinbox-command prinbox-test--stub)
  (setenv "PRINBOX_STUB_LOG" prinbox-test--log)
  (setenv "PRINBOX_STUB_EXIT" nil)
  (setenv "PRINBOX_STUB_VERSION" nil)
  (with-temp-file prinbox-test--log (insert ""))
  (when (get-buffer "*prinbox*") (kill-buffer "*prinbox*"))
  (setq prinbox-test--opened nil)
  (setq prinbox--last nil)
  (setq prinbox--failed nil)
  (setq prinbox-mode-line-string ""))

(defun prinbox-test--entries ()
  "The entries the buffer shows."
  (with-current-buffer "*prinbox*" tabulated-list-entries))

(defun prinbox-test--cell (entry column)
  "Text of COLUMN in ENTRY, without properties."
  (substring-no-properties (aref (cadr entry) column)))

(defun prinbox-test--wait-for-rows ()
  "Wait until the demo rows are shown."
  (prinbox-test--wait (lambda () (and (get-buffer "*prinbox*") (> (length (prinbox-test--entries)) 10)))))

(ert-deftest prinbox-test-lists-sections-and-rows-in-order ()
  "The buffer lists every row under its section, in the document's order."
  (prinbox-test--reset)
  (prinbox)
  (prinbox-test--wait (lambda () (>= (length (prinbox-test--log-lines)) 2)))
  (prinbox-test--wait-for-rows)
  (with-current-buffer "*prinbox*"
    (should (derived-mode-p 'prinbox-mode))
    (should (string-match-p "^8 waiting on you · updated [0-9][0-9]:[0-9][0-9] · 4 new$" header-line-format))
    (should (equal (length tabulated-list-entries) 17))
    (let ((first (car tabulated-list-entries)) (last (car (last tabulated-list-entries))))
      (should (equal (car first) "DEMO_1290"))
      (should (equal (prinbox-test--cell first 0) "Needs your review"))
      (should (equal (prinbox-test--cell first 2) "Migrate the settings page to the new design system"))
      (should (equal (prinbox-test--cell first 6) "stack 1/2"))
      (should (equal (car last) "DEMO_1284"))
      (should (equal (prinbox-test--cell last 0) "Waiting on others"))
      (should (equal (prinbox-test--cell last 6) "snoozed")))
    (should (equal (prinbox--count) "8"))))

(ert-deftest prinbox-test-ret-opens-and-s-u-run-the-command ()
  "RET opens the row's URL; s and u run the command, then re-read the cache."
  (prinbox-test--reset)
  (prinbox)
  (prinbox-test--wait-for-rows)
  ;; Both inbox runs (the cache, then the refresh) finish before the log is cleared.
  (prinbox-test--wait (lambda () (>= (length (prinbox-test--log-lines)) 2)))
  (with-current-buffer "*prinbox*"
    (goto-char (point-min))
    (cl-letf (((symbol-function 'browse-url) (lambda (url &rest _) (push url prinbox-test--opened))))
      (prinbox-open))
    (should (equal prinbox-test--opened '("https://github.com/acme/web/pull/1290")))
    (with-temp-file prinbox-test--log (insert ""))
    (forward-line 1)
    (prinbox-snooze)
    (prinbox-test--wait (lambda () (= (length (prinbox-test--log-lines)) 2)))
    (should (equal (prinbox-test--log-lines) '("snooze DEMO_1291" "inbox json")))
    (prinbox-unsnooze)
    (prinbox-test--wait (lambda () (= (length (prinbox-test--log-lines)) 4)))
    (should (equal (nth 2 (prinbox-test--log-lines)) "unsnooze DEMO_1291"))))

(ert-deftest prinbox-test-errors-are-shown ()
  "Each failure shows its text, and the count turns to `!' with the last badge."
  (prinbox-test--reset)
  (setenv "PRINBOX_STUB_EXIT" "3")
  (prinbox)
  (prinbox-test--wait
   (lambda () (and (get-buffer "*prinbox*")
                   (with-current-buffer "*prinbox*" (string-match-p "gh auth login" (buffer-string))))))
  (with-current-buffer "*prinbox*"
    (should (string-prefix-p "0 waiting on you" header-line-format))
    (should (equal (prinbox--count) "!")))
  (setenv "PRINBOX_STUB_EXIT" "1")
  (prinbox-refresh)
  (prinbox-test--wait
   (lambda () (with-current-buffer "*prinbox*"
                (string-match-p "^8 waiting on you.*· GitHub did not answer in time$" header-line-format))))
  (should (equal (length (prinbox-test--entries)) 17))
  (should (equal (prinbox--count) "!8"))
  (setenv "PRINBOX_STUB_EXIT" nil)
  (setenv "PRINBOX_STUB_VERSION" "2")
  (prinbox-refresh)
  (prinbox-test--wait
   (lambda () (with-current-buffer "*prinbox*"
                (equal header-line-format "prinbox prints JSON version 2; this plugin reads version 1"))))
  (should (equal (prinbox--count) "!8"))
  (setenv "PRINBOX_STUB_VERSION" nil)
  (setq prinbox-command (expand-file-name "Tests/Adapters/bin/no-such-prinbox" prinbox-test--root))
  (prinbox-refresh)
  (prinbox-test--wait
   (lambda () (with-current-buffer "*prinbox*" (equal header-line-format prinbox--install))))
  (should (equal (prinbox--count) "!8")))

(ert-deftest prinbox-test-count-follows-every-run ()
  "A run that prints no document turns a healthy count into `!' and the last badge."
  (prinbox-test--reset)
  (prinbox--remember (list :document '((version . 1) (badge . 8))))
  (should (equal (prinbox--count) "8"))
  (prinbox--remember (list :message prinbox--install))
  (should (equal (prinbox--count) "!8"))
  (should (equal prinbox-mode-line-string "!8"))
  (prinbox--remember (list :message "prinbox prints JSON version 2; this plugin reads version 1"))
  (should (equal (prinbox--count) "!8"))
  (prinbox--remember (list :document '((version . 1) (badge . 8))))
  (should (equal (prinbox--count) "8")))

(ert-deftest prinbox-test-more-line-opens-the-section-page ()
  "A capped section ends with its more line, which opens the section's page."
  (prinbox-test--reset)
  (let* ((row '((id . "x") (number . 7) (title . "T") (repository . "acme/web")
                (reasonText . "Review requested") (age . "1h") (url . "https://example.test/7")))
         (section `((kind . "needsReview") (title . "Needs your review") (count . 3) (moreCount . 2)
                    (moreUrl . "https://example.test/more") (rows . (,row))))
         (document `((version . 1) (badge . 3) (sections . (,section)))))
    (prinbox--render (list :document document)))
  (with-current-buffer "*prinbox*"
    (should (equal (length tabulated-list-entries) 2))
    (let ((more (nth 1 tabulated-list-entries)))
      (should (equal (car more) "more-needsReview"))
      (should (equal (prinbox-test--cell more 2) "+2 more on GitHub")))
    (goto-char (point-min))
    (forward-line 1)
    (should (equal (tabulated-list-get-id) "more-needsReview"))
    (cl-letf (((symbol-function 'browse-url) (lambda (url &rest _) (push url prinbox-test--opened))))
      (prinbox-open))
    (should (equal prinbox-test--opened '("https://example.test/more")))
    (prinbox-snooze)
    (accept-process-output nil 0.3)
    (should (equal (prinbox-test--log-lines) nil))))

(ert-deftest prinbox-test-setup-replaces-the-rows ()
  "Exit 3 shows the setup steps in place of the rows, even cached ones."
  (let* ((row '((id . "DEMO_1290") (number . 1290) (title . "Migrate the settings page")
                (repository . "acme/web") (reasonText . "Review requested") (age . "2d")))
         (document `((version . 1) (badge . 1)
                     (sections ((kind . "needsReview") (title . "Needs your review") (rows ,row)))))
         (report (list :document document :message "Sign in to the GitHub CLI\n     gh auth login" :setup t))
         (entries (prinbox--entries report)))
    (should (equal (length entries) 2))
    (should (cl-every (lambda (entry) (string-prefix-p "message-" (car entry))) entries))
    (should (equal (mapcar (lambda (entry) (prinbox-test--cell entry 2)) entries)
                   '("Sign in to the GitHub CLI" "     gh auth login")))))

(ert-deftest prinbox-test-report-maps-the-exit-codes ()
  "Every exit code maps to its report."
  (should (equal (plist-get (prinbox--report 0 "{\"version\":1,\"badge\":2}" "") :document)
                 '((version . 1) (badge . 2))))
  (should (equal (prinbox--report 0 "not json" "") '(:message "prinbox printed something that is not JSON")))
  (should (equal (plist-get (prinbox--report 1 "{\"version\":1,\"error\":{\"message\":\"Offline\"}}" "") :message)
                 "Offline"))
  (should (equal (plist-get (prinbox--report 3 "" "Sign in\n") :message) "Sign in"))
  (should (equal (prinbox--report 127 "" "") (list :message prinbox--install)))
  (should (equal (prinbox--report 2 "" "prinbox: unknown option\n") '(:message "prinbox: unknown option")))
  (should (equal (prinbox--report 0 "{\"version\":2}" "")
                 '(:message "prinbox prints JSON version 2; this plugin reads version 1"))))

(ert-deftest prinbox-test-mode-line-mode-polls ()
  "The minor mode adds the count to the mode line and takes it out again."
  (prinbox-test--reset)
  (let ((prinbox-poll-seconds 1))
    (prinbox-mode-line-mode 1)
    (prinbox-test--wait (lambda () (equal prinbox-mode-line-string "8")))
    (should (member '(:eval (prinbox--mode-line)) global-mode-string))
    (should (equal (prinbox--mode-line) " PR:8"))
    (prinbox-mode-line-mode -1)
    (should-not (member '(:eval (prinbox--mode-line)) global-mode-string))))

(provide 'prinbox-test)
;;; prinbox-test.el ends here
