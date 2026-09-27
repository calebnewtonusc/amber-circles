# DENY.md

**What Amber Circles refuses.** Rewritten 2026-09-27 after Caleb looked at the
editorial version and called it AI slop: "the font the italics the layout,
everything". He was right, and the reason is specific. A serif display face
with one gold italic phrase, an uppercase tracked kicker over every heading,
and thin outline buttons on a flat grey page is now the median generated
"tasteful" page. It passed every check we had, because every check scored the
absence of the old tells and the look had become the new one.
`test/deny.test.js` enforces every line below that a regex can see.

## The real constraint

The person making a tool may be in their seventies. The people opening it tap
a link in a text, on a phone, often with reading glasses somewhere else.
A hackathon judge gives the landing page five seconds. Both need the same
thing: to know what to press without reading.

## The one mechanism

**The circle is the permission, and it arrives as a text.** So the page shows
people by name and face everywhere a generic product says "users", the landing
page shows the actual text message a group receives, and the tools page shows
each tool as itself, a live thumbnail, the way Google Docs shows pages.

## Stance

`material` (ux-engine `tools/stances.py`): flat blocks of colour with hard
edges and hard offset shadows, like printed signage. Signage is the one
visual tradition built for people reading at a glance, at a distance, without
their glasses, which is exactly this audience.

## Type

Atkinson Hyperlegible Next and Atkinson Hyperlegible Mono, drawn by the
Braille Institute for readers with low vision: the I, l and 1 differ, the 0
and O differ, and the counters stay open at small sizes. One family, carried
by size and weight. Body text is 18px, never smaller than 15px anywhere.

## Forbidden

- No italic anywhere. Instead: weight and size carry emphasis.
- No serif. Instead: one hyperlegible family at several weights.
- No uppercase kicker above a heading. Instead: the heading says it alone.
- No gradient of any kind. Instead: flat blocks of paper, sheet, ink and amber.
- No blurred or soft shadow. Instead: a hard 4px offset in ink, on things you can press or open.
- No outline-only primary button. Instead: a solid amber block with an ink border, which reads as a button to anyone.
- No radius above 4px, except 50% for people. Instead: square blocks, 4px on inputs.
- No pill shape on anything. Instead: square blocks.
- No second accent hue. Instead: amber, with green and red only to mean present and error.
- No amber on anything you cannot tap. Instead: amber means press this, everywhere, so a person learns it once. Decoration is ink, paper or sheet.
- No grey hairline doing structural work. Instead: 2px ink rules, visible from arm's length.
- No text under 15px. Instead: 18px body, 16px for the smallest labels.

## Motion, declared per element

| Element                             | Class      | Spec                                                                    |
| ----------------------------------- | ---------- | ----------------------------------------------------------------------- |
| Landing headline, lede, form, phone | SPAWN      | reading order, 60ms step, 4 items so 180ms, 12px travel, 260ms ease-out |
| Landing text thread                 | STATE-SWAP | one message appears every 1.4s, opacity only, then it resets            |
| Buttons and tiles                   | press      | hover lifts the shadow to 6px, press drops it to 0 and moves 4px, 90ms  |
| Everything else                     | STATIC     |                                                                         |

Reduced motion keeps the thread's content and drops all travel.

## What this costs

Hard shadows and 2px rules are loud, so there can only be one amber block per
screen that means "press this", or the page shouts. The landing page trades
the quiet-luxury read for a road-sign read, on purpose: the user is Grandpa,
not a design critic.
