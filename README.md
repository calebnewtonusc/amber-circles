# Amber

An iMessage app where a group chat builds small software together, by talking.

Open Amber inside any iMessage thread, hold the mic, and say what the group needs: "a shift sign-up sheet for our club fair booth". Amber asks at most three questions, reads the plan back, and builds it in about a minute while you watch it come together. The app is live on the web the moment it exists, and everyone in the chat can open it, comment on it, and change it by talking, the way everyone can edit a Google Doc. No accounts, no downloads beyond iMessage, no code.

Built for Origin Weekend Fall 2026, Prompt F, "A Cloud for Small Software", by Caleb Newton and Shirley Park.

## Try it

- **iPhone:** TestFlight, public link https://testflight.apple.com/join/7DMFRSv8 (live once Apple's beta review passes). After installing, open any iMessage thread, tap **+**, and choose **Amber**.
- **Server:** https://web-production-058309.up.railway.app

## What it does

- **Talk to build.** Hold the mic in the message field and speak, or type. Amber interviews you (three questions at most, always including the look you want), then builds. Say "just build it" or "don't ask questions" and it skips straight to building.
- **Watch it get made.** The preview fills in live as Claude writes the app: each new piece eases in, a status line says what is being added, and Amber narrates out loud.
- **One project, one conversation.** Home is a chat with Amber plus every project the group has made. Asking for something new drops a project card into the chat, and the card grows into the project.
- **Everyone in the chat can change it.** Changes are patches, not rewrites, so "make the names bigger" takes seconds. A change stays private to whoever asked until they tap **Publish online**. **Send to chat** drops a bubble for it into the conversation.
- **Pinned comments, like Google Docs.** Double-tap anything in the preview to pin a comment to that exact element. Each person has their own letter and colour. Reply and resolve right on the pin. A pin whose element is removed resolves itself.
- **Activity.** Every edit, publish, share, rename and open comment, per project and across the whole chat.
- **Group cards, from your own Amber.** Free time, Split, Vote, Who knows and Remind us are cards the whole chat answers, one row per person, so nobody overwrites anybody. If you have the Amber app, Amber answers for you on your phone: your free half hours from your calendar, real places to vote on, the people you know (you pick who to share), a reminder saved in your Amber. Only the answer reaches the chat. Without Amber you tap your answer in by hand.
- **Memory.** Amber remembers each person's style across chats (with Sign in with Apple) and never carries one chat's contents into another.

## How it works

- `ios/`: the iMessage extension and container app, SwiftUI, built with xcodegen. Speech recognition runs on the phone.
- `server.js`: Node and Hono on Railway, with Postgres. Chats are circles; each member acts with their own token.
- `agent.js`: the conversational agent (Claude Sonnet 5) with tools for reading the chat's apps, its conversations and memories, proposing a plan, and building or changing an app. The build is refused on the server unless a plan was confirmed or the person said to skip the questions.
- `builder.js`: Claude Opus 5 streams a new app as one HTML file; Claude Sonnet 5 patches an existing one with exact find-and-replace edits, falling back to a full rebuild.
- Voice replies use ElevenLabs Flash v2.5 through a server proxy, so no key ever reaches the phone.

## How a tool is kept safe

A tool is untrusted code written by a model, so the platform assumes nothing about it.

- It runs in a sandboxed iframe with an opaque origin, so it cannot read the member's link, cookies or storage.
- Its content security policy closes `connect-src`, so it cannot send data anywhere. Images are `data:` and `blob:` only.
- Its one door is a postMessage bridge the parent page mediates. The bridge exposes names, never phone numbers.
- The server enforces removal: members remove their own entries, and the owner removes any.
- A tool that navigates itself away is closed. The first outbound request still leaves before that happens, which is the known open item.
- Member and sign-in links carry their token after `#`, which browsers never send to the server, so tokens stay out of request logs.
- Tokens are stored hashed. The only reversible copy is sealed with `AMBER_SECRET`, so the owner's share sheet can resend a link.

## Run it locally

```bash
npm install
DATABASE_URL=postgres://localhost:5433/amber \
ANTHROPIC_API_KEY=... \
PORT=8787 node server.js
```

The schema applies itself on boot. Without `ANTHROPIC_API_KEY`, everything works except `/make`, which says the builder is not switched on.

## Test it

```bash
npm test                                  # against localhost:8787
AMBER_URL=https://... npm test            # against a deployed copy
```

- `test/e2e.test.js` covers the gate, the bridge, the frame policy and MCP.
- `test/flows.test.js` covers versions, entry restore, join requests, presence, copying and removal rights.
- `test/chat.test.js` covers chats, members, pinned comments, replies and resolve, activity and renames.
- `test/deny.test.js` enforces DENY.md.

The tests delete every owner they create, so running them against production leaves nothing behind.

## Design

The iMessage app follows Apple's own patterns: the system font, one Messages-style field with the microphone inside it, and one colour, Amber orange, used only for your own messages. Screens open by growing out of the row or card you tapped and close back into it. The web version's rules are in [DENY.md](DENY.md) and enforced by `test/deny.test.js`.

## Deploy

Railway, workspace "Caleb Newton's Projects", project `amber-circles`, services `web` and `Postgres`. Pushing does not deploy; run `railway up --service web`. The web service needs these env vars: `DATABASE_URL`, `AMBER_SECRET`, `ANTHROPIC_API_KEY`, `NODE_ENV=production`, and `PUBLIC_URL`.

## Research

[research/vibe-coding-vs-docs.md](research/vibe-coding-vs-docs.md) covers what non-developers hate about AI app builders, what Google Docs gets right, and the ranked list of mechanics this copies, all with sources.

All glory to God! ✝️❤️
