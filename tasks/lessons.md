# Lessons

## 2026-09-29: never send global synthetic keystrokes during UI verification

What happened: while verifying the popover's keyboard handling, `osascript -e 'tell application
"System Events" to key code 125/36'` was sent after opening the popover via an AX press. macOS
refused to activate the accessory app for a synthetic press, so Brave stayed frontmost and received
Down + Return while the user was working in it. An approval appeared on a work PR seconds later; the
user confirmed they submitted it themselves, so this was a near miss, not damage. The keystrokes still
went to an app the user was using.

Rules:
- Never use System Events `keystroke` / `key code` (or any global input injection) in a session where
  the user is working. Input goes to whatever is frontmost, not to the app under test.
- Before any UI automation, check the frontmost process and stop if it is not the app under test.
- Prefer targeted AX actions on the app's own elements (AXPress on a specific element) or ask the user
  to perform keyboard checks themselves.
- Treat the user's browser, mail and chat apps as live production systems.
