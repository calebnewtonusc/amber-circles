# DENY.md

**What Amber Circles refuses.** Declared before the restyle on 2026-09-27,
after the first build drifted to the median look: soft 16px cards, pill
buttons, a gradient mesh, filled tag bubbles. `ux-lint` called that page clean,
because it scores the absence of tells and nothing scored the stance.
`test/deny.test.js` enforces every line below that a regex can see.

## The real constraint

Two readers, both in a hurry. A student opens a tool from a text between
classes, on a phone, for ten seconds. A hackathon judge gives the landing page
five. And it has to read as Amber, a real company with its own system
(Classical: `amber-ios/apps/mobile/design-reference/classical-readme.md`), not
as a weekend project.

## The one mechanism

**The circle is the permission.** Every link knows who opened it. So the
interface shows people by name everywhere a generic product would say "users",
and the landing page proves it by showing a circle filling in, name by name.

## Stance

`editorial` (ux-engine `tools/stances.py`), which is also what Amber's own
Classical system already is: serif display, hairline rules, colour as stroke.

## Forbidden

- No gradient of any kind. Instead: flat paper ground, structure from 1px hairline rules.
- No radius above 4px. Instead: 4px on controls, 0 on rules and tables. Avatars are the one circle, because a person is round.
- No blurred or soft drop shadow. Instead: a 1px hairline border, and elevation only from the ground being a step darker than the sheet.
- No filled button. Instead: a 1px gold outline, tinted on hover and press only. Classical: "the primary is an accent outline, never a fill".
- No pill shape on anything. Instead: 4px, or plain text with an underline.
- No icon in a coloured bubble. Instead: the icon inline at text size, in the text's own colour.
- No second hue. Instead: gold 700 for the one accent, green and red only to mean present and error.
- No weight above 600. Instead: size carries hierarchy; display sets at 400, the bigger the lighter.
- No centred hero and no equal-width card grid. Instead: a left column that reads like a page, and a ruled ledger for lists.
- No uppercase except the tracked 11px kicker. Instead: sentence case everywhere else.

## Motion, declared per element

| Element                                            | Class      | Spec                                                                          |
| -------------------------------------------------- | ---------- | ----------------------------------------------------------------------------- |
| Landing kicker, headline, lede, form, margin notes | SPAWN      | reading order, 50ms step, 5 items so 200ms total, 12px travel, 260ms ease-out |
| Landing ledger of a circle                         | STATE-SWAP | one name checks in every 1.6s, the count steps, then it resets. No travel     |
| Buttons                                            | press      | `scale(0.98)` 110ms ease-out down, 160ms up. Hover colour 120ms               |
| Everything else                                    | STATIC     |                                                                               |

Reduced motion keeps the fades and the state swap's content, and drops all travel.

## What this costs

Outlined buttons carry less pop than a filled one, so the single primary action
on each screen has to win on size and position instead. The flat ground reads
plainer in a thumbnail. A judge skimming for "polish" in the SaaS sense will
not find glass or glow, on purpose.

## Suppressions

- House rule "no flat background without treatment": the treatment here is the
  hairline grid, not a gradient, because the stance forbids gradients and
  Amber's own system does not use them.
- House rule "Inter or Geist": Amber's shipped families are Newsreader and
  Outfit (`apps/mobile/lib/tokens.ts`). A product's own type beats a house default.
