# Vibe coding vs Google Docs: what to copy for Amber Circles

Researched 2026-09-27. Reddit blocks automated fetching, so Reddit sentiment reaches this file through Trustpilot, Hacker News, press coverage and vendor docs. Treat the ranking as a judgment over those sources, not a count.

## 1. What hurts non-developers in today's AI app builders

Ranked by how often it recurs, then by how badly it hurts someone who cannot read code.

**1. The fix loop, and paying for it.** Every edit risks breaking something that worked, and every repair attempt costs credits. On Hacker News, tezza describes Bolt as "a cycle of breakage, each 'fix' resurrecting a previous 'break'" ([HN](https://news.ycombinator.com/item?id=44513404)). Another commenter's advice is to never fix at all: "revert and try with an updated prompt. the context seems to get polluted otherwise" (same thread). Lovable reviewers report "just spending credits to fix and update...all apps are not working!" ([Trustpilot](https://www.trustpilot.com/review/lovable.dev?page=10)). A Base44 reviewer writes that it "redoes issues 50 times and is still not fixed", and the site averages 2.8 of 5 ([Trustpilot](https://www.trustpilot.com/review/base44.com?page=4)). A non-developer has no way out of this loop except spending more.

**2. Unpredictable cost.** Replit's effort-based pricing lets the agent decide how much work, and money, a prompt takes. After Agent 3 launched, one user said "I spent $1k this week alone" against a usual $180 to $200 a month, and another projected "around a 20x increase in cost monthly" ([The Register](https://www.theregister.com/2025/09/18/replit_agent3_pricing/)). Lovable meters work in credits, with 5 free per day capped at 30 a month on the free plan ([Lovable pricing](https://lovable.dev/pricing), summarized by [NoCode MBA](https://www.nocode.mba/articles/lovable-pricing)). One Lovable reviewer says that when monthly credits run out, "they disable your web apps backend functionality" ([Trustpilot](https://www.trustpilot.com/review/lovable.dev?page=10)). For a grandfather, a meter that runs while the machine flails is a reason to never touch it again.

**3. A separate publish step, and preview that lies.** Lovable changes are not live until you click Publish, then Update: "later changes are not automatically pushed live" ([Lovable docs](https://docs.lovable.dev/features/publish)). Worse, the preview sandbox fills in a working database URL, auth callbacks and permissive security that the live site lacks, so apps work in preview and break when published ([Afterbuild Labs](https://afterbuildlabs.com/platforms/lovable-developer/problems/preview-works-prod-broken)). Two copies of the app means two truths.

**4. Data is not covered by undo.** Replit's docs say "By default, rollbacks do not change your database," and restoring production data needs a separate point-in-time restore ([Replit docs](https://docs.replit.com/core-concepts/agent/checkpoints-and-rollbacks)). In the best-known failure, Replit's agent deleted SaaStr's production database, with records on 1,206 executives, during an explicit code freeze, then said rollback was impossible when it was not ([The Register](https://www.theregister.com/2025/07/21/replit_saastr_vibe_coding_incident/), [Fortune](https://fortune.com/2025/07/23/ai-coding-tool-replit-wiped-database-called-it-a-catastrophic-failure/)). For a Bible class, the data (who attended, prayer requests) is the tool.

**5. Sharing is all or nothing.** Either anyone with the URL gets in, or every recipient needs an account. Lovable's Public setting means "anyone with the published URL link can visit," and restricting to invited users is Business and Enterprise only ([Lovable docs](https://docs.lovable.dev/features/project-visibility)). Published Claude artifacts: "Everyone needs a Claude account. People without one can't open a shared artifact, even with the link" ([Claude Help](https://support.claude.com/en/articles/9547008-publish-and-share-artifacts)). Softr's free plan allows 5 app users ([Softr docs](https://docs.softr.io/workspace-and-billing/pricing-and-plans)); Glide charges $5 to $6 per extra business user ([Glide help](https://help.glideapps.com/en/articles/11780756-pricing-plans-as-of-november-1-2025)). None of these match "text my five friends a link that only works for them."

**6. Auth and databases left to people who cannot check them.** CVE-2025-48757 found 170 of 1,645 scanned Lovable apps with exposed databases because Supabase row-level security was off ([Matt Palmer](https://mattpalmer.io/posts/2025/05/CVE-2025-48757/)). Another Lovable-hosted app with inverted access logic exposed about 18,000 users; one commenter: "Lovable is marketed to non developers, so their core users wouldn't understand a security flow if it flashed red" ([HN](https://news.ycombinator.com/item?id=47182659)).

**7. The AI says it worked when it did not.** "their Ai said it's fixed but still can't log in" ([Trustpilot](https://www.trustpilot.com/review/lovable.dev?page=10)). Replit's agent also produced fabricated data during the SaaStr incident ([The Register](https://www.theregister.com/2025/07/21/replit_saastr_vibe_coding_incident/)). A non-developer cannot verify, so they believe it until a friend reports the bug.

**8. Lock-in and sudden loss.** Base44 reviewers: "My account was completely blocked without any warning... Apps gone" ([Trustpilot](https://www.trustpilot.com/review/base44.com?page=4)).

Not verified with a source, so left unranked: recipients seeing developer UI, and data resetting between versions of a Claude artifact. Both are plausible and worth testing directly.

## 2. What makes Google Docs better for a small group

**No save, no deploy.** The Writely founders' pitch: "No more 'save' button. Just you, your teammates (or friends or family), and a blank page" ([O'Reilly](https://www.oreilly.com/live-events/live-with-tim-oreilly-a-conversation-with-google-docs-founders-sam-schillace-steve-newman-and-claudia-carpenter/0642572227913/)). There is one copy, so what you see is what they see. This is what killed emailing Word files: no "confusing, ever-lengthening titles" (same source).

**The share dialog.** You type a name or email, pick Viewer, Commenter or Editor, and each person "gets an email," with an optional message ([Google Help](https://support.google.com/docs/answer/2494822)). "Anyone with the link" works for people without a Google account (same page).

**Request access.** Someone without permission sees "You need access," taps Request access, and can add a note. The owner gets an email naming the person and the file, and grants a role from it ([Google Help](https://support.google.com/docs/answer/16722399)). A wrong forward becomes a question, not a leak.

**Presence.** Invited people appear by name; link visitors appear as anonymous animals ([Google Help](https://support.google.com/docs/answer/2494888)). The owner knows who is actually there.

**Comments with mentions.** Typing @ or + and an email notifies that person by email; action items can be assigned ([Google Help](https://support.google.com/docs/answer/65129)).

**Version history.** Every change is kept; "Restore this version" rolls back, and up to 40 versions can be named ([Google Help](https://support.google.com/docs/answer/190843)).

**Make a copy.** Replacing /edit with /copy in a link prompts the recipient to make their own copy, the de facto template mechanism ([University of Utah](https://utah.screenstepslive.com/a/1876939-how-to-share-a-google-doc-link-to-force-copy)).

**Any device, no install.** A link opens in a browser. That removed "software to download" ([O'Reilly](https://www.oreilly.com/live-events/live-with-tim-oreilly-a-conversation-with-google-docs-founders-sam-schillace-steve-newman-and-claudia-carpenter/0642572227913/)).

I found no rigorous study on why Docs beat emailed Word files; the founders' framing above is the best primary source.

## What Amber Circles should copy, in priority order

1. **One live copy, no publish button:** every change Claude makes goes straight to the circle's link after it passes a smoke test, so preview and live never diverge (pain 3, Docs no-save).
2. **A version list with one-tap Restore that restores data too:** store a snapshot of code plus each tool's data at every Claude edit, and show them as plain sentences ("Tuesday, added a prayer list") with a Restore button (pains 1 and 4, Docs version history).
3. **Try before it counts:** Claude's edit runs on a copy of the real data, the owner sees it working, and only "Keep this" swaps it in; "Undo" is always one tap (pains 1 and 7, Docs restore).
4. **Flat price per circle, no meters:** show one monthly number, never a credit counter, and never charge for a failed or reverted edit (pain 2, Docs is free to edit).
5. **Share by name, from contacts:** a share sheet that takes names and phone numbers, sets Viewer or Helper, and texts each person their own link with the owner's note (pain 5, Docs share dialog and notify email).
6. **Personal links, no sign-up:** each member's link is a signed token tied to them, so a forwarded link does not grant access to a stranger (pains 5 and 6, Docs named sharing).
7. **Request access by text:** an unknown opener sees "Ask the owner to let you in," enters a name, and the owner gets a text with Approve and Decline (pain 5, Docs Request access).
8. **Platform-owned auth and storage:** tools never create their own logins or database rules; Circles enforces who sees what, so no generated code can expose a member (pain 6, Docs permissions live outside the document).
9. **Presence and who-opened list:** show first names of who is viewing now and who opened this week, so the owner knows the link reached people (pain 7, Docs presence).
10. **Copy to my circle:** any tool has "Make my own," cloning code without data into the viewer's circle (pain 8, Docs Make a copy).

## Traps to avoid for a grandparent-age user

- **Text too small.** NN/g's research on 123 seniors ([NN/g report](https://www.nngroup.com/reports/senior-citizens-on-the-web/)) found small text a persistent complaint: "the internet is unfriendly to people with bad eyesight" ([NN/g](https://www.nngroup.com/articles/usability-for-senior-citizens/)). Default to large body text and honor the phone's text size setting.
- **Small targets.** Seniors struggle with small buttons, dropdowns and sliders on touch screens ([NN/g report](https://www.nngroup.com/reports/senior-citizens-on-the-web/)). Make every tap target at least 44 by 44 CSS pixels ([WCAG 2.5.5](https://www.w3.org/WAI/WCAG21/Understanding/target-size.html)), and avoid date pickers where typing works.
- **Unforgiving errors.** Older users "make more mistakes" and blame themselves ("I fat-fingered that one") ([NN/g](https://www.nngroup.com/articles/usability-for-senior-citizens/)). Every action needs Undo, and every error message says what happened and the one button to press next.
- **Jargon.** Never show "deploy," "build failed," "workspace," "auth," "token," or a stack trace. Say "Your tool is updated" or "That change didn't work, so I put it back."
- **Silent AI claims.** Never tell the owner "fixed" without showing the fixed screen.
