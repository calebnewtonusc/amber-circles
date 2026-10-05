// Group cards: one shared question per card, one answer per member. These are
// the rules that make a card safe in a group chat with several people tapping
// at once.
import { test, after } from "node:test";
import assert from "node:assert/strict";

const BASE = process.env.AMBER_URL || "http://localhost:8787";

const started = [];
after(async () => {
  await Promise.all(
    started.map(({ chat, token }) =>
      fetch(`${BASE}/api/chats/${chat}`, { method: "DELETE", headers: { "x-amber-chat": token } }),
    ),
  );
});

async function call(path, { method = "GET", body, chat } = {}) {
  const headers = { "content-type": "application/json" };
  if (chat) headers["x-amber-chat"] = chat;
  const response = await fetch(BASE + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const json = await response.json().catch(() => null);
  if (path === "/api/chats" && method === "POST" && json?.token) started.push({ chat: json.chat, token: json.token });
  return { status: response.status, json };
}

async function startChat() {
  const stan = (await call("/api/chats", { method: "POST", body: { name: "Stan", participant: "c-stan" } })).json;
  const ruth = (await call(`/api/chats/${stan.chat}/join`, { method: "POST", body: { invite: stan.invite, name: "Ruth", participant: "c-ruth" } })).json;
  return { stan, ruth };
}

const free = { kind: "free", title: "This weekend", spec: { days: ["2026-10-10", "2026-10-11"] } };

test("two people answering at the same moment both land, and each only ever writes their own row", async () => {
  const { stan, ruth } = await startChat();
  const card = (await call(`/api/chats/${stan.chat}/cards`, { method: "POST", chat: stan.token, body: free })).json.card;
  await Promise.all([
    call(`/api/cards/${card.id}/mine`, { method: "PUT", chat: stan.token, body: { data: { slots: [14, 15, 16] } } }),
    call(`/api/cards/${card.id}/mine`, { method: "PUT", chat: ruth.token, body: { data: { slots: [15, 16, 40], amber: true } } }),
  ]);
  const seen = (await call(`/api/chats/${stan.chat}/cards`, { chat: ruth.token })).json.cards[0];
  assert.equal(seen.entries.length, 2, "neither answer overwrote the other");
  assert.deepEqual(Object.fromEntries(seen.entries.map((e) => [e.name, e.data.slots])), { Stan: [14, 15, 16], Ruth: [15, 16, 40] });
  // Ruth changes her answer: still one row for her, Stan's untouched.
  await call(`/api/cards/${card.id}/mine`, { method: "PUT", chat: ruth.token, body: { data: { slots: [2] } } });
  const after = (await call(`/api/chats/${stan.chat}/cards`, { chat: stan.token })).json.cards[0];
  assert.deepEqual(Object.fromEntries(after.entries.map((e) => [e.name, e.data.slots])), { Stan: [14, 15, 16], Ruth: [2] });
});

test("only the fields a card allows are stored, so a phone number or token cannot ride along", async () => {
  const { stan } = await startChat();
  const who = (await call(`/api/chats/${stan.chat}/cards`, { method: "POST", chat: stan.token, body: { kind: "who", title: "Anyone at Pixar?", spec: { question: "Who do we know at Pixar?" } } })).json.card;
  const put = await call(`/api/cards/${who.id}/mine`, {
    method: "PUT",
    chat: stan.token,
    body: { data: { people: [{ name: "Jake Lin", about: "Story artist", phone: "+13105550101", token: "x" }], secret: "y" } },
  });
  assert.equal(put.status, 200);
  const stored = put.json.card.entries[0].data;
  assert.deepEqual(stored, { people: [{ name: "Jake Lin", about: "Story artist" }], amber: false });
  assert.equal(JSON.stringify(put.json).includes("3105550101"), false);
});

test("an answer outside the card's own shape is refused", async () => {
  const { stan } = await startChat();
  const pick = (await call(`/api/chats/${stan.chat}/cards`, {
    method: "POST", chat: stan.token,
    body: { kind: "pick", title: "Dinner", spec: { options: [{ name: "Tacos" }, { name: "Pho", url: "javascript:alert(1)" }] } },
  })).json.card;
  assert.equal(pick.spec.options[1].url, undefined, "only https links are kept");
  assert.equal((await call(`/api/cards/${pick.id}/mine`, { method: "PUT", chat: stan.token, body: { data: { vote: 7 } } })).status, 400);
  const slots = (await call(`/api/chats/${stan.chat}/cards`, { method: "POST", chat: stan.token, body: free })).json.card;
  const out = await call(`/api/cards/${slots.id}/mine`, { method: "PUT", chat: stan.token, body: { data: { slots: [0, 51, 52, -1, 3.5] } } });
  assert.deepEqual(out.json.card.entries[0].data.slots, [0, 51], "slots past the last day are dropped");
  assert.equal((await call(`/api/chats/${stan.chat}/cards`, { method: "POST", chat: stan.token, body: { kind: "nope", title: "x" } })).status, 400);
});

test("another chat cannot see, answer or close a card, and only its maker can close it", async () => {
  const { stan, ruth } = await startChat();
  const other = await startChat();
  const card = (await call(`/api/chats/${stan.chat}/cards`, { method: "POST", chat: stan.token, body: { kind: "split", title: "Dinner", spec: { total: 8400, tip: 18, venmo: "@stan-g" } } })).json.card;
  assert.equal(card.spec.venmo, "stan-g");
  assert.equal((await call(`/api/chats/${stan.chat}/cards`, { chat: other.stan.token })).status, 403);
  assert.equal((await call(`/api/cards/${card.id}/mine`, { method: "PUT", chat: other.ruth.token, body: { data: { paid: true } } })).status, 404);
  assert.equal((await call(`/api/cards/${card.id}/close`, { method: "POST", chat: ruth.token })).status, 403, "Ruth did not start it");
  assert.equal((await call(`/api/cards/${card.id}/close`, { method: "POST", chat: stan.token })).status, 200);
  assert.equal((await call(`/api/cards/${card.id}/mine`, { method: "PUT", chat: ruth.token, body: { data: { paid: true } } })).status, 409);
});
