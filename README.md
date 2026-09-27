# Amber Circles

Ask Claude for a tool, and share it like a Google Doc.

Someone who has never written code describes a small tool in plain words, like "a prayer list for my Monday Bible class". Claude builds it in about a minute. Only the people in that group, a circle, can open it, each through a personal link sent by text. Built for Origin Weekend Fall 2026, Prompt F, "A Cloud for Small Software", by Caleb Newton and Shirley Park.

Live at https://web-production-058309.up.railway.app

## What it does

- **Make it in plain words.** `/make` takes a sentence and a group. Claude Opus 5 writes one HTML file, and the page names each stage while it works.
- **One live copy.** There is no publish step. A change lands as a draft on the real data, visible only to the owner, until "Keep this" or "Put it back".
- **Every version kept.** Going back is one tap and is itself a version. "Entries too" also puts the list back exactly as it was, and that can be undone.
- **Share by name.** Each member gets a personal link. There are no accounts and no passwords, and a stranger with the link can ask to join.
- **Presence.** The owner sees who is using a tool right now and who has not opened it yet.
- **Make your own.** Any viewer can copy a tool, without its data, into their own group.
- **For power users.** Claude and Claude Code can publish through the MCP endpoint at `/mcp/<owner key>`.

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
- `test/deny.test.js` enforces DENY.md.

The tests delete every owner they create, so running them against production leaves nothing behind.

## Design

The stance is editorial, the one Amber's own Classical system already takes. [DENY.md](DENY.md) lists what the interface refuses: gradients, radius above 4px, soft shadows, filled buttons, pills, and a second hue. `test/deny.test.js` fails the build on any of them. Screens are also checked by rendering them with ux-engine's `design-gate`.

## Deploy

Railway, workspace "Caleb Newton's Projects", project `amber-circles`, services `web` and `Postgres`. Pushing does not deploy; run `railway up --service web`. The web service needs these env vars: `DATABASE_URL`, `AMBER_SECRET`, `ANTHROPIC_API_KEY`, `NODE_ENV=production`, and `PUBLIC_URL`.

## Research

[research/vibe-coding-vs-docs.md](research/vibe-coding-vs-docs.md) covers what non-developers hate about AI app builders, what Google Docs gets right, and the ranked list of mechanics this copies, all with sources.

All glory to God! ✝️❤️
