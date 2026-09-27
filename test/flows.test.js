// The Google Docs mechanics, end to end against a running server, without a
// paid Claude call: every change is kept and restorable, a draft can be
// discarded, and a stranger can ask to join and be let in with one tap.
import { test } from "node:test";
import assert from "node:assert/strict";

const BASE = process.env.AMBER_URL || "http://localhost:8787";

// Every owner a test creates is deleted afterwards, so running this against
// production leaves nothing behind. It did once: 2026-09-27, four test owners.
const created = [];
import { after } from "node:test";
after(async () => {
  await Promise.all(
    created.map((key) =>
      fetch(`${BASE}/api/owner`, {
        method: "DELETE",
        headers: { authorization: `Bearer ${key}` },
      }),
    ),
  );
});

async function call(path, { method = "GET", body, owner, member } = {}) {
  const headers = { "content-type": "application/json" };
  if (owner) headers.authorization = `Bearer ${owner}`;
  if (member) headers["x-amber-member"] = member;
  const response = await fetch(BASE + path, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await response.json().catch(() => null);
  if (path === "/api/owners" && method === "POST" && json?.key)
    created.push(json.key);
  return { status: response.status, json };
}

test("a tool can be copied, without its data, by someone who can open it", async () => {
  const stan = (
    await call("/api/owners", { method: "POST", body: { name: "Stan" } })
  ).json.key;
  await call("/api/circles", {
    method: "POST",
    owner: stan,
    body: { name: "Class", members: [{ name: "Ruth" }] },
  });
  const { circles } = (await call("/api/owner", { owner: stan })).json;
  const { slug } = (
    await call("/api/tools", {
      method: "POST",
      owner: stan,
      body: { title: "Prayers", circle: circles[0].id, html: page("x") },
    })
  ).json;
  const ruthToken = circles[0].members.find((m) => m.name === "Ruth").token;
  await call(`/api/run/${slug}/rpc`, {
    method: "POST",
    member: ruthToken,
    body: { op: "add", collection: "prayers", data: { text: "secret" } },
  });

  const ruth = (
    await call("/api/owners", { method: "POST", body: { name: "Ruth" } })
  ).json.key;
  const mine = (
    await call("/api/circles", {
      method: "POST",
      owner: ruth,
      body: { name: "My family" },
    })
  ).json;
  const copy = await call(`/api/run/${slug}/copy`, {
    method: "POST",
    owner: ruth,
    member: ruthToken,
    body: { circle: mine.id },
  });
  assert.equal(copy.status, 200);
  const hers = (await call("/api/owner", { owner: ruth })).json.tools;
  assert.equal(hers.length, 1);
  assert.equal(hers[0].record_count, 0, "the copy carries no data");

  // Without a link that opens the original, there is nothing to copy.
  assert.equal(
    (
      await call(`/api/run/${slug}/copy`, {
        method: "POST",
        owner: ruth,
        member: "nope",
        body: { circle: mine.id },
      })
    ).status,
    403,
  );
  // Deleting an account removes its tools.
  assert.equal(
    (await call("/api/owner", { method: "DELETE", owner: ruth })).status,
    200,
  );
  assert.equal((await call("/api/owner", { owner: ruth })).status, 401);
});

const page = (text) =>
  `<!doctype html><html><head><title>t</title></head><body><p>${text}</p></body></html>`;

test("every change is kept, and going back restores the old tool as a new version", async () => {
  const owner = (
    await call("/api/owners", { method: "POST", body: { name: "Stan" } })
  ).json.key;
  const { id } = (
    await call("/api/circles", {
      method: "POST",
      owner,
      body: { name: "Class" },
    })
  ).json;
  const { slug } = (
    await call("/api/tools", {
      method: "POST",
      owner,
      body: { title: "Prayers", circle: id, html: page("one") },
    })
  ).json;
  await call(`/api/tools/${slug}`, {
    method: "PUT",
    owner,
    body: { html: page("two") },
  });
  await call(`/api/tools/${slug}`, {
    method: "PUT",
    owner,
    body: { html: page("three") },
  });

  const { versions } = (await call(`/api/tools/${slug}/versions`, { owner }))
    .json;
  assert.deepEqual(
    versions.map((v) => v.version),
    [3, 2, 1],
  );
  assert.equal(versions.find((v) => v.current).version, 3);

  const restored = await call(`/api/tools/${slug}/restore`, {
    method: "POST",
    owner,
    body: { version: 1 },
  });
  assert.equal(
    restored.json.version,
    4,
    "going back is itself a new version, so it can be undone",
  );
  const after = (await call(`/api/tools/${slug}/versions`, { owner })).json
    .versions;
  assert.equal(after[0].request, "Went back to version 1");

  // Keep with nothing waiting says so; discard is always safe.
  assert.equal(
    (await call(`/api/tools/${slug}/keep`, { method: "POST", owner })).status,
    404,
  );
  assert.equal(
    (await call(`/api/tools/${slug}/discard`, { method: "POST", owner }))
      .status,
    200,
  );

  // Another owner cannot read or restore this tool's history.
  const other = (
    await call("/api/owners", { method: "POST", body: { name: "Other" } })
  ).json.key;
  assert.deepEqual(
    (await call(`/api/tools/${slug}/versions`, { owner: other })).json.versions,
    [],
  );
  assert.equal(
    (
      await call(`/api/tools/${slug}/restore`, {
        method: "POST",
        owner: other,
        body: { version: 1 },
      })
    ).status,
    404,
  );
});

test("a stranger asks to join, the owner lets them in, and their link works", async () => {
  const owner = (
    await call("/api/owners", { method: "POST", body: { name: "Stan" } })
  ).json.key;
  const { id } = (
    await call("/api/circles", {
      method: "POST",
      owner,
      body: { name: "Class" },
    })
  ).json;
  const { slug } = (
    await call("/api/tools", {
      method: "POST",
      owner,
      body: { title: "Prayers", circle: id, html: page("x") },
    })
  ).json;

  const gate = await call(`/api/run/${slug}`, { member: "nobody" });
  assert.equal(gate.status, 403);
  assert.equal(
    (
      await call(`/api/run/${slug}/ask`, {
        method: "POST",
        body: {
          name: "Ruth Miller",
          phone: "253 555 0101",
          note: "From Tuesday",
        },
      })
    ).status,
    200,
  );
  assert.equal(
    (
      await call(`/api/run/${slug}/ask`, {
        method: "POST",
        body: { name: "Harold" },
      })
    ).status,
    200,
  );

  const { requests } = (await call("/api/requests", { owner })).json;
  assert.equal(requests.length, 2);
  const ruth = requests.find((r) => r.name === "Ruth Miller");
  assert.equal(ruth.note, "From Tuesday");

  const approved = (
    await call(`/api/requests/${ruth.id}/approve`, { method: "POST", owner })
  ).json;
  assert.equal(approved.phone, "2535550101");
  assert.ok(!new URL(approved.link).search, "the member token never rides in a query string, where edge logs keep it");
  const token = new URLSearchParams(new URL(approved.link).hash.slice(1)).get("m");
  const opened = await call(`/api/run/${slug}`, { member: token });
  assert.equal(opened.status, 200);
  assert.equal(opened.json.me.name, "Ruth Miller");

  // Handling a request twice is refused, and declining never adds anyone.
  assert.equal(
    (await call(`/api/requests/${ruth.id}/approve`, { method: "POST", owner }))
      .status,
    404,
  );
  const harold = requests.find((r) => r.name === "Harold");
  const declined = (
    await call(`/api/requests/${harold.id}/decline`, { method: "POST", owner })
  ).json;
  assert.equal(declined.link, null);
  assert.equal(
    (await call("/api/requests", { owner })).json.requests.length,
    0,
  );

  // Someone else's owner key cannot approve requests on this tool.
  await call(`/api/run/${slug}/ask`, {
    method: "POST",
    body: { name: "Mallory" },
  });
  const pending = (await call("/api/requests", { owner })).json.requests[0];
  const other = (
    await call("/api/owners", { method: "POST", body: { name: "Other" } })
  ).json.key;
  assert.equal(
    (
      await call(`/api/requests/${pending.id}/approve`, {
        method: "POST",
        owner: other,
      })
    ).status,
    404,
  );
});

test("presence: a member polling shows up as here now", async () => {
  const owner = (
    await call("/api/owners", { method: "POST", body: { name: "Stan" } })
  ).json.key;
  await call("/api/circles", {
    method: "POST",
    owner,
    body: { name: "Class", members: [{ name: "Dottie" }] },
  });
  const { circles } = (await call("/api/owner", { owner })).json;
  const { slug } = (
    await call("/api/tools", {
      method: "POST",
      owner,
      body: { title: "P", circle: circles[0].id, html: page("x") },
    })
  ).json;
  const dottie = circles[0].members.find((m) => m.name === "Dottie");
  const other = (await call("/api/tools", { method: "POST", owner, body: { title: "Q", circle: circles[0].id, html: page("y") } })).json.slug;
  const toolBySlug = async (which) => (await call("/api/owner", { owner })).json.tools.find((t) => t.slug === which);
  assert.deepEqual((await toolBySlug(slug)).here_now_ids, []);
  await call(`/api/run/${slug}/rpc`, { method: "POST", member: dottie.token, body: { op: "stamp" } });
  assert.deepEqual((await toolBySlug(slug)).here_now_ids, [dottie.id]);
  // Regression, 2026-09-27: presence was per member, so being on one tool
  // showed you as using every tool in the circle.
  assert.deepEqual((await toolBySlug(other)).here_now_ids, [], "Dottie is not on the other tool");
});

test("people remove their own entries; only the owner removes anyone's", async () => {
  const stan = (await call("/api/owners", { method: "POST", body: { name: "Stan" } })).json.key;
  await call("/api/circles", { method: "POST", owner: stan, body: { name: "Class", members: [{ name: "Ruth" }, { name: "Harold" }] } });
  const { circles } = (await call("/api/owner", { owner: stan })).json;
  const { slug } = (await call("/api/tools", { method: "POST", owner: stan, body: { title: "P", circle: circles[0].id, html: page("x") } })).json;
  const token = (name) => circles[0].members.find((m) => m.name === name).token;
  const add = async (who, text) => (await call(`/api/run/${slug}/rpc`, { method: "POST", member: token(who), body: { op: "add", collection: "prayers", data: { text } } })).json.result.id;
  const remove = (who, id) => call(`/api/run/${slug}/rpc`, { method: "POST", member: token(who), body: { op: "remove", collection: "prayers", id } });

  const harolds = await add("Harold", "for Carol");
  assert.equal((await remove("Ruth", harolds)).status, 403, "Ruth cannot delete Harold's prayer");
  assert.equal((await remove("Harold", harolds)).status, 200, "Harold can delete his own");
  const ruths = await add("Ruth", "for Dan");
  assert.equal((await remove("Stan", ruths)).status, 200, "the owner can delete anyone's");
  // Editing stays shared, so a sign-up slot one person made can be claimed by another.
  const slot = await add("Harold", "bring rolls");
  assert.equal((await call(`/api/run/${slug}/rpc`, { method: "POST", member: token("Ruth"), body: { op: "update", collection: "prayers", id: slot, data: { taken: "Ruth" } } })).status, 200);
});

test("going back can put the entries back too, and that is itself undoable", async () => {
  const stan = (await call("/api/owners", { method: "POST", body: { name: "Stan" } })).json.key;
  await call("/api/circles", { method: "POST", owner: stan, body: { name: "Class", members: [{ name: "Ruth" }] } });
  const { circles } = (await call("/api/owner", { owner: stan })).json;
  const { slug } = (await call("/api/tools", { method: "POST", owner: stan, body: { title: "P", circle: circles[0].id, html: page("one") } })).json;
  const ruth = circles[0].members.find((m) => m.name === "Ruth").token;
  const rpc = (body) => call(`/api/run/${slug}/rpc`, { method: "POST", member: ruth, body });
  const texts = async () => (await rpc({ op: "list", collection: "prayers" })).json.result.map((r) => r.data.text).sort();

  await rpc({ op: "add", collection: "prayers", data: { text: "Carol" } });
  const dan = (await rpc({ op: "add", collection: "prayers", data: { text: "Dan" } })).json.result.id;
  await call(`/api/tools/${slug}`, { method: "PUT", owner: stan, body: { html: page("two") } }); // v2 carries Carol and Dan
  await rpc({ op: "remove", collection: "prayers", id: dan });
  await rpc({ op: "add", collection: "prayers", data: { text: "Walt" } });
  assert.deepEqual(await texts(), ["Carol", "Walt"]);

  const back = await call(`/api/tools/${slug}/restore`, { method: "POST", owner: stan, body: { version: 2, entries: true } });
  assert.equal(back.status, 200);
  assert.deepEqual(await texts(), ["Carol", "Dan"], "the entries are exactly as they were at version 2");
  const byRuth = (await rpc({ op: "list", collection: "prayers" })).json.result.every((r) => r.author.name === "Ruth");
  assert.ok(byRuth, "authorship survives the round trip");

  // The restore made version 3, which snapshotted Carol and Walt first.
  const undo = await call(`/api/tools/${slug}/restore`, { method: "POST", owner: stan, body: { version: 3, entries: true } });
  assert.equal(undo.status, 200);
  assert.deepEqual(await texts(), ["Carol", "Walt"], "putting entries back can be undone");

  // A plain go-back never touches the entries.
  await call(`/api/tools/${slug}/restore`, { method: "POST", owner: stan, body: { version: 1 } });
  assert.deepEqual(await texts(), ["Carol", "Walt"]);
});
