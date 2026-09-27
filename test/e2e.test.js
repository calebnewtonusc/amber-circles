// End to end against a running server: AMBER_URL (default localhost:8787).
// Every assertion here is a promise the pitch makes out loud, so each one is
// checked against the real HTTP surface rather than the functions behind it.
import { test } from "node:test";
import assert from "node:assert/strict";

const BASE = process.env.AMBER_URL || "http://localhost:8787";

async function call(path, { method = "GET", body, owner, member } = {}) {
  const headers = { "content-type": "application/json" };
  if (owner) headers.authorization = `Bearer ${owner}`;
  if (member) headers["x-amber-member"] = member;
  const response = await fetch(BASE + path, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const text = await response.text();
  let json = null;
  try {
    json = JSON.parse(text);
  } catch {
    /* html or empty */
  }
  return { status: response.status, json, text, headers: response.headers };
}

const TOOL =
  '<!doctype html><html><head><title>t</title></head><body><p id="x">hello</p><script>amber.me().then(m => document.getElementById("x").textContent = m.name)</script></body></html>';

test("the whole flow: owner, circle, publish, member, outsider, bridge, frame, mcp", async () => {
  const created = await call("/api/owners", {
    method: "POST",
    body: { name: "Caleb Test" },
  });
  assert.equal(created.status, 200);
  const owner = created.json.key;

  const circle = await call("/api/circles", {
    method: "POST",
    owner,
    body: {
      name: "Test Cabinet",
      members: [
        { name: "Maya Chen", phone: "213 555 0199" },
        { name: "Tyler L" },
      ],
    },
  });
  assert.equal(circle.status, 200);

  const published = await call("/api/tools", {
    method: "POST",
    owner,
    body: { title: "Check-in", circle: "test cabinet", html: TOOL },
  });
  assert.equal(published.status, 200, published.text);
  const { slug } = published.json;

  const overview = await call("/api/owner", { owner });
  const members = overview.json.circles.find(
    (c) => c.name === "Test Cabinet",
  ).members;
  assert.equal(members.length, 3, "owner is auto-added to their own circle");
  const maya = members.find((m) => m.name === "Maya Chen");
  const me = members.find((m) => m.is_owner);
  assert.ok(maya.token && me.token);

  // A member gets in and the open is counted.
  const run = await call(`/api/run/${slug}`, { member: maya.token });
  assert.equal(run.status, 200);
  assert.equal(run.json.me.name, "Maya Chen");

  // An outsider is turned away, and told who to ask.
  const outsider = await call(`/api/run/${slug}`, {
    member: "not-a-real-token",
  });
  assert.equal(outsider.status, 403);
  assert.equal(outsider.json.circle, "Test Cabinet");
  assert.equal(outsider.json.owner, "Caleb Test");

  // A member of a DIFFERENT circle cannot open it either.
  await call("/api/circles", {
    method: "POST",
    owner,
    body: { name: "Other", members: [{ name: "Stranger" }] },
  });
  const again = await call("/api/owner", { owner });
  const stranger = again.json.circles
    .find((c) => c.name === "Other")
    .members.find((m) => m.name === "Stranger");
  assert.equal(
    (await call(`/api/run/${slug}`, { member: stranger.token })).status,
    403,
  );

  // The bridge: people carries no phones, data is shared and attributed.
  const people = await call(`/api/run/${slug}/rpc`, {
    method: "POST",
    member: maya.token,
    body: { op: "people" },
  });
  assert.equal(people.json.result.length, 3);
  assert.ok(
    people.json.result.every((p) => !("phone" in p)),
    "phones never cross into a tool",
  );
  await call(`/api/run/${slug}/rpc`, {
    method: "POST",
    member: maya.token,
    body: { op: "add", collection: "checkins", data: { here: true } },
  });
  const listed = await call(`/api/run/${slug}/rpc`, {
    method: "POST",
    member: me.token,
    body: { op: "list", collection: "checkins" },
  });
  assert.equal(listed.json.result.length, 1);
  assert.equal(listed.json.result[0].author.name, "Maya Chen");
  const badCollection = await call(`/api/run/${slug}/rpc`, {
    method: "POST",
    member: maya.token,
    body: { op: "list", collection: "../etc" },
  });
  assert.equal(badCollection.status, 400);

  // Only the owner can pull a phone number to reach out.
  assert.equal(
    (await call(`/api/run/${slug}/reach/${maya.id}`, { member: maya.token }))
      .status,
    403,
  );
  const reach = await call(`/api/run/${slug}/reach/${maya.id}`, {
    member: me.token,
  });
  assert.equal(reach.json.phone, "2135550199");

  // The frame: only with a fresh ticket, and with the network closed.
  const frame = await call(
    `/frame/${slug}?ticket=${encodeURIComponent(run.json.ticket)}`,
  );
  assert.equal(frame.status, 200);
  const csp = frame.headers.get("content-security-policy");
  assert.match(csp, /connect-src 'none'/);
  assert.match(frame.text, /window\.amber/, "the bridge is injected");
  assert.equal(
    (await call(`/frame/${slug}?ticket=forged.ticket.${maya.id}`)).status,
    403,
  );

  // Someone else's owner key cannot touch this tool.
  const intruder = (
    await call("/api/owners", { method: "POST", body: { name: "Intruder" } })
  ).json.key;
  assert.equal(
    (
      await call(`/api/tools/${slug}`, {
        method: "PUT",
        owner: intruder,
        body: { html: "<p>pwned</p>" },
      })
    ).status,
    404,
  );

  // MCP: the same publish, from Claude.
  const mcp = (body) =>
    call(`/mcp/${owner}`, {
      method: "POST",
      body: { jsonrpc: "2.0", id: 1, ...body },
    });
  assert.equal(
    (await mcp({ method: "initialize", params: {} })).json.result.serverInfo
      .name,
    "amber",
  );
  const tools = (await mcp({ method: "tools/list" })).json.result.tools.map(
    (t) => t.name,
  );
  assert.deepEqual(tools.sort(), [
    "create_circle",
    "get_tool_source",
    "list_circles",
    "publish_tool",
    "update_tool",
  ]);
  const viaMcp = await mcp({
    method: "tools/call",
    params: {
      name: "publish_tool",
      arguments: { title: "From Claude", circle: "Test Cabinet", html: TOOL },
    },
  });
  assert.match(viaMcp.json.result.content[0].text, /Link: .*\/t\/from-claude-/);
  assert.equal(
    (
      await call("/mcp/amb_wrong", {
        method: "POST",
        body: { jsonrpc: "2.0", id: 1, method: "tools/list" },
      })
    ).status,
    401,
  );
});
