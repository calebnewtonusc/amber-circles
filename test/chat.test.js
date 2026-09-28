// The iMessage app's server side: a group chat is a circle, the bubble carries
// the invite, and anyone in the thread can make and change things, scoped to
// that thread alone. No paid Claude call: tools are published directly.
import { test, after } from "node:test";
import assert from "node:assert/strict";

const BASE = process.env.AMBER_URL || "http://localhost:8787";

// Every chat a test starts is removed afterwards, so this can run on prod.
const started = [];
after(async () => {
  await Promise.all(
    started.map(({ chat, token }) =>
      fetch(`${BASE}/api/chats/${chat}`, { method: "DELETE", headers: { "x-amber-chat": token } }),
    ),
  );
});

async function call(path, { method = "GET", body, chat, member } = {}) {
  const headers = { "content-type": "application/json" };
  if (chat) headers["x-amber-chat"] = chat;
  if (member) headers["x-amber-member"] = member;
  const response = await fetch(BASE + path, { method, headers, body: body ? JSON.stringify(body) : undefined });
  const json = await response.json().catch(() => null);
  if (path === "/api/chats" && method === "POST" && json?.token) started.push({ chat: json.chat, token: json.token });
  return { status: response.status, json };
}

const page = (text) => `<!doctype html><html><body><main><p>${text}</p><script>window.x=1</script></main></body></html>`;

async function startChat() {
  const stan = (await call("/api/chats", { method: "POST", body: { name: "Stan", participant: "p-stan" } })).json;
  const ruth = (await call(`/api/chats/${stan.chat}/join`, { method: "POST", body: { invite: stan.invite, name: "Ruth", participant: "p-ruth" } })).json;
  return { stan, ruth };
}

test("a chat starts, the bubble's invite joins it, and joining twice is the same person", async () => {
  const { stan, ruth } = await startChat();
  assert.ok(stan.token && stan.invite && ruth.token);
  const again = (await call(`/api/chats/${stan.chat}/join`, { method: "POST", body: { invite: stan.invite, name: "Ruth", participant: "p-ruth" } })).json;
  assert.equal(again.member.id, ruth.member.id, "tapping the bubble again finds Ruth, not a second Ruth");
  const wrong = await call(`/api/chats/${stan.chat}/join`, { method: "POST", body: { invite: "nope", name: "Eve", participant: "p-eve" } });
  assert.equal(wrong.status, 404, "a guessed invite gets nothing");
  const view = (await call(`/api/chats/${stan.chat}`, { chat: ruth.token })).json;
  assert.deepEqual(view.people.map((p) => p.name), ["Stan", "Ruth"]);
  assert.equal(JSON.stringify(view).includes(stan.token), false, "nobody's link is handed to anyone else");
});

test("anyone in the chat can make, change and comment on a tool; outsiders cannot", async () => {
  const { stan, ruth } = await startChat();
  const made = await call("/api/tools", { method: "POST", chat: ruth.token, body: { title: "Rides", circle: stan.chat, html: page("v1") } });
  assert.equal(made.status, 200, "Ruth can put a tool in the chat");
  const slug = made.json.slug;
  const changed = await call(`/api/tools/${slug}`, { method: "PUT", chat: stan.token, body: { html: page("v2"), request: "bigger" } });
  assert.equal(changed.status, 200, "Stan can change what Ruth made");
  await call(`/api/tools/${slug}/notes`, { method: "POST", chat: ruth.token, body: { text: "Add Sunday too" } });
  const notes = (await call(`/api/tools/${slug}/notes`, { chat: stan.token })).json.notes;
  assert.deepEqual(notes.map((n) => [n.name, n.text]), [["Ruth", "Add Sunday too"]]);
  const opened = await call(`/api/run/${slug}`, { member: ruth.token });
  assert.equal(opened.status, 200, "the chat token opens the tool itself");

  const other = await startChat();
  const peek = await call(`/api/tools/${slug}/notes`, { chat: other.ruth.token });
  assert.equal(peek.status, 404, "another chat cannot see this chat's tool");
  const view = await call(`/api/chats/${stan.chat}`, { chat: other.stan.token });
  assert.equal(view.status, 403, "another chat cannot list this one");
});

test("comments work like Google Docs: reply to one, resolve the thread", async () => {
  const { stan, ruth } = await startChat();
  const slug = (await call("/api/tools", { method: "POST", chat: ruth.token, body: { title: "Rides", circle: stan.chat, html: page("v1") } })).json.slug;
  const first = (await call(`/api/tools/${slug}/notes`, { method: "POST", chat: ruth.token, body: { text: "Add Sunday" } })).json.id;
  const reply = await call(`/api/tools/${slug}/notes`, { method: "POST", chat: stan.token, body: { text: "On it", parent: first } });
  assert.equal(reply.status, 200);
  const deep = await call(`/api/tools/${slug}/notes`, { method: "POST", chat: stan.token, body: { text: "nested", parent: reply.json.id } });
  assert.equal(deep.status, 404, "replies are one level deep");
  let notes = (await call(`/api/tools/${slug}/notes`, { chat: ruth.token })).json.notes;
  assert.deepEqual(notes.map((n) => [n.name, n.text, n.parent_id]), [["Ruth", "Add Sunday", null], ["Stan", "On it", first]]);
  let board = (await call(`/api/chats/${stan.chat}/board`, { chat: stan.token })).json;
  assert.deepEqual(board.comments.map((n) => n.text), ["Add Sunday"], "replies stay in their thread");
  assert.equal((await call(`/api/tools/${slug}/notes/${reply.json.id}/resolve`, { method: "POST", chat: stan.token, body: {} })).status, 404, "only a thread resolves");
  assert.equal((await call(`/api/tools/${slug}/notes/${first}/resolve`, { method: "POST", chat: stan.token, body: {} })).status, 200);
  notes = (await call(`/api/tools/${slug}/notes`, { chat: ruth.token })).json.notes;
  assert.ok(notes[0].resolved_at, "resolved is kept, not deleted");
  board = (await call(`/api/chats/${stan.chat}/board`, { chat: stan.token })).json;
  assert.deepEqual(board.comments, [], "a resolved comment leaves the home board");
  await call(`/api/tools/${slug}/notes/${first}/resolve`, { method: "POST", chat: ruth.token, body: { resolved: false } });
  notes = (await call(`/api/tools/${slug}/notes`, { chat: ruth.token })).json.notes;
  assert.equal(notes[0].resolved_at, null, "and it can be reopened");
  const other = await startChat();
  assert.equal((await call(`/api/tools/${slug}/notes/${first}/resolve`, { method: "POST", chat: other.ruth.token, body: {} })).status, 404);
});

test("pins keep their anchor, and activity separates edits, publishes and shares", async () => {
  const { stan, ruth } = await startChat();
  const slug = (await call("/api/tools", { method: "POST", chat: ruth.token, body: { title: "Rides", circle: stan.chat, html: page("v1") } })).json.slug;
  const pin = await call(`/api/tools/${slug}/notes`, {
    method: "POST", chat: stan.token,
    body: { text: "Bigger", anchor: { selector: "body > h1:nth-of-type(1)", fx: 1.7, fy: 0.25, label: "Rides", evil: "x" } },
  });
  assert.equal(pin.status, 200);
  const notes = (await call(`/api/tools/${slug}/notes`, { chat: ruth.token })).json.notes;
  assert.deepEqual(notes[0].anchor, { selector: "body > h1:nth-of-type(1)", fx: 1, fy: 0.25, label: "Rides" }, "clamped, and nothing extra kept");
  assert.equal((await call(`/api/tools/${slug}/shared`, { method: "POST", chat: ruth.token, body: {} })).status, 200);
  const activity = (await call(`/api/tools/${slug}/activity`, { chat: stan.token })).json.activity;
  assert.deepEqual(activity.map((a) => [a.kind, a.name]), [["shared", "Ruth"]]);
  const other = await startChat();
  assert.equal((await call(`/api/tools/${slug}/activity`, { chat: other.ruth.token })).status, 404);
});

test("someone in a chat cannot delete the chat's account or remove people; the starter can remove the chat", async () => {
  const { stan, ruth } = await startChat();
  assert.equal((await call("/api/owner", { method: "DELETE", chat: ruth.token })).status, 403);
  assert.equal((await call(`/api/members/${stan.member.id}`, { method: "DELETE", chat: ruth.token })).status, 403);
  assert.equal((await call(`/api/chats/${stan.chat}`, { method: "DELETE", chat: ruth.token })).status, 403, "Ruth did not start it");
  assert.equal((await call(`/api/chats/${stan.chat}`, { method: "DELETE", chat: stan.token })).status, 200);
  assert.equal((await call(`/api/chats/${stan.chat}`, { chat: stan.token })).status, 401, "gone means gone");
});
