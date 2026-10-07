;;; prinbox.el --- The pull requests waiting on you  -*- lexical-binding: t; -*-

;; Author: creeonix
;; Version: 0.7.0
;; Package-Requires: ((emacs "29.1"))
;; URL: https://github.com/creeonix/prinbox
;; Keywords: tools, vc

;; This file is not part of GNU Emacs.

;;; Commentary:

;; A `tabulated-list' buffer over the `prinbox' command: the pull requests waiting on you in six sections.
;; RET opens one in the browser, `s' snoozes it until something happens on it, `u' wakes it, `g' refreshes,
;; `q' buries the buffer.  `prinbox-mode-line-mode' shows the count in the mode line.
;;
;; Install the command first (`brew install creeonix/tap/prinbox-cli', signed in with `gh auth login'), then:
;;
;;   (use-package prinbox
;;     :vc (:url "https://github.com/creeonix/prinbox" :rev :newest)
;;     :commands (prinbox prinbox-mode-line-mode))
;;
;; or (package-vc-install "https://github.com/creeonix/prinbox").  See docs/emacs.md in that repository.
;; The package reads only what the command prints: titles, logins, URLs, counts and dates, never comment text.

;;; Code:

(require 'tabulated-list)
(require 'browse-url)
(require 'iso8601)
(require 'seq)
(require 'subr-x)

(defgroup prinbox nil
  "The pull requests waiting on you, through the prinbox command."
  :group 'tools
  :prefix "prinbox-")

(defcustom prinbox-command "prinbox"
  "The prinbox executable."
  :type 'string)

(defcustom prinbox-max-age 60
  "Serve the cache when GitHub confirmed it within this many seconds.
0 fetches now."
  :type 'integer)

(defcustom prinbox-poll-seconds 0
  "Refresh this often in the background for the mode line; 0 turns polling off."
  :type 'integer)

(defface prinbox-section '((t :inherit font-lock-keyword-face :weight bold))
  "The section column.")

(defface prinbox-new '((t :weight bold))
  "A row new since the last look at the popover.")

(defface prinbox-snoozed '((t :inherit shadow))
  "A snoozed row.")

(defface prinbox-message '((t :inherit warning))
  "A message shown in place of rows.")

(defconst prinbox--install "prinbox not found: brew install creeonix/tap/prinbox-cli"
  "What to say when the command is missing.")

(defvar prinbox--last nil
  "The last report that held a document: a plist (:document DOC :message MSG).")

(defvar prinbox--failed nil
  "Non-nil when the latest inbox run produced no document.")

(defvar-local prinbox--report nil
  "The report the buffer shows.")

(defvar prinbox--timer nil
  "The poll timer of `prinbox-mode-line-mode'.")

(defvar prinbox-mode-line-string ""
  "The count for the mode line, as `prinbox inbox --format tmux' prints it.")
(put 'prinbox-mode-line-string 'risky-local-variable t)

;;;; The command

(defun prinbox--decode (text)
  "Parse TEXT as the inbox document (an alist), or nil."
  (condition-case nil
      (let ((value (json-parse-string text :object-type 'alist :array-type 'list
                                      :null-object nil :false-object nil)))
        (and (listp value) value))
    (error nil)))

(defun prinbox--report (code stdout stderr)
  "Turn the exit CODE, STDOUT and STDERR of an inbox run into a report plist."
  (let* ((document (prinbox--decode stdout))
         (err (string-trim-right (or stderr "")))
         (version (and document (alist-get 'version document))))
    (cond
     ((and document (not (eql version 1)))
      (list :message (format "prinbox prints JSON version %s; this plugin reads version 1" version)))
     ((eql code 0)
      (if document (list :document document) (list :message "prinbox printed something that is not JSON")))
     ((eql code 1)
      (list :document document
            :message (or (alist-get 'message (alist-get 'error document)) err)))
     ((eql code 3)
      (list :document document :setup t
            :message (if (string-empty-p err) "prinbox needs setup: gh auth login" err)))
     ((eql code 127) (list :message prinbox--install))
     (t (list :message (if (string-empty-p err) (format "prinbox exited with %s" code) err))))))

(defun prinbox--process (args interpret callback)
  "Run the command with ARGS and call CALLBACK when it exits.
CALLBACK receives what INTERPRET makes of the exit code, stdout and stderr."
  (let ((stdout (generate-new-buffer " *prinbox-stdout*"))
        (stderr (generate-new-buffer " *prinbox-stderr*")))
    (condition-case nil
        (make-process
         :name "prinbox" :buffer stdout :stderr stderr :noquery t :connection-type 'pipe
         :command (cons prinbox-command args)
         :sentinel
         (lambda (process _event)
           (when (memq (process-status process) '(exit signal))
             ;; Bounded: a grandchild holding stderr open must not freeze Emacs (sentinels inhibit quit).
             (let ((errp (get-buffer-process stderr))
                   (deadline (+ (float-time) 1.0)))
               (while (and errp (process-live-p errp) (< (float-time) deadline))
                 (accept-process-output errp 0.05))
               (when (and errp (process-live-p errp))
                 (delete-process errp)))
             (let ((code (process-exit-status process))
                   (out (with-current-buffer stdout (buffer-string)))
                   (err (with-current-buffer stderr (buffer-string))))
               (kill-buffer stdout)
               (kill-buffer stderr)
               (funcall callback (funcall interpret code out err))))))
      (file-error
       (kill-buffer stdout)
       (kill-buffer stderr)
       (funcall callback (funcall interpret 127 "" ""))))))

(defun prinbox--remember (report)
  "Keep REPORT when it holds a document and refresh the mode line.
Note whether it did, for `prinbox--count'."
  (when (plist-get report :document) (setq prinbox--last report))
  (setq prinbox--failed (null (plist-get report :document)))
  (setq prinbox-mode-line-string (prinbox--count))
  (force-mode-line-update t))

(defun prinbox--inbox (args callback)
  "Run `prinbox inbox --format json' with ARGS and call CALLBACK with the report."
  (prinbox--process (append (list "inbox" "--format" "json") args) #'prinbox--report
                    (lambda (report) (prinbox--remember report) (funcall callback report))))

(defun prinbox--count ()
  "The count as `--format tmux' spells it.
The badge, nothing when idle, `!' first after a failure: a document with an
error, or a run that printed no document (then the last known badge follows)."
  (let* ((document (plist-get prinbox--last :document))
         (badge (or (alist-get 'badge document) 0))
         (text (if (> badge 0) (number-to-string badge) "")))
    (if (or prinbox--failed (alist-get 'error document)) (concat "!" text) text)))

;;;; The buffer

(defun prinbox--rows (document)
  "Every row of DOCUMENT with its section, in display order: (SECTION . ROW)."
  (let (rows)
    (dolist (section (alist-get 'sections document))
      (dolist (row (alist-get 'rows section))
        (push (cons section row) rows)))
    (nreverse rows)))

(defun prinbox--flatten (text)
  "TEXT with control characters turned into spaces."
  (replace-regexp-in-string "[[:cntrl:]]+" " " (or text "")))

(defun prinbox--flags (row)
  "The flags column of ROW."
  (let ((stack (alist-get 'stack row)))
    (string-join
     (delq nil (list (and (alist-get 'isNew row) "new")
                     (and (alist-get 'isDraft row) "draft")
                     (and (alist-get 'snoozed row) "snoozed")
                     (and stack (format "stack %s/%s" (alist-get 'position stack) (alist-get 'size stack)))))
     " ")))

(defun prinbox--hhmm (iso)
  "HH:MM in local time for the ISO 8601 date ISO."
  (format-time-string "%H:%M" (encode-time (iso8601-parse iso))))

(defun prinbox--header (report)
  "The header line for REPORT."
  (let ((document (plist-get report :document))
        (message (plist-get report :message)))
    (if (not document)
        (or message "prinbox")
      (let ((parts (list (format "%d waiting on you" (or (alist-get 'badge document) 0)))))
        (when-let* ((at (alist-get 'checkedAt document)))
          (push (concat "updated " (prinbox--hhmm at)) parts))
        (when (> (or (alist-get 'newCount document) 0) 0)
          (push (format "%d new" (alist-get 'newCount document)) parts))
        (when-let* ((repositories (alist-get 'defaultRepositories document)))
          (push (string-join repositories ", ") parts))
        (when message
          (push (car (split-string message "\n")) parts))
        (string-join (nreverse parts) " · ")))))

(defun prinbox--entries (report)
  "The `tabulated-list-entries' for REPORT: the rows, or the message's lines.
The message's lines show when there are no rows, and in place of the rows
when setup is needed."
  (let* ((document (plist-get report :document))
         (rows (and document (not (plist-get report :setup)) (prinbox--rows document)))
         entries)
    (if (and (null rows) (plist-get report :message))
        (let ((index 0))
          (dolist (line (split-string (plist-get report :message) "\n"))
            (setq index (1+ index))
            (push (list (format "message-%d" index)
                        (vector "" "" (propertize line 'face 'prinbox-message) "" "" "" ""))
                  entries)))
      (dolist (section (alist-get 'sections document))
        (dolist (row (alist-get 'rows section))
          (push (prinbox--row-entry section row) entries))
        (when (> (or (alist-get 'moreCount section) 0) 0)
          (push (prinbox--more-entry section) entries))))
    (nreverse entries)))

(defun prinbox--row-entry (section row)
  "The entry for ROW of SECTION."
  (let ((face (cond ((alist-get 'snoozed row) 'prinbox-snoozed)
                    ((alist-get 'isNew row) 'prinbox-new)
                    (t 'default))))
    (list (alist-get 'id row)
          (vector (propertize (alist-get 'title section) 'face 'prinbox-section)
                  (propertize (number-to-string (alist-get 'number row)) 'face face)
                  (propertize (prinbox--flatten (alist-get 'title row)) 'face face)
                  (propertize (alist-get 'repository row) 'face face)
                  (propertize (alist-get 'reasonText row) 'face face)
                  (propertize (alist-get 'age row) 'face face)
                  (prinbox--flags row)))))

(defun prinbox--more-entry (section)
  "The `+N more on GitHub' entry of the capped SECTION."
  (list (format "more-%s" (alist-get 'kind section))
        (vector (propertize (alist-get 'title section) 'face 'prinbox-section)
                ""
                (propertize (format "+%d more on GitHub" (alist-get 'moreCount section))
                            'face 'prinbox-message)
                "" "" "" "")))

(defvar-keymap prinbox-mode-map
  :doc "Keys of `prinbox-mode'."
  :parent tabulated-list-mode-map
  "RET" #'prinbox-open
  "s" #'prinbox-snooze
  "u" #'prinbox-unsnooze
  "g" #'prinbox-refresh)

(define-derived-mode prinbox-mode tabulated-list-mode "prinbox"
  "The pull requests waiting on you."
  (setq tabulated-list-format
        [("Section" 18 nil) ("#" 6 nil :right-align t) ("Title" 48 nil) ("Repository" 20 nil)
         ("Reason" 20 nil) ("Age" 5 nil) ("Flags" 12 nil)])
  (setq tabulated-list-padding 1)
  (setq tabulated-list-sort-key nil)
  (setq-local revert-buffer-function #'prinbox--revert)
  ;; The column titles print as the buffer's first line: the header line holds the summary.
  (setq-local tabulated-list-use-header-line nil)
  (tabulated-list-init-header))

(defun prinbox--buffer ()
  "The *prinbox* buffer."
  (get-buffer-create "*prinbox*"))

(defun prinbox--render (report)
  "Show REPORT in the buffer."
  (with-current-buffer (prinbox--buffer)
    (unless (derived-mode-p 'prinbox-mode) (prinbox-mode))
    (setq prinbox--report report)
    (setq header-line-format (prinbox--header report))
    (setq tabulated-list-entries (prinbox--entries report))
    (tabulated-list-print t)))

;;;###autoload
(defun prinbox ()
  "Show the pull requests waiting on you: the cache at once, then a refresh."
  (interactive)
  (pop-to-buffer (prinbox--buffer))
  (prinbox--inbox '("--cached")
                  (lambda (report)
                    (prinbox--render report)
                    (prinbox--inbox (list "--max-age" (number-to-string prinbox-max-age))
                                    #'prinbox--render))))

(defun prinbox-refresh ()
  "Fetch now and show the result when the buffer exists."
  (interactive)
  (prinbox--inbox nil (lambda (report) (when (get-buffer "*prinbox*") (prinbox--render report)))))

(defun prinbox--revert (&rest _)
  "The `revert-buffer-function': a refresh."
  (prinbox-refresh))

(defun prinbox--current-row ()
  "The row at point, or nil on a message line or a more line."
  (let ((id (tabulated-list-get-id)))
    (and id (not (string-prefix-p "message-" id)) (not (string-prefix-p "more-" id))
         (cdr (seq-find (lambda (item) (equal (alist-get 'id (cdr item)) id))
                        (prinbox--rows (plist-get prinbox--report :document)))))))

(defun prinbox--current-more ()
  "The section whose more line is at point, or nil."
  (when-let* ((id (tabulated-list-get-id))
              ((string-prefix-p "more-" id)))
    (seq-find (lambda (section) (equal (format "more-%s" (alist-get 'kind section)) id))
              (alist-get 'sections (plist-get prinbox--report :document)))))

(defun prinbox-open ()
  "Open the pull request at point in the browser.
On a more line, open the section's page on GitHub."
  (interactive)
  (if-let* ((row (prinbox--current-row)))
      (browse-url (alist-get 'url row))
    (when-let* ((section (prinbox--current-more)))
      (browse-url (alist-get 'moreUrl section)))))

(defun prinbox--act (verb)
  "Run `prinbox VERB <id>' for the row at point, then re-read the cache."
  (when-let* ((row (prinbox--current-row)))
    (prinbox--process
     (list verb (alist-get 'id row))
     (lambda (code _out err)
       (list :ok (eql code 0)
             :message (string-trim (string-remove-prefix "prinbox: " (string-trim err)))))
     (lambda (result)
       (if (plist-get result :ok)
           (prinbox--inbox '("--cached") #'prinbox--render)
         (message "prinbox: %s" (plist-get result :message)))))))

(defun prinbox-snooze ()
  "Snooze the pull request at point until something happens on it."
  (interactive)
  (prinbox--act "snooze"))

(defun prinbox-unsnooze ()
  "Wake the snoozed pull request at point."
  (interactive)
  (prinbox--act "unsnooze"))

;;;; The mode line

(defun prinbox--mode-line ()
  "The mode-line segment."
  (if (string-empty-p prinbox-mode-line-string) "" (format " PR:%s" prinbox-mode-line-string)))

(defun prinbox--poll ()
  "A background refresh for the count.
It serves the cache up to `prinbox-poll-seconds' old."
  (prinbox--inbox (list "--max-age" (number-to-string (max prinbox-poll-seconds prinbox-max-age)))
                  (lambda (report) (when (get-buffer "*prinbox*") (prinbox--render report)))))

;;;###autoload
(define-minor-mode prinbox-mode-line-mode
  "Show the prinbox count in the mode line, refreshed every `prinbox-poll-seconds'."
  :global t
  (when prinbox--timer
    (cancel-timer prinbox--timer)
    (setq prinbox--timer nil))
  (unless (listp global-mode-string)
    (setq global-mode-string (list global-mode-string)))
  (cond
   (prinbox-mode-line-mode
    (add-to-list 'global-mode-string '(:eval (prinbox--mode-line)) t)
    (prinbox--poll)
    (when (> prinbox-poll-seconds 0)
      (setq prinbox--timer (run-with-timer prinbox-poll-seconds prinbox-poll-seconds #'prinbox--poll))))
   (t
    (setq global-mode-string (delete '(:eval (prinbox--mode-line)) global-mode-string)))))

(provide 'prinbox)
;;; prinbox.el ends here
