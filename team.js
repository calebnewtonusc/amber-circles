// The Chewbacca team board, inside a group chat. The board is one markdown file
// per task in calebnewtonusc/Chewbacca (team/tasks/CHW-12.md); the web board
// and the `team` CLI already read and write those files, and this is a third
// writer of the same files, so nothing here keeps its own copy of a task.
//
// A chat sees the board only after someone in it links it with TEAM_LINK_CODE,
// and each person says once which teammate they are. Writes then commit to
// main as the server's GitHub token, with the teammate's name in the commit and
// in the task's activity, the same way the web board logs who did what.
//
// TEAM_LOCAL_DIR swaps GitHub for a folder of task files, for local tests.
import { readFile, readdir, writeFile, mkdir } from "node:fs/promises";
import { createHash, timingSafeEqual } from "node:crypto";
import path from "node:path";
import {
  ID_PATTERN,
  PRIORITIES,
  STATUSES,
  idNumber,
  oneLine,
  parse,
  render,
} from "./team-task.js";

const REPO = process.env.TEAM_REPO || "calebnewtonusc/Chewbacca";
const BRANCH = process.env.TEAM_BRANCH || "main";
const TASK_DIR = "team/tasks";
const TZ = process.env.TEAM_TZ || "America/Los_Angeles";
// Same as WRITE_TRIES in apps/team-web/server.js: two writers in one second is
// the realistic worst case for a four-person team.
const WRITE_TRIES = 3;
// The board had 187 files on 2026-10-09 and a phone opens it every few seconds
// while someone is in it; 15s keeps that to one tree call per person-session
// and still shows a teammate's change by the next open.
const LIST_TTL_MS = 15_000;
// Done tasks stay on the phone for two weeks so Friday's proof is still
// visible the next Friday; older ones live on the web board.
const DONE_DAYS = 14;
// What a phone carries. The board's inbox (107 untriaged on 2026-10-09) and
// ideas (28) are triage work for the web board, so they arrive as counts only.
const SHOWN = new Set(["todo", "in_progress", "in_review", "backlog", "done"]);
// Guessed, never measured: small enough that a cold start did not reset, and
// 187 files is then 16 rounds.
const BLOB_BATCH = 12;
const LIMITS = { title: 200, done_when: 600, proof: 500, comment: 2000 };

export function teamConfigured() {
  return Boolean(
    process.env.TEAM_LINK_CODE &&
      (process.env.TEAM_GITHUB_TOKEN || process.env.TEAM_LOCAL_DIR),
  );
}

const today = () =>
  new Intl.DateTimeFormat("en-CA", { timeZone: TZ }).format(new Date());
const b64 = (s) => Buffer.from(s, "utf8").toString("base64");
const unb64 = (s) => Buffer.from(s, "base64").toString("utf8");

// ---------- storage: GitHub, or a local folder for tests ----------

async function gh(pathname, options = {}) {
  const res = await fetch(`https://api.github.com${pathname}`, {
    ...options,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${process.env.TEAM_GITHUB_TOKEN}`,
      "X-GitHub-Api-Version": "2022-11-28",
      "User-Agent": "amber-circles-team",
      ...(options.body ? { "Content-Type": "application/json" } : {}),
    },
  });
  const text = await res.text();
  let json = null;
  try {
    json = text ? JSON.parse(text) : null;
  } catch {
    json = null;
  }
  return { status: res.status, json };
}

const local = () => process.env.TEAM_LOCAL_DIR;
const blobCache = new Map();
// maxId comes from file names, not parsed tasks: a newest file that failed to
// fetch or parse would otherwise hand out its own id again on every create.
let listed = { at: 0, tasks: null, maxId: 0 };

async function listTasks({ fresh = false } = {}) {
  if (!fresh && listed.tasks && Date.now() - listed.at < LIST_TTL_MS)
    return listed.tasks;
  let tasks;
  let names;
  if (local()) {
    const dir = path.join(local(), TASK_DIR);
    names = (await readdir(dir).catch(() => [])).filter((n) =>
      n.endsWith(".md"),
    );
    tasks = await Promise.all(
      names.map(async (n) => {
        try {
          const t = parse(await readFile(path.join(dir, n), "utf8"));
          return t.id === n.slice(0, -3) ? t : null;
        } catch {
          return null;
        }
      }),
    );
  } else {
    // One tree call lists every file with its blob sha; only changed blobs are fetched.
    const tree = await gh(`/repos/${REPO}/git/trees/${BRANCH}:${TASK_DIR}`);
    if (tree.status !== 200)
      throw Object.assign(new Error("GitHub did not return the board"), {
        status: 502,
      });
    const files = tree.json.tree.filter(
      (f) => f.type === "blob" && f.path.endsWith(".md"),
    );
    // A cold start fetched all 187 blobs at once and GitHub reset the
    // connection (ECONNRESET, 2026-10-09), so blobs come a few at a time.
    names = files.map((f) => f.path);
    const missing = files.filter((f) => !blobCache.has(f.sha));
    for (let i = 0; i < missing.length; i += BLOB_BATCH) {
      await Promise.all(
        missing.slice(i, i + BLOB_BATCH).map(async (f) => {
          const blob = await gh(`/repos/${REPO}/git/blobs/${f.sha}`).catch(
            () => null,
          );
          if (blob?.status !== 200) return;
          try {
            blobCache.set(f.sha, parse(unb64(blob.json.content)));
          } catch {
            // An unparseable file is left off the board, as on the web.
          }
        }),
      );
    }
    tasks = files.map((f) => {
      const t = blobCache.get(f.sha);
      return t && t.id === f.path.slice(0, -3) ? t : null;
    });
  }
  tasks = tasks.filter(Boolean).sort((a, b) => idNumber(a.id) - idNumber(b.id));
  const maxId = Math.max(0, ...names.map((n) => idNumber(n.slice(0, -3))));
  listed = { at: Date.now(), tasks, maxId };
  return tasks;
}

// members.json changes a few times a semester and every board open read it,
// about 450 GitHub calls an hour per open phone (review, 2026-10-09).
const MEMBERS_TTL_MS = 60_000;
let membersCache = { at: 0, list: null };

async function readMembers() {
  if (membersCache.list && Date.now() - membersCache.at < MEMBERS_TTL_MS) return membersCache.list;
  const list = await readMembersFresh();
  if (list.length) membersCache = { at: Date.now(), list };
  return list;
}

async function readMembersFresh() {
  try {
    const raw = local()
      ? await readFile(path.join(local(), "team/members.json"), "utf8")
      : await gh(
          `/repos/${REPO}/contents/team/members.json?ref=${BRANCH}`,
        ).then((r) => (r.status === 200 ? unb64(r.json.content) : "[]"));
    const list = JSON.parse(raw);
    return Array.isArray(list)
      ? list
          .filter((m) => m && typeof m.name === "string")
          .map((m) => ({ name: m.name, role: m.role || "" }))
      : [];
  } catch {
    return [];
  }
}

/** Reads a task fresh, lets `change` edit it, writes it back; retried when someone else wrote first. `change` returning null writes nothing. */
async function writeTask(id, message, change, { create = false } = {}) {
  const file = `${TASK_DIR}/${id}.md`;
  for (let attempt = 0; attempt < WRITE_TRIES; attempt++) {
    if (local()) {
      const full = path.join(local(), file);
      const existing = await readFile(full, "utf8").catch(() => null);
      if (create ? existing !== null : existing === null)
        return { conflict: create, missing: !create };
      const task = change(existing ? parse(existing) : null);
      if (!task) return { aborted: true };
      await mkdir(path.dirname(full), { recursive: true });
      // "wx" fails if the file appeared meanwhile, like GitHub's 422 on a create.
      try {
        await writeFile(
          full,
          render(task),
          create ? { flag: "wx" } : undefined,
        );
      } catch (error) {
        if (error.code === "EEXIST") return { conflict: true };
        throw error;
      }
      listed.at = 0;
      return { task };
    }
    const cur = create
      ? null
      : await gh(`/repos/${REPO}/contents/${file}?ref=${BRANCH}`);
    if (cur && cur.status === 404) return { missing: true };
    if (cur && cur.status !== 200)
      throw Object.assign(new Error("GitHub did not return the task"), {
        status: 502,
      });
    const task = change(cur ? parse(unb64(cur.json.content)) : null);
    if (!task) return { aborted: true };
    const put = await gh(`/repos/${REPO}/contents/${file}`, {
      method: "PUT",
      body: JSON.stringify({
        message,
        content: b64(render(task)),
        branch: BRANCH,
        ...(cur ? { sha: cur.json.sha } : {}),
      }),
    });
    if (put.status === 200 || put.status === 201) {
      listed.at = 0;
      return { task };
    }
    // 409/422: the file changed (or, on create, appeared) since we read it.
    if (put.status !== 409 && put.status !== 422)
      throw Object.assign(new Error("GitHub refused the write"), {
        status: 502,
      });
    if (create) return { conflict: true };
  }
  return { conflict: true };
}

// ---------- shaping for the phone ----------

function forPhone(t) {
  return {
    id: t.id,
    title: t.title,
    status: t.status,
    owner: t.owner,
    priority: t.priority || "none",
    due: t.due,
    done_when: t.done_when,
    proof: t.proof,
    labels: t.labels,
    updated: t.updated,
    notes: (t.notes || "").slice(0, 600),
    activity: (t.activity || []).slice(-6),
  };
}

function daysAgo(day) {
  const ms =
    Date.parse(`${today()}T00:00:00Z`) - Date.parse(`${day}T00:00:00Z`);
  return Number.isFinite(ms) ? ms / 86_400_000 : Infinity;
}

// ---------- routes ----------

export function registerTeam(app, { pool, chatMemberIn, HttpError }) {
  const bad = (status, message) => {
    throw new HttpError(status, message);
  };

  function text(value, field, { required = false } = {}) {
    if (value === undefined || value === null)
      return required
        ? bad(400, `${field.replace("_", " ")} is required`)
        : undefined;
    if (typeof value !== "string")
      bad(400, `${field.replace("_", " ")} must be text`);
    const v = oneLine(value);
    if (required && !v) bad(400, `${field.replace("_", " ")} is required`);
    if (v.length > LIMITS[field])
      bad(400, `${field.replace("_", " ")} is too long`);
    return v;
  }

  function cleanChanges(body, members) {
    const out = {};
    for (const f of ["title", "done_when"]) {
      const v = text(body[f], f);
      if (v !== undefined) out[f] = v;
    }
    if (out.title === "") bad(400, "A task needs a title.");
    if (body.status !== undefined) {
      if (!STATUSES.includes(body.status))
        bad(400, "That status is not on the board.");
      out.status = body.status;
    }
    if (body.priority !== undefined) {
      if (!PRIORITIES.includes(body.priority))
        bad(400, "That priority is not on the board.");
      out.priority = body.priority;
    }
    if (body.due !== undefined) {
      if (body.due !== "" && !/^\d{4}-\d{2}-\d{2}$/.test(body.due))
        bad(400, "Due is a date like 2026-10-12.");
      out.due = body.due;
    }
    if (body.owner !== undefined) {
      if (typeof body.owner !== "string")
        bad(400, "Owner must be a teammate's name.");
      if (body.owner && !members.some((m) => m.name === body.owner))
        bad(400, `${oneLine(body.owner).slice(0, 40)} is not on the team.`);
      out.owner = body.owner;
    }
    if (body.proof !== undefined) {
      const proof = text(body.proof, "proof");
      // The board renders proof as a link, so only web links (a javascript: URL would run on tap).
      if (proof && !/^https?:\/\/\S+$/i.test(proof))
        bad(400, "Proof is a link: a commit, a video or a page.");
      out.proof = proof;
    }
    return out;
  }

  function verbFor(changes) {
    if (changes.status) return `moved to ${changes.status.replace("_", " ")}`;
    if ("owner" in changes)
      return changes.owner ? `assigned to ${changes.owner}` : "unassigned";
    return (
      "edited " +
      Object.keys(changes)
        .map((k) => k.replace("_", " "))
        .join(", ")
    );
  }

  async function linkedMember(c) {
    if (!teamConfigured()) bad(503, "The team board is not switched on here.");
    const me = await chatMemberIn(c, c.req.param("id"));
    const { rows } = await pool.query(
      `select l.circle_id, p.team_name from team_links l
         left join team_people p on p.member_id = $2
        where l.circle_id = $1`,
      [me.circleId, me.id],
    );
    return {
      me,
      linked: Boolean(rows[0]),
      teamName: rows[0]?.team_name || null,
    };
  }

  async function writer(c) {
    const ctx = await linkedMember(c);
    if (!ctx.linked) bad(403, "Link this chat to the team board first.");
    if (!ctx.teamName) bad(403, "Say which teammate you are first.");
    return ctx;
  }

  app.get("/api/chats/:id/team", async (c) => {
    if (!teamConfigured()) return c.json({ available: false, linked: false });
    const { linked, teamName } = await linkedMember(c);
    if (!linked) return c.json({ available: true, linked: false });
    const [all, members] = await Promise.all([listTasks(), readMembers()]);
    const counts = {};
    for (const t of all) counts[t.status] = (counts[t.status] || 0) + 1;
    const tasks = all
      .filter(
        (t) =>
          SHOWN.has(t.status) &&
          (t.status !== "done" || daysAgo(t.updated) <= DONE_DAYS),
      )
      .map(forPhone);
    return c.json({
      available: true,
      linked: true,
      me: teamName,
      members,
      tasks,
      counts,
      today: today(),
      repo: REPO,
    });
  });

  app.post("/api/chats/:id/team/link", async (c) => {
    if (!teamConfigured()) bad(503, "The team board is not switched on here.");
    const me = await chatMemberIn(c, c.req.param("id"));
    const body = await c.req.json().catch(() => ({}));
    const given = createHash("sha256")
      .update(
        String(body.code ?? "")
          .trim()
          .toLowerCase(),
      )
      .digest();
    const wanted = createHash("sha256")
      .update(process.env.TEAM_LINK_CODE.trim().toLowerCase())
      .digest();
    if (!timingSafeEqual(given, wanted))
      bad(403, "That code is not the team's. Ask Caleb for it.");
    await pool.query(
      "insert into team_links (circle_id, linked_by) values ($1, $2) on conflict (circle_id) do nothing",
      [me.circleId, me.id],
    );
    return c.json({ ok: true });
  });

  app.post("/api/chats/:id/team/me", async (c) => {
    const { me, linked } = await linkedMember(c);
    if (!linked) bad(403, "Link this chat to the team board first.");
    const body = await c.req.json().catch(() => ({}));
    const members = await readMembers();
    const name = typeof body.name === "string" ? body.name : "";
    if (!members.some((m) => m.name === name))
      bad(400, "Pick your name from the team.");
    // A name can be claimed again in the same chat (your phone and your Mac
    // are two members), but someone who already has a name cannot switch to
    // a name another member holds: before this, anyone could move tasks as
    // "Caleb" and switch back (review, 2026-10-09).
    const { rows: held } = await pool.query(
      `select p.member_id, p.team_name from team_people p join members m on m.id = p.member_id
        where m.circle_id = $1`,
      [me.circleId],
    );
    const mine = held.find((r) => r.member_id === me.id);
    const takenByOther = held.some((r) => r.team_name === name && r.member_id !== me.id);
    if (mine && mine.team_name !== name && takenByOther)
      bad(409, `${name} is already someone else in this chat.`);
    await pool.query(
      `insert into team_people (member_id, team_name) values ($1, $2)
       on conflict (member_id) do update set team_name = excluded.team_name`,
      [me.id, name],
    );
    return c.json({ ok: true, me: name });
  });

  app.post("/api/chats/:id/team/tasks", async (c) => {
    const { teamName } = await writer(c);
    const body = await c.req.json().catch(() => ({}));
    const members = await readMembers();
    const changes = cleanChanges(body, members);
    if (!changes.title) bad(400, "A task needs a title.");
    for (let attempt = 0; attempt < WRITE_TRIES; attempt++) {
      await listTasks({ fresh: true });
      const id = `CHW-${listed.maxId + 1}`;
      const { task, conflict } = await writeTask(
        id,
        `team: ${id} created: ${changes.title} (${teamName}, from Amber)`,
        () => ({
          id,
          title: changes.title,
          status: changes.status || "todo",
          area: "",
          parent: "",
          owner: changes.owner ?? teamName,
          priority: changes.priority || "none",
          due: changes.due || "",
          labels: [],
          done_when: changes.done_when || "",
          proof: "",
          source: "amber",
          created: today(),
          updated: today(),
          notes: "",
          activity: [`${today()} ${teamName}: created from the group chat`],
        }),
        { create: true },
      );
      if (task) return c.json({ task: forPhone(task) });
      if (!conflict) break;
    }
    bad(409, "Someone else just added a task. Try again.");
  });

  app.patch("/api/chats/:id/team/tasks/:task", async (c) => {
    const { teamName } = await writer(c);
    const id = c.req.param("task");
    if (!ID_PATTERN.test(id)) bad(400, "That is not a task id.");
    const body = await c.req.json().catch(() => ({}));
    const members = await readMembers();
    const changes = cleanChanges(body, members);
    const comment = text(body.comment, "comment");
    if (!Object.keys(changes).length && !comment)
      bad(400, "Nothing to change.");
    let refused = null;
    const verb = comment || verbFor(changes);
    const { task, missing, conflict } = await writeTask(
      id,
      `team: ${id} ${comment ? "comment" : verb} (${teamName}, from Amber)`,
      (t) => {
        // Checked on the fresh read, so proof added on the web a second ago counts.
        // "proof" in changes, so {status: done, proof: ""} cannot clear a task's
        // proof on the way to done (review, 2026-10-09).
        const proof = "proof" in changes ? changes.proof : t.proof;
        if ((changes.status ?? t.status) === "done" && !proof) {
          refused = "Done needs proof: a link to the commit, video or page.";
          // Null writes nothing. Returning the task unchanged still made an
          // empty "moved to done" commit on GitHub (scratch branch, 2026-10-09).
          return null;
        }
        Object.assign(t, changes, { updated: today() });
        t.activity.push(`${today()} ${teamName}: ${verb}`);
        return t;
      },
    );
    if (refused) bad(400, refused);
    if (missing) bad(404, `There is no ${id} on the board.`);
    if (conflict) bad(409, "Someone else is editing this task. Try again.");
    return c.json({ task: forPhone(task) });
  });
}
