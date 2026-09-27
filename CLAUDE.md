# Amber Circles: rules for agents working here

Read README.md first for what this is. These are the rules that each cost something to learn.

## Before any UI change

- Read DENY.md. The stance is editorial and its refusals are enforced by `test/deny.test.js`. The first build passed ux-lint and still looked generated, because the linter scores the absence of tells and nothing scored the stance.
- Render what you changed and look at it at 1280 and 390 wide. Run ux-engine's `design-gate <url> --shots 3` and read the whole output, not a grep of it. On 2026-09-27 a filtered grep hid a failing verdict.
- The page CSP forbids inline `style=""` attributes. Add a class to `public/app.css` instead. Inline styles fail silently: spacing just disappears.

## Security rules that are tested

- A tool is untrusted model output. Never widen the frame CSP, never add `allow-same-origin` to the iframe sandbox, and never pass a phone number or token into the frame.
- Anything a tool's buttons hide must also be refused by the server. Removal was once UI-only, and any member could delete anyone's entry from the console.
- Secrets travel after `#`, never in a query string.

## Working rules

- Every bug fix gets a test that fails on the old code. Prove it by running the test against a mutant copy of the server on another port.
- The tests clean up the owners they create. Keep it that way, because they also run against production.
- A build spends real money, about 19 cents for a new tool at Opus 5 list price. Do not loop builds in tests; the flows tests use `PUT /api/tools/:slug` instead.
- Deploy with `railway up --service web --detach`, then run `AMBER_URL=<prod> npm test`.
