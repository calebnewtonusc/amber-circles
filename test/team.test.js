// The Chewbacca team board in a group chat (team.js). These run only against a
// server started with TEAM_LOCAL_DIR, because against production they would
// commit real tasks to the real board:
//
//   TEAM_LOCAL_DIR=/tmp/board TEAM_LINK_CODE=test-code node server.js
//   TEAM_LINK_CODE=test-code TEAM_LOCAL_DIR=/tmp/board node --test test/team.test.js
import { test, after, before } from "node:test";
import assert from "node:assert/strict";
import { mkdir, readFile, stat, writeFile } from "node:fs/promises";
import path from "node:path";

const BASE = process.env.AMBER_URL || "http://localhost:8787";
const CODE = process.env.TEAM_LINK_CODE;
const DIR = process.env.TEAM_LOCAL_DIR;
const skip =
  !CODE || !DIR
    ? "needs a local server with TEAM_LOCAL_DIR and TEAM_LINK_CODE"
    : false;

const started = [];
after(async () => {
  await Promise.all(
    started.map(({ chat, token }) =>
      fetch(`${BASE}/api/chats/${chat}`, {
        method: "DELETE",
        headers: { "x-amber-chat": token },
      }),
    ),
  );
});

before(async () => {
  if (skip) return;
  await mkdir(path.join(DIR, "team/tasks"), { recursive: true });
  await writeFile(
    path.join(DIR, "team/members.json"),
    JSON.stringify([
      { name: "Caleb", role: "business" },
      { name: "Jake", role: "implementations" },
      { name: "Semyon", role: "backend" },
    ]),
  );
  await writeFile(
    path.join(DIR, "team/tasks/CHW-1.md"),
    [
      "---",
      "id: CHW-1",
      "title: Ship the reply agent",
      "status: todo",
      "area: ",
      "parent: ",
      "owner: Jake",
      "priority: high",
      "due: 2026-10-12",
      "labels: ",
      "done_when: Jonah sees a reply drafted",
      "proof: ",
      "source: ",
      "created: 2026-10-01",
      "updated: 2026-10-01",
      "---",
      "",
      "## Activity",
      "- 2026-10-01 Caleb: created",
      "",
    ].join("\n"),
  );
  await writeFile(
    path.join(DIR, "team/tasks/CHW-2.md"),
    [
      "---",
      "id: CHW-2",
      "title: Untriaged idea",
      "status: inbox",
      "area: ",
      "parent: ",
      "owner: ",
      "priority: none",
      "due: ",
      "labels: ",
      "done_when: ",
      "proof: ",
      "source: ",
      "created: 2026-10-01",
      "updated: 2026-10-01",
      "---",
      "",
      "## Activity",
      "",
    ].join("\n"),
  );
});

async function call(p, { method = "GET", body, chat } = {}) {
  const headers = { "content-type": "application/json" };
  if (chat) headers["x-amber-chat"] = chat;
  const response = await fetch(BASE + p, {
    method,
    headers,
    body: body ? JSON.stringify(body) : undefined,
  });
  const json = await response.json().catch(() => null);
  if (p === "/api/chats" && method === "POST" && json?.token)
    started.push({ chat: json.chat, token: json.token });
  return { status: response.status, json };
}

async function chat() {
  const caleb = (
    await call("/api/chats", {
      method: "POST",
      body: { name: "Caleb", participant: `t-caleb-${Date.now()}` },
    })
  ).json;
  const jake = (
    await call(`/api/chats/${caleb.chat}/join`, {
      method: "POST",
      body: {
        invite: caleb.invite,
        name: "Jake",
        participant: `t-jake-${Date.now()}`,
      },
    })
  ).json;
  return { caleb, jake };
}

test(
  "a chat sees nothing of the board until it is linked with the team's code",
  { skip },
  async () => {
    const { caleb } = await chat();
    const before = await call(`/api/chats/${caleb.chat}/team`, {
      chat: caleb.token,
    });
    assert.equal(before.status, 200);
    assert.equal(before.json.linked, false);
    assert.equal(
      before.json.tasks,
      undefined,
      "no tasks leak to an unlinked chat",
    );
    const wrong = await call(`/api/chats/${caleb.chat}/team/link`, {
      method: "POST",
      chat: caleb.token,
      body: { code: "guess" },
    });
    assert.equal(wrong.status, 403);
    const right = await call(`/api/chats/${caleb.chat}/team/link`, {
      method: "POST",
      chat: caleb.token,
      body: { code: CODE },
    });
    assert.equal(right.status, 200);
    const board = (
      await call(`/api/chats/${caleb.chat}/team`, { chat: caleb.token })
    ).json;
    assert.equal(board.linked, true);
    const ids = board.tasks.map((t) => t.id);
    assert.ok(ids.includes("CHW-1"));
    assert.ok(!ids.includes("CHW-2"), "the inbox arrives as a count, not as tasks");
    assert.equal(board.counts.inbox, 1);
  },
);

test(
  "another chat's member cannot read or write a linked chat's board",
  { skip },
  async () => {
    const { caleb } = await chat();
    await call(`/api/chats/${caleb.chat}/team/link`, {
      method: "POST",
      chat: caleb.token,
      body: { code: CODE },
    });
    const other = await chat();
    const peek = await call(`/api/chats/${caleb.chat}/team`, {
      chat: other.caleb.token,
    });
    assert.equal(peek.status, 403);
    const own = (
      await call(`/api/chats/${other.caleb.chat}/team`, {
        chat: other.caleb.token,
      })
    ).json;
    assert.equal(own.linked, false, "linking one chat links no other");
  },
);

test(
  "writes need a name from members.json, and the activity log carries it",
  { skip },
  async () => {
    const { caleb, jake } = await chat();
    await call(`/api/chats/${caleb.chat}/team/link`, {
      method: "POST",
      chat: caleb.token,
      body: { code: CODE },
    });
    const anon = await call(`/api/chats/${jake.chat}/team/tasks/CHW-1`, {
      method: "PATCH",
      chat: jake.token,
      body: { status: "in_progress" },
    });
    assert.equal(anon.status, 403, "nobody writes before saying who they are");
    const impostor = await call(`/api/chats/${jake.chat}/team/me`, {
      method: "POST",
      chat: jake.token,
      body: { name: "Mallory" },
    });
    assert.equal(impostor.status, 400);
    assert.equal(
      (
        await call(`/api/chats/${jake.chat}/team/me`, {
          method: "POST",
          chat: jake.token,
          body: { name: "Jake" },
        })
      ).status,
      200,
    );
    const moved = await call(`/api/chats/${jake.chat}/team/tasks/CHW-1`, {
      method: "PATCH",
      chat: jake.token,
      body: { status: "in_progress" },
    });
    assert.equal(moved.status, 200);
    const file = await readFile(path.join(DIR, "team/tasks/CHW-1.md"), "utf8");
    assert.match(file, /^status: in_progress$/m);
    assert.match(file, /Jake: moved to in progress$/m);
    const board = (
      await call(`/api/chats/${caleb.chat}/team`, { chat: caleb.token })
    ).json;
    assert.equal(
      board.tasks.find((t) => t.id === "CHW-1").status,
      "in_progress",
      "the next read shows the write, not a cached copy",
    );
  },
);

test("done needs proof, and proof must be a web link", { skip }, async () => {
  const { caleb } = await chat();
  await call(`/api/chats/${caleb.chat}/team/link`, {
    method: "POST",
    chat: caleb.token,
    body: { code: CODE },
  });
  await call(`/api/chats/${caleb.chat}/team/me`, {
    method: "POST",
    chat: caleb.token,
    body: { name: "Caleb" },
  });
  const before = (await stat(path.join(DIR, "team/tasks/CHW-1.md"))).mtimeMs;
  await new Promise((r) => setTimeout(r, 20));
  const bare = await call(`/api/chats/${caleb.chat}/team/tasks/CHW-1`, {
    method: "PATCH",
    chat: caleb.token,
    body: { status: "done" },
  });
  assert.equal(bare.status, 400);
  // Not just "the status didn't change": on GitHub an unchanged write is
  // still an empty commit on main, which is what this once did.
  assert.equal(
    (await stat(path.join(DIR, "team/tasks/CHW-1.md"))).mtimeMs,
    before,
    "a refused done does not touch the file",
  );
  assert.doesNotMatch(
    await readFile(path.join(DIR, "team/tasks/CHW-1.md"), "utf8"),
    /^status: done$/m,
    "a refused done writes nothing",
  );
  const script = await call(`/api/chats/${caleb.chat}/team/tasks/CHW-1`, {
    method: "PATCH",
    chat: caleb.token,
    body: { status: "done", proof: "javascript:alert(1)" },
  });
  assert.equal(script.status, 400);
  const real = await call(`/api/chats/${caleb.chat}/team/tasks/CHW-1`, {
    method: "PATCH",
    chat: caleb.token,
    body: {
      status: "done",
      proof: "https://github.com/calebnewtonusc/Chewbacca/commit/abc1234",
    },
  });
  assert.equal(real.status, 200);
  assert.equal(real.json.task.status, "done");
});

test(
  "a task added from the chat gets the next id, defaults to its maker, and refuses an unknown owner",
  { skip },
  async () => {
    const { caleb } = await chat();
    await call(`/api/chats/${caleb.chat}/team/link`, {
      method: "POST",
      chat: caleb.token,
      body: { code: CODE },
    });
    await call(`/api/chats/${caleb.chat}/team/me`, {
      method: "POST",
      chat: caleb.token,
      body: { name: "Caleb" },
    });
    const stranger = await call(`/api/chats/${caleb.chat}/team/tasks`, {
      method: "POST",
      chat: caleb.token,
      body: { title: "x", owner: "Mallory" },
    });
    assert.equal(stranger.status, 400);
    const [a, b] = await Promise.all([
      call(`/api/chats/${caleb.chat}/team/tasks`, {
        method: "POST",
        chat: caleb.token,
        body: { title: "Book Jonah's call", due: "2026-10-13" },
      }),
      call(`/api/chats/${caleb.chat}/team/tasks`, {
        method: "POST",
        chat: caleb.token,
        body: { title: "Record the demo", owner: "Semyon" },
      }),
    ]);
    assert.equal(a.status, 200);
    assert.equal(b.status, 200);
    assert.notEqual(
      a.json.task.id,
      b.json.task.id,
      "two adds at once never share an id",
    );
    assert.equal(a.json.task.owner, "Caleb");
    assert.equal(b.json.task.owner, "Semyon");
    assert.match(
      await readFile(path.join(DIR, `team/tasks/${a.json.task.id}.md`), "utf8"),
      /^source: amber$/m,
    );
  },
);

test("done with an empty proof cannot clear the proof a task already has", { skip }, async () => {
  const { caleb } = await chat();
  await call(`/api/chats/${caleb.chat}/team/link`, { method: "POST", chat: caleb.token, body: { code: CODE } });
  await call(`/api/chats/${caleb.chat}/team/me`, { method: "POST", chat: caleb.token, body: { name: "Caleb" } });
  const made = (await call(`/api/chats/${caleb.chat}/team/tasks`, { method: "POST", chat: caleb.token, body: { title: "Has proof" } })).json.task;
  await call(`/api/chats/${caleb.chat}/team/tasks/${made.id}`, { method: "PATCH", chat: caleb.token, body: { proof: "https://example.com/video" } });
  const sneaky = await call(`/api/chats/${caleb.chat}/team/tasks/${made.id}`, { method: "PATCH", chat: caleb.token, body: { status: "done", proof: "" } });
  assert.equal(sneaky.status, 400);
});

test("someone with a name cannot switch to a name another member of the chat holds", { skip }, async () => {
  const { caleb, jake } = await chat();
  await call(`/api/chats/${caleb.chat}/team/link`, { method: "POST", chat: caleb.token, body: { code: CODE } });
  await call(`/api/chats/${caleb.chat}/team/me`, { method: "POST", chat: caleb.token, body: { name: "Caleb" } });
  await call(`/api/chats/${jake.chat}/team/me`, { method: "POST", chat: jake.token, body: { name: "Jake" } });
  const swap = await call(`/api/chats/${jake.chat}/team/me`, { method: "POST", chat: jake.token, body: { name: "Caleb" } });
  assert.equal(swap.status, 409);
  const fix = await call(`/api/chats/${jake.chat}/team/me`, { method: "POST", chat: jake.token, body: { name: "Semyon" } });
  assert.equal(fix.status, 200, "a mis-tap can still be fixed to a free name");
});

test("a newest task file that does not parse still counts toward the next id", { skip }, async () => {
  const { readdir } = await import("node:fs/promises");
  const top = Math.max(0, ...(await readdir(path.join(DIR, "team/tasks"))).map((n) => Number(/^CHW-(\d+)\.md$/.exec(n)?.[1] || 0)));
  const broken = top + 50;
  await writeFile(path.join(DIR, `team/tasks/CHW-${broken}.md`), "not a task file\n");
  const { caleb } = await chat();
  await call(`/api/chats/${caleb.chat}/team/link`, { method: "POST", chat: caleb.token, body: { code: CODE } });
  await call(`/api/chats/${caleb.chat}/team/me`, { method: "POST", chat: caleb.token, body: { name: "Caleb" } });
  const made = await call(`/api/chats/${caleb.chat}/team/tasks`, { method: "POST", chat: caleb.token, body: { title: "After a broken file" } });
  assert.equal(made.status, 200);
  assert.equal(made.json.task.id, `CHW-${broken + 1}`);
});

test("a second member taking a name already held here needs the team code", { skip }, async () => {
  const { caleb, jake } = await chat();
  await call(`/api/chats/${caleb.chat}/team/link`, { method: "POST", chat: caleb.token, body: { code: CODE } });
  await call(`/api/chats/${caleb.chat}/team/me`, { method: "POST", chat: caleb.token, body: { name: "Caleb" } });
  const bare = await call(`/api/chats/${jake.chat}/team/me`, { method: "POST", chat: jake.token, body: { name: "Caleb" } });
  assert.equal(bare.status, 409);
  const wrong = await call(`/api/chats/${jake.chat}/team/me`, { method: "POST", chat: jake.token, body: { name: "Caleb", code: "nope" } });
  assert.equal(wrong.status, 403);
  const right = await call(`/api/chats/${jake.chat}/team/me`, { method: "POST", chat: jake.token, body: { name: "Caleb", code: CODE } });
  assert.equal(right.status, 200);
});

test("wrong codes stop after ten in an hour", { skip }, async () => {
  const { caleb } = await chat();
  let last;
  for (let i = 0; i < 11; i++) last = await call(`/api/chats/${caleb.chat}/team/link`, { method: "POST", chat: caleb.token, body: { code: `guess-${i}` } });
  assert.equal(last.status, 429);
  const right = await call(`/api/chats/${caleb.chat}/team/link`, { method: "POST", chat: caleb.token, body: { code: CODE } });
  assert.equal(right.status, 429, "even the right code waits out the hour");
});

test("the code check and the headline need a teammate name first", { skip }, async () => {
  const { caleb } = await chat();
  await call(`/api/chats/${caleb.chat}/team/link`, { method: "POST", chat: caleb.token, body: { code: CODE } });
  const check = await call(`/api/chats/${caleb.chat}/team/tasks/CHW-1/check`, { method: "POST", chat: caleb.token, body: {} });
  assert.equal(check.status, 403);
  const head = await call(`/api/chats/${caleb.chat}/team/headline`, { method: "POST", chat: caleb.token, body: { updates: ["finished CHW-1 x"] } });
  assert.equal(head.status, 403);
});
