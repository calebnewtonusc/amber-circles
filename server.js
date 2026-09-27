import {
  createHash,
  createHmac,
  randomBytes,
  createCipheriv,
  createDecipheriv,
  timingSafeEqual,
} from "node:crypto";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";
import { Hono } from "hono";
import { serve } from "@hono/node-server";
import { serveStatic } from "@hono/node-server/serve-static";
import pg from "pg";
import { streamSSE } from "hono/streaming";
import { build, titleFrom } from "./builder.js";

const here = path.dirname(fileURLToPath(import.meta.url));
const PORT = Number(process.env.PORT || 8787);
const DATABASE_URL =
  process.env.DATABASE_URL || "postgres://localhost:5433/amber";
const IS_PRODUCTION = process.env.NODE_ENV === "production";

if (IS_PRODUCTION && !process.env.AMBER_SECRET) {
  throw new Error(
    "AMBER_SECRET is required in production: it seals member links and signs frame tickets.",
  );
}
const SECRET = createHash("sha256")
  .update(process.env.AMBER_SECRET || "amber-dev-secret-not-for-production")
  .digest();

// Railway's private network is plain TCP inside the project, so no TLS here.
const pool = new pg.Pool({ connectionString: DATABASE_URL });

const BRIDGE = readFileSync(path.join(here, "public", "bridge.js"), "utf8");

// Limits. Each one is guessed, never measured under real load: a club of 60
// checking in weekly for a semester writes about 900 records, so 5,000 per
// tool is five semesters of headroom, and 64KB per record is ten times the
// largest attendance record the demo tool writes.
const MAX_RECORDS_PER_TOOL = 5000;
const MAX_RECORD_BYTES = 64 * 1024;
const MAX_TOOL_HTML_BYTES = 512 * 1024;
const FRAME_TICKET_SECONDS = 300;

// ---------- small helpers ----------

const newId = (prefix) => `${prefix}_${randomBytes(9).toString("base64url")}`;
const newToken = () => randomBytes(24).toString("base64url");
const hash = (value) => createHash("sha256").update(value).digest("hex");

function seal(plain) {
  const iv = randomBytes(12);
  const cipher = createCipheriv("aes-256-gcm", SECRET, iv);
  const body = Buffer.concat([cipher.update(plain, "utf8"), cipher.final()]);
  return Buffer.concat([iv, cipher.getAuthTag(), body]).toString("base64url");
}

function unseal(sealed) {
  const raw = Buffer.from(sealed, "base64url");
  const decipher = createDecipheriv("aes-256-gcm", SECRET, raw.subarray(0, 12));
  decipher.setAuthTag(raw.subarray(12, 28));
  return Buffer.concat([
    decipher.update(raw.subarray(28)),
    decipher.final(),
  ]).toString("utf8");
}

function signTicket(slug, memberId) {
  const expires = Math.floor(Date.now() / 1000) + FRAME_TICKET_SECONDS;
  const payload = `${slug}.${memberId}.${expires}`;
  const signature = createHmac("sha256", SECRET)
    .update(payload)
    .digest("base64url");
  return `${expires}.${signature}.${memberId}`;
}

function verifyTicket(slug, ticket) {
  const [expires, signature, memberId] = String(ticket || "").split(".");
  if (!expires || !signature || !memberId) return null;
  if (Number(expires) < Date.now() / 1000) return null;
  const expected = createHmac("sha256", SECRET)
    .update(`${slug}.${memberId}.${expires}`)
    .digest();
  const given = Buffer.from(signature, "base64url");
  if (given.length !== expected.length || !timingSafeEqual(given, expected))
    return null;
  return memberId;
}

function slugify(title) {
  const base =
    String(title)
      .toLowerCase()
      .replace(/[^a-z0-9]+/g, "-")
      .replace(/^-|-$/g, "")
      .slice(0, 40) || "tool";
  return `${base}-${randomBytes(3).toString("hex")}`;
}

function publicUrl(c) {
  if (process.env.PUBLIC_URL) return process.env.PUBLIC_URL.replace(/\/$/, "");
  const proto = c.req.header("x-forwarded-proto") || "http";
  return `${proto}://${c.req.header("host")}`;
}

class HttpError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

function requireText(value, field, max = 200) {
  if (typeof value !== "string" || !value.trim())
    throw new HttpError(400, `${field} is required`);
  if (value.length > max)
    throw new HttpError(400, `${field} must be ${max} characters or fewer`);
  return value.trim();
}

function normalizePhone(value) {
  if (value == null || value === "") return null;
  const digits = String(value).replace(/[^\d+]/g, "");
  if (digits.replace(/\D/g, "").length < 7)
    throw new HttpError(400, `"${value}" does not look like a phone number`);
  return digits;
}

// ---------- data access ----------

async function ownerFromKey(key) {
  if (!key) return null;
  const { rows } = await pool.query(
    "select id, name from owners where key_hash = $1",
    [hash(key)],
  );
  return rows[0] || null;
}

async function requireOwner(c) {
  const header = c.req.header("authorization") || "";
  const owner = await ownerFromKey(header.replace(/^Bearer\s+/i, ""));
  if (!owner)
    throw new HttpError(
      401,
      "Sign in again: this browser does not hold a valid Amber owner key.",
    );
  return owner;
}

async function addMember(client, circleId, { name, phone, isOwner = false }) {
  const token = newToken();
  const id = newId("mem");
  await client.query(
    `insert into members (id, circle_id, name, phone, is_owner, token_hash, token_hint, token_sealed)
     values ($1, $2, $3, $4, $5, $6, $7, $8)`,
    [
      id,
      circleId,
      requireText(name, "name", 80),
      normalizePhone(phone),
      isOwner,
      hash(token),
      token.slice(0, 4),
      seal(token),
    ],
  );
  return { id, token };
}

async function createCircle(owner, name, members = []) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    const id = newId("cir");
    await client.query(
      "insert into circles (id, owner_id, name) values ($1, $2, $3)",
      [id, owner.id, requireText(name, "circle name", 80)],
    );
    await addMember(client, id, { name: owner.name, isOwner: true });
    for (const member of members) await addMember(client, id, member);
    await client.query("commit");
    return id;
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function findCircle(owner, circleRef) {
  const ref = requireText(circleRef, "circle", 120);
  const { rows } = await pool.query(
    "select id, name from circles where owner_id = $1 and (id = $2 or lower(name) = lower($2)) order by created_at limit 1",
    [owner.id, ref],
  );
  if (!rows[0])
    throw new HttpError(
      404,
      `No circle called "${ref}". Create it first, or pick one of yours.`,
    );
  return rows[0];
}

async function publishTool(
  owner,
  { title, description = "", circle, html, request = "" },
) {
  const target = await findCircle(owner, circle);
  const source = requireText(html, "html", MAX_TOOL_HTML_BYTES);
  const id = newId("tool");
  const slug = slugify(title);
  const client = await pool.connect();
  try {
    await client.query("begin");
    await client.query(
      `insert into tools (id, slug, owner_id, circle_id, title, description, html, request)
       values ($1, $2, $3, $4, $5, $6, $7, $8)`,
      [
        id,
        slug,
        owner.id,
        target.id,
        requireText(title, "title", 80),
        String(description).slice(0, 500),
        source,
        String(request).slice(0, 4000),
      ],
    );
    await client.query(
      "insert into tool_versions (tool_id, version, html, request) values ($1, 1, $2, $3)",
      [id, source, String(request).slice(0, 4000)],
    );
    await client.query("commit");
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
  return { slug, circle: target.name };
}

// Guessed, never measured: two megabytes is roughly 2,000 prayer requests
// with their authors, far past a real group's semester, and small enough
// that keeping one per version costs nothing worth counting.
const MAX_SNAPSHOT_BYTES = 2 * 1024 * 1024;

async function snapshotRecords(client, toolId) {
  const { rows } = await client.query(
    "select id, collection, data, author_id, created_at, updated_at from records where tool_id = $1 order by created_at",
    [toolId],
  );
  const json = JSON.stringify(rows);
  return Buffer.byteLength(json) > MAX_SNAPSHOT_BYTES ? null : json;
}

async function updateTool(
  owner,
  slug,
  { html, title, description, request = "" },
) {
  const client = await pool.connect();
  try {
    await client.query("begin");
    const { rows } = await client.query(
      `update tools set
         html = coalesce($3, html),
         title = coalesce($4, title),
         description = coalesce($5, description),
         version = version + 1,
         updated_at = now()
       where owner_id = $1 and slug = $2
       returning id, slug, version, html`,
      [
        owner.id,
        slug,
        html ? requireText(html, "html", MAX_TOOL_HTML_BYTES) : null,
        title ? requireText(title, "title", 80) : null,
        description ?? null,
      ],
    );
    if (!rows[0])
      throw new HttpError(404, "No tool with that link belongs to you.");
    // The entries as they stand at this moment travel with the new version,
    // so "go back" can offer to put them back too.
    const snapshot = await snapshotRecords(client, rows[0].id);
    await client.query(
      "insert into tool_versions (tool_id, version, html, request, data_snapshot) values ($1, $2, $3, $4, $5) on conflict do nothing",
      [
        rows[0].id,
        rows[0].version,
        rows[0].html,
        String(request).slice(0, 4000),
        snapshot,
      ],
    );
    await client.query("commit");
    return { slug: rows[0].slug, version: rows[0].version };
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
}

async function ownerOverview(owner, base) {
  const circles = await pool.query(
    `select c.id, c.name, c.created_at,
            coalesce(json_agg(json_build_object(
              'id', m.id, 'name', m.name, 'phone', m.phone, 'is_owner', m.is_owner, 'token_sealed', m.token_sealed,
              'here_now', coalesce(m.last_seen > now() - interval '2 minutes', false)
            ) order by m.is_owner desc, m.created_at) filter (where m.id is not null), '[]') as members
       from circles c left join members m on m.circle_id = c.id
      where c.owner_id = $1
      group by c.id order by c.created_at`,
    [owner.id],
  );
  const tools = await pool.query(
    `select t.slug, t.title, t.description, t.version, t.updated_at, t.created_at,
            (t.draft_html is not null) as has_draft, t.draft_request,
            c.id as circle_id, c.name as circle_name,
            (select count(*) from opens o where o.tool_id = t.id)::int as open_count,
            (select count(distinct o.member_id) from opens o where o.tool_id = t.id)::int as people_opened,
            (select max(o.at) from opens o where o.tool_id = t.id) as last_open,
            (select count(*) from records r where r.tool_id = t.id)::int as record_count,
            (select count(*) from access_requests a where a.tool_id = t.id and a.status = 'pending')::int as pending_requests,
            (select count(*) from members m where m.circle_id = t.circle_id and m.last_seen > now() - interval '2 minutes')::int as here_now,
            (select coalesce(json_agg(distinct o.member_id), '[]') from opens o where o.tool_id = t.id) as opened_by
       from tools t join circles c on c.id = t.circle_id
      where t.owner_id = $1 order by t.updated_at desc`,
    [owner.id],
  );
  return {
    owner,
    circles: circles.rows.map((circle) => ({
      ...circle,
      members: circle.members.map(({ token_sealed, ...member }) => ({
        ...member,
        token: token_sealed ? unseal(token_sealed) : null,
      })),
    })),
    tools: tools.rows.map((tool) => ({
      ...tool,
      url: `${base}/t/${tool.slug}`,
    })),
  };
}

async function memberForTool(slug, token) {
  const { rows } = await pool.query(
    `select t.id as tool_id, t.slug, t.title, t.description, t.version, t.circle_id,
            c.name as circle_name, o.name as owner_name,
            m.id as member_id, m.name as member_name, m.is_owner
       from tools t
       join circles c on c.id = t.circle_id
       join owners o on o.id = t.owner_id
       left join members m on m.circle_id = t.circle_id and m.token_hash = $2
      where t.slug = $1`,
    [slug, hash(String(token || ""))],
  );
  return rows[0] || null;
}

// ---------- the bridge: the only door a tool has to the world ----------

const COLLECTION = /^[a-z][a-z0-9_-]{0,39}$/i;

async function bridge(access, body) {
  const op = body?.op;
  const collection = body?.collection;
  const needsCollection = ["list", "add", "update", "remove"].includes(op);
  if (needsCollection && !COLLECTION.test(String(collection || ""))) {
    throw new HttpError(400, 'collection must be a short name like "checkins"');
  }
  switch (op) {
    case "stamp": {
      // A fingerprint of the tool's shared data, polled by the frame so one
      // person's check-in shows up on everyone else's screen. The same poll is
      // the presence heartbeat.
      await pool.query("update members set last_seen = now() where id = $1", [
        access.member_id,
      ]);
      const {
        rows: [row],
      } = await pool.query(
        "select count(*)::int as n, coalesce(max(updated_at), 'epoch')::text as at from records where tool_id = $1",
        [access.tool_id],
      );
      return `${row.n}:${row.at}`;
    }
    case "me":
      return {
        id: access.member_id,
        name: access.member_name,
        isOwner: access.is_owner,
      };
    case "circle":
      return { name: access.circle_name, owner: access.owner_name };
    case "people": {
      // Phones never cross into a tool. A tool that wants to reach someone asks
      // the frame to open the text thread, and only the circle owner can.
      const { rows } = await pool.query(
        'select id, name, is_owner as "isOwner" from members where circle_id = $1 order by is_owner desc, name',
        [access.circle_id],
      );
      return rows;
    }
    case "list": {
      const { rows } = await pool.query(
        `select r.id, r.data, r.created_at as "createdAt", r.updated_at as "updatedAt",
                json_build_object('id', m.id, 'name', m.name) as author
           from records r left join members m on m.id = r.author_id
          where r.tool_id = $1 and r.collection = $2 order by r.created_at`,
        [access.tool_id, collection],
      );
      return rows;
    }
    case "add": {
      const data = body.data ?? {};
      if (Buffer.byteLength(JSON.stringify(data)) > MAX_RECORD_BYTES)
        throw new HttpError(413, "That record is too large.");
      const {
        rows: [{ count }],
      } = await pool.query(
        "select count(*)::int as count from records where tool_id = $1",
        [access.tool_id],
      );
      if (count >= MAX_RECORDS_PER_TOOL)
        throw new HttpError(409, "This tool has hit its storage limit.");
      const id = newId("rec");
      await pool.query(
        "insert into records (id, tool_id, collection, data, author_id) values ($1, $2, $3, $4, $5)",
        [
          id,
          access.tool_id,
          collection,
          JSON.stringify(data),
          access.member_id,
        ],
      );
      return { id };
    }
    case "update": {
      const data = body.data ?? {};
      if (Buffer.byteLength(JSON.stringify(data)) > MAX_RECORD_BYTES)
        throw new HttpError(413, "That record is too large.");
      const { rowCount } = await pool.query(
        `update records set data = data || $4::jsonb, updated_at = now()
          where tool_id = $1 and collection = $2 and id = $3`,
        [access.tool_id, collection, String(body.id), JSON.stringify(data)],
      );
      if (!rowCount) throw new HttpError(404, "No record with that id.");
      return { id: body.id };
    }
    case "remove": {
      // Found by the commit security review, 2026-09-27: removal was only
      // hidden in the tool's UI, so any member could delete anyone's entry
      // from the browser console. People remove their own entries; the
      // circle's owner can remove any. Editing stays shared, because a
      // sign-up sheet needs people to claim slots someone else created.
      const { rowCount } = await pool.query(
        `delete from records
          where tool_id = $1 and collection = $2 and id = $3
            and ($5::boolean or author_id = $4)`,
        [
          access.tool_id,
          collection,
          String(body.id),
          access.member_id,
          Boolean(access.is_owner),
        ],
      );
      if (!rowCount)
        throw new HttpError(
          403,
          "Only the person who added this, or the group's owner, can remove it.",
        );
      return { id: body.id };
    }
    default:
      throw new HttpError(400, `Unknown bridge call "${op}".`);
  }
}

// ---------- the tool frame ----------

// A tool runs in a sandboxed iframe with an opaque origin, so it cannot read
// the member's link, cookies or storage. This policy also closes the network:
// it can load libraries from two CDNs and fonts, and it cannot send data
// anywhere. Its only way out is the bridge, which the parent page mediates.
const FRAME_CSP = [
  "default-src 'none'",
  "script-src 'unsafe-inline' https://cdn.jsdelivr.net https://unpkg.com",
  "style-src 'unsafe-inline' https://fonts.googleapis.com https://cdn.jsdelivr.net",
  "font-src https://fonts.gstatic.com data:",
  "img-src data: blob:",
  "connect-src 'none'",
  "form-action 'none'",
  "base-uri 'none'",
  "frame-ancestors 'self'",
].join("; ");

function frameDocument(html) {
  const inject = `<script>${BRIDGE}</script>`;
  if (/<head[^>]*>/i.test(html))
    return html.replace(/<head[^>]*>/i, (tag) => `${tag}${inject}`);
  return `<!doctype html><html><head><meta charset="utf-8">${inject}</head><body>${html}</body></html>`;
}

// ---------- MCP: publish straight from Claude ----------

const TOOL_GUIDE = `Write ONE self-contained HTML file. It runs in a sandbox inside Amber with no network access. Everything it needs comes from the global \`amber\` object, which is already defined:

  await amber.me()                        -> { id, name, isOwner }   the person viewing
  await amber.circle()                    -> { name, owner }
  await amber.people()                    -> [{ id, name, isOwner }] everyone in the circle
  await amber.list(collection)            -> [{ id, data, author: {id, name}, createdAt, updatedAt }]
  await amber.add(collection, data)       -> { id }     shared storage, visible to the whole circle
  await amber.update(collection, id, data) -> { id }    shallow-merges data
  await amber.remove(collection, id)
  amber.reachOut(memberId, message)       opens a text to that person; only works for the circle owner
  amber.onChange(callback)                fires when someone else in the circle changes data

Collection names are short words like "checkins". Libraries may load from cdn.jsdelivr.net or unpkg.com. fetch() is blocked. Design for a phone first: this opens from a text message. Show a loading state, an empty state and an error state.`;

const MCP_TOOLS = [
  {
    name: "list_circles",
    description:
      "List your Amber circles and who is in each. Circles are who a tool can be shared with.",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "create_circle",
    description:
      "Create an Amber circle: a named group of people (a club cabinet, a team, a trip). Each member gets a personal link.",
    inputSchema: {
      type: "object",
      required: ["name"],
      properties: {
        name: { type: "string" },
        members: {
          type: "array",
          items: {
            type: "object",
            required: ["name"],
            properties: { name: { type: "string" }, phone: { type: "string" } },
          },
        },
      },
    },
  },
  {
    name: "publish_tool",
    description: `Publish a small tool to Amber and share it with one circle, like sharing a Google Doc. Only people in that circle can open it, each through their own link. Returns the link.\n\n${TOOL_GUIDE}`,
    inputSchema: {
      type: "object",
      required: ["title", "circle", "html"],
      properties: {
        title: {
          type: "string",
          description: 'Short name, like "TTS Attendance"',
        },
        description: {
          type: "string",
          description: "One sentence on what it is for",
        },
        circle: {
          type: "string",
          description: "The circle name or id to share with",
        },
        html: { type: "string", description: "The complete HTML file" },
      },
    },
  },
  {
    name: "update_tool",
    description:
      "Replace a published tool's HTML (and optionally title or description). Everyone keeps their link and all shared data survives.",
    inputSchema: {
      type: "object",
      required: ["slug"],
      properties: {
        slug: { type: "string" },
        html: { type: "string" },
        title: { type: "string" },
        description: { type: "string" },
      },
    },
  },
  {
    name: "get_tool_source",
    description:
      "Read the current HTML of one of your published tools, to edit it.",
    inputSchema: {
      type: "object",
      required: ["slug"],
      properties: { slug: { type: "string" } },
    },
  },
];

async function callMcpTool(owner, name, args, base) {
  switch (name) {
    case "list_circles": {
      const { circles } = await ownerOverview(owner, base);
      return (
        circles
          .map(
            (circle) =>
              `${circle.name} (${circle.id}): ${circle.members.map((member) => member.name).join(", ")}`,
          )
          .join("\n") || "No circles yet."
      );
    }
    case "create_circle": {
      const id = await createCircle(owner, args.name, args.members || []);
      return `Created circle "${args.name}" (${id}). Share links are on the Amber dashboard: ${base}/`;
    }
    case "publish_tool": {
      const { slug, circle } = await publishTool(owner, args);
      return `Published "${args.title}" to ${circle}.\nLink: ${base}/t/${slug}\nEach member opens it through their own link, sent from ${base}/`;
    }
    case "update_tool": {
      const { version } = await updateTool(owner, args.slug, args);
      return `Updated ${args.slug} to version ${version}. Links and data are unchanged.`;
    }
    case "get_tool_source": {
      const { rows } = await pool.query(
        "select html from tools where owner_id = $1 and slug = $2",
        [owner.id, args.slug],
      );
      if (!rows[0])
        throw new HttpError(404, "No tool with that slug belongs to you.");
      return rows[0].html;
    }
    default:
      throw new HttpError(400, `Unknown tool ${name}`);
  }
}

// ---------- routes ----------

const app = new Hono();

app.onError((error, c) => {
  if (error instanceof HttpError)
    return c.json({ error: error.message }, error.status);
  console.error(error);
  return c.json(
    { error: "Something broke on our side. Try again in a moment." },
    500,
  );
});

app.use("*", async (c, next) => {
  await next();
  c.header("x-content-type-options", "nosniff");
  c.header("referrer-policy", "no-referrer");
  if (
    !c.req.path.startsWith("/frame/") &&
    !c.res.headers.get("content-security-policy")
  ) {
    c.header(
      "content-security-policy",
      "default-src 'self'; style-src 'self' https://fonts.googleapis.com; font-src https://fonts.gstatic.com; img-src 'self' data:; frame-src 'self'; connect-src 'self'; frame-ancestors 'none'",
    );
  }
});

// A judge opening the site from Devpost should see a tool with data in it
// before building anything. AMBER_DEMO_LINK is a member link into the demo
// circle, set only on the deployment that has one.
app.get("/api/demo", (c) => c.json({ link: process.env.AMBER_DEMO_LINK || null }));

app.get("/healthz", async (c) => {
  await pool.query("select 1");
  return c.json({ ok: true });
});

app.post("/api/owners", async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const name = requireText(body.name, "name", 80);
  const key = `amb_${newToken()}`;
  const id = newId("own");
  await pool.query(
    "insert into owners (id, name, key_hash) values ($1, $2, $3)",
    [id, name, hash(key)],
  );
  return c.json({ key, owner: { id, name } });
});

app.get("/api/owner", async (c) => {
  const owner = await requireOwner(c);
  const base = publicUrl(c);
  return c.json({ ...(await ownerOverview(owner, base)), mcpUrl: null, base });
});

app.post("/api/circles", async (c) => {
  const owner = await requireOwner(c);
  const body = await c.req.json();
  const id = await createCircle(
    owner,
    body.name,
    Array.isArray(body.members) ? body.members : [],
  );
  return c.json({ id });
});

app.post("/api/circles/:id/members", async (c) => {
  const owner = await requireOwner(c);
  const circle = await findCircle(owner, c.req.param("id"));
  const body = await c.req.json();
  const client = await pool.connect();
  try {
    const member = await addMember(client, circle.id, body);
    return c.json({ id: member.id });
  } finally {
    client.release();
  }
});

app.delete("/api/members/:id", async (c) => {
  const owner = await requireOwner(c);
  await pool.query(
    `delete from members m using circles c
      where m.id = $1 and m.circle_id = c.id and c.owner_id = $2 and not m.is_owner`,
    [c.req.param("id"), owner.id],
  );
  return c.json({ ok: true });
});

app.post("/api/tools", async (c) => {
  const owner = await requireOwner(c);
  const result = await publishTool(owner, await c.req.json());
  return c.json({ ...result, url: `${publicUrl(c)}/t/${result.slug}` });
});

app.put("/api/tools/:slug", async (c) => {
  const owner = await requireOwner(c);
  return c.json(
    await updateTool(owner, c.req.param("slug"), await c.req.json()),
  );
});

app.delete("/api/tools/:slug", async (c) => {
  const owner = await requireOwner(c);
  await pool.query("delete from tools where owner_id = $1 and slug = $2", [
    owner.id,
    c.req.param("slug"),
  ]);
  return c.json({ ok: true });
});

app.get("/api/templates/:name", (c) => {
  const name = c.req.param("name");
  if (!/^[a-z-]+$/.test(name)) throw new HttpError(404, "No such template");
  try {
    return c.text(
      readFileSync(path.join(here, "tools", `${name}.html`), "utf8"),
    );
  } catch {
    throw new HttpError(404, "No such template");
  }
});

// A member opening a tool. A wrong or missing link still learns which circle
// the tool belongs to and who to ask, so the gate screen can say something
// useful instead of a bare 403.
app.get("/api/run/:slug", async (c) => {
  const access = await memberForTool(
    c.req.param("slug"),
    c.req.header("x-amber-member"),
  );
  if (!access)
    throw new HttpError(404, "This tool does not exist, or it was deleted.");
  if (!access.member_id) {
    return c.json(
      {
        error: "not_in_circle",
        title: access.title,
        circle: access.circle_name,
        owner: access.owner_name,
      },
      403,
    );
  }
  await pool.query("insert into opens (tool_id, member_id) values ($1, $2)", [
    access.tool_id,
    access.member_id,
  ]);
  return c.json({
    tool: {
      title: access.title,
      description: access.description,
      version: access.version,
    },
    circle: access.circle_name,
    owner: access.owner_name,
    me: {
      id: access.member_id,
      name: access.member_name,
      isOwner: access.is_owner,
    },
    ticket: signTicket(access.slug, access.member_id),
  });
});

app.post("/api/run/:slug/rpc", async (c) => {
  const access = await memberForTool(
    c.req.param("slug"),
    c.req.header("x-amber-member"),
  );
  if (!access?.member_id)
    throw new HttpError(403, "Your link does not open this tool.");
  return c.json({ result: await bridge(access, await c.req.json()) });
});

app.get("/api/run/:slug/reach/:memberId", async (c) => {
  const access = await memberForTool(
    c.req.param("slug"),
    c.req.header("x-amber-member"),
  );
  if (!access?.member_id)
    throw new HttpError(403, "Your link does not open this tool.");
  if (!access.is_owner)
    throw new HttpError(
      403,
      "Only the circle owner can reach out from a tool.",
    );
  const { rows } = await pool.query(
    "select name, phone from members where id = $1 and circle_id = $2",
    [c.req.param("memberId"), access.circle_id],
  );
  if (!rows[0]) throw new HttpError(404, "That person is not in this circle.");
  return c.json(rows[0]);
});

app.get("/frame/:slug", async (c) => {
  const slug = c.req.param("slug");
  const memberId = verifyTicket(slug, c.req.query("ticket"));
  if (!memberId)
    return c.text("This frame link expired. Reload the tool.", 403);
  const { rows } = await pool.query(
    `select case when $3::boolean and m.is_owner and t.draft_html is not null then t.draft_html else t.html end as html
       from tools t join members m on m.circle_id = t.circle_id where t.slug = $1 and m.id = $2`,
    [slug, memberId, c.req.query("draft") === "1"],
  );
  if (!rows[0]) return c.text("Not found", 404);
  c.header("content-security-policy", FRAME_CSP);
  c.header("cache-control", "no-store");
  return c.html(frameDocument(rows[0].html));
});

app.post("/mcp/:key", async (c) => {
  const owner = await ownerFromKey(c.req.param("key"));
  if (!owner)
    return c.json(
      {
        jsonrpc: "2.0",
        id: null,
        error: { code: -32001, message: "Unknown Amber key" },
      },
      401,
    );
  const message = await c.req.json().catch(() => null);
  if (!message || message.jsonrpc !== "2.0")
    return c.json(
      {
        jsonrpc: "2.0",
        id: null,
        error: { code: -32700, message: "Parse error" },
      },
      400,
    );
  if (message.id === undefined) return c.body(null, 202);
  const reply = (result) => c.json({ jsonrpc: "2.0", id: message.id, result });
  switch (message.method) {
    case "initialize":
      return reply({
        protocolVersion: message.params?.protocolVersion || "2025-06-18",
        capabilities: { tools: {} },
        serverInfo: { name: "amber", version: "0.1.0" },
        instructions: `Amber hosts small tools and shares them with circles of people. ${TOOL_GUIDE}`,
      });
    case "ping":
      return reply({});
    case "tools/list":
      return reply({ tools: MCP_TOOLS });
    case "tools/call": {
      try {
        const text = await callMcpTool(
          owner,
          message.params?.name,
          message.params?.arguments || {},
          publicUrl(c),
        );
        return reply({ content: [{ type: "text", text }] });
      } catch (error) {
        return reply({
          content: [{ type: "text", text: error.message }],
          isError: true,
        });
      }
    }
    default:
      return c.json({
        jsonrpc: "2.0",
        id: message.id,
        error: { code: -32601, message: `Method not found: ${message.method}` },
      });
  }
});

// Deleting an account removes every circle, tool, member link and saved
// entry it owns, through the schema's cascades. Nothing is kept.
app.delete("/api/owner", async (c) => {
  const owner = await requireOwner(c);
  await pool.query("delete from owners where id = $1", [owner.id]);
  return c.json({ ok: true });
});

// "Make my own copy", the Google Docs template move: someone who can see a
// tool, and has an Amber account of their own, copies the tool without its
// data into one of their circles. The member link proves they can see it.
app.post("/api/run/:slug/copy", async (c) => {
  const owner = await requireOwner(c);
  const access = await memberForTool(
    c.req.param("slug"),
    c.req.header("x-amber-member"),
  );
  if (!access?.member_id)
    throw new HttpError(403, "You can only copy a tool you can open.");
  const body = await c.req.json();
  const { rows } = await pool.query(
    "select title, description, html from tools where slug = $1",
    [c.req.param("slug")],
  );
  const result = await publishTool(owner, {
    title: rows[0].title,
    description: rows[0].description,
    circle: body.circle,
    html: rows[0].html,
    request: `A copy of ${rows[0].title}`,
  });
  return c.json(result);
});

// ---------- the builder, versions, and asking to be let in ----------

// Guessed, never measured: every build spends real money on the owner's key,
// and a stuck retry loop in a browser should not be able to spend more than
// about a dollar an hour. Twelve builds an hour is far past what a person
// iterating by hand does.
const BUILDS_PER_HOUR = 12;
// The per-owner limit does not stop fifty new accounts, and this URL goes on
// a public Devpost page. A new tool measured about 19 cents at Opus 5 list
// price (2026-09-27, two builds), so 150 a day caps the worst day near $30.
const BUILDS_PER_DAY = Number(process.env.AMBER_BUILDS_PER_DAY || 150);
const buildLog = new Map();
let siteBuilds = [];
function allowBuild(ownerId) {
  const now = Date.now();
  siteBuilds = siteBuilds.filter((at) => now - at < 86_400_000);
  if (siteBuilds.length >= BUILDS_PER_DAY) return "site";
  const recent = (buildLog.get(ownerId) || []).filter(
    (at) => now - at < 3600_000,
  );
  if (recent.length >= BUILDS_PER_HOUR) return false;
  recent.push(now);
  buildLog.set(ownerId, recent);
  siteBuilds.push(now);
  return true;
}

app.post("/api/build", async (c) => {
  const owner = await requireOwner(c);
  const body = await c.req.json();
  const request = requireText(body.request, "what you want", 4000);
  const existing = body.slug
    ? (
        await pool.query(
          "select slug, title, html, circle_id from tools where owner_id = $1 and slug = $2",
          [owner.id, String(body.slug)],
        )
      ).rows[0]
    : null;
  if (body.slug && !existing)
    throw new HttpError(404, "No tool with that link belongs to you.");
  const circle = existing
    ? (
        await pool.query("select id, name from circles where id = $1", [
          existing.circle_id,
        ])
      ).rows[0]
    : await findCircle(owner, body.circle);
  const { rows: people } = await pool.query(
    "select name from members where circle_id = $1 order by is_owner desc, name",
    [circle.id],
  );
  const allowed = allowBuild(owner.id);
  if (allowed === "site")
    throw new HttpError(503, "Amber has built a lot of tools today and is resting. Try again tomorrow.");
  if (!allowed)
    throw new HttpError(
      429,
      "That is a lot of building for one hour. Take a break and try again in a little while.",
    );

  return streamSSE(c, async (sse) => {
    const send = (event, data) =>
      sse.writeSSE({ event, data: JSON.stringify(data) });
    try {
      const { html, usage } = await build({
        request,
        circleName: circle.name,
        people: people.map((person) => person.name),
        currentHtml: existing?.html,
        onProgress: (progress) => send("progress", progress),
      });
      // Token counts only, never the request text: the cost-per-build number
      // on the pitch deck has to come from real builds, not a guess.
      console.log(
        JSON.stringify({
          event: "build",
          input: usage.input_tokens,
          output: usage.output_tokens,
          edit: Boolean(existing),
        }),
      );
      if (existing) {
        await pool.query(
          "update tools set draft_html = $3, draft_request = $4 where owner_id = $1 and slug = $2",
          [owner.id, existing.slug, html, request],
        );
        await send("done", { slug: existing.slug, draft: true });
      } else {
        const result = await publishTool(owner, {
          title: body.title || titleFrom(request),
          description: request.slice(0, 200),
          circle: circle.id,
          html,
          request,
        });
        await send("done", { slug: result.slug, version: 1 });
      }
    } catch (error) {
      if (!(error.status >= 400 && error.status < 600)) console.error(error);
      await send("error", {
        message: error.status
          ? error.message
          : "Something went wrong while building. Try again.",
      });
    }
  });
});

app.post("/api/tools/:slug/keep", async (c) => {
  const owner = await requireOwner(c);
  const { rows } = await pool.query(
    "select draft_html, draft_request from tools where owner_id = $1 and slug = $2",
    [owner.id, c.req.param("slug")],
  );
  if (!rows[0]?.draft_html)
    throw new HttpError(404, "There is no change waiting. Ask for one first.");
  const result = await updateTool(owner, c.req.param("slug"), {
    html: rows[0].draft_html,
    request: rows[0].draft_request || "",
  });
  await pool.query(
    "update tools set draft_html = null, draft_request = null where owner_id = $1 and slug = $2",
    [owner.id, c.req.param("slug")],
  );
  return c.json(result);
});

app.post("/api/tools/:slug/discard", async (c) => {
  const owner = await requireOwner(c);
  await pool.query(
    "update tools set draft_html = null, draft_request = null where owner_id = $1 and slug = $2",
    [owner.id, c.req.param("slug")],
  );
  return c.json({ ok: true });
});

app.get("/api/tools/:slug/versions", async (c) => {
  const owner = await requireOwner(c);
  const { rows } = await pool.query(
    `select v.version, v.request, v.created_at, (v.version = t.version) as current,
            (v.data_snapshot is not null) as has_entries,
            coalesce(jsonb_array_length(v.data_snapshot), 0) as entry_count
       from tool_versions v join tools t on t.id = v.tool_id
      where t.owner_id = $1 and t.slug = $2 order by v.version desc limit 30`,
    [owner.id, c.req.param("slug")],
  );
  return c.json({ versions: rows });
});

app.post("/api/tools/:slug/restore", async (c) => {
  const owner = await requireOwner(c);
  const { version } = await c.req.json();
  const { rows } = await pool.query(
    `select v.html from tool_versions v join tools t on t.id = v.tool_id
      where t.owner_id = $1 and t.slug = $2 and v.version = $3`,
    [owner.id, c.req.param("slug"), Number(version)],
  );
  if (!rows[0]) throw new HttpError(404, "That version is not there any more.");
  const body = await c.req.json().catch(() => ({}));
  const withEntries = Boolean(body.entries);
  // updateTool snapshots the entries as they are now into the new version,
  // so even putting old entries back can itself be undone.
  const result = await updateTool(owner, c.req.param("slug"), {
    html: rows[0].html,
    request: `Went back to version ${Number(version)}${withEntries ? ", entries too" : ""}`,
  });
  if (withEntries) {
    const { rows: [old] } = await pool.query(
      `select v.data_snapshot, t.id as tool_id from tool_versions v join tools t on t.id = v.tool_id
        where t.owner_id = $1 and t.slug = $2 and v.version = $3`,
      [owner.id, c.req.param("slug"), Number(version)],
    );
    if (!old?.data_snapshot) throw new HttpError(409, "That version has no saved entries to put back. The tool itself went back.");
    const client = await pool.connect();
    try {
      await client.query("begin");
      await client.query("delete from records where tool_id = $1", [old.tool_id]);
      // One statement for the whole snapshot. An author who has since left
      // the group keeps their entry, unattributed, rather than blocking it.
      await client.query(
        `insert into records (id, tool_id, collection, data, author_id, created_at, updated_at)
         select r.id, $2, r.collection, r.data, m.id, r.created_at, r.updated_at
           from jsonb_to_recordset($1::jsonb) as r(id text, collection text, data jsonb, author_id text, created_at timestamptz, updated_at timestamptz)
           left join members m on m.id = r.author_id`,
        [JSON.stringify(old.data_snapshot), old.tool_id],
      );
      await client.query("commit");
    } catch (error) {
      await client.query("rollback");
      throw error;
    } finally {
      client.release();
    }
  }
  return c.json(result);
});

// Guessed, never measured: a real circle is a few dozen people, so fifty
// open requests on one tool means someone is spamming the form.
const MAX_PENDING_REQUESTS = 50;

app.post("/api/run/:slug/ask", async (c) => {
  const body = await c.req.json().catch(() => ({}));
  const { rows } = await pool.query("select id from tools where slug = $1", [
    c.req.param("slug"),
  ]);
  if (!rows[0]) throw new HttpError(404, "This tool does not exist.");
  const {
    rows: [{ count }],
  } = await pool.query(
    "select count(*)::int as count from access_requests where tool_id = $1 and status = 'pending'",
    [rows[0].id],
  );
  if (count >= MAX_PENDING_REQUESTS)
    throw new HttpError(
      429,
      "There are already a lot of people waiting. Text the owner directly.",
    );
  await pool.query(
    "insert into access_requests (id, tool_id, name, phone, note) values ($1, $2, $3, $4, $5)",
    [
      newId("req"),
      rows[0].id,
      requireText(body.name, "your name", 80),
      normalizePhone(body.phone),
      String(body.note || "").slice(0, 280),
    ],
  );
  return c.json({ ok: true });
});

app.get("/api/requests", async (c) => {
  const owner = await requireOwner(c);
  const { rows } = await pool.query(
    `select a.id, a.name, a.phone, a.note, a.created_at, t.slug, t.title, c.name as circle_name
       from access_requests a join tools t on t.id = a.tool_id join circles c on c.id = t.circle_id
      where t.owner_id = $1 and a.status = 'pending' order by a.created_at`,
    [owner.id],
  );
  return c.json({ requests: rows });
});

app.post("/api/requests/:id/:decision", async (c) => {
  const owner = await requireOwner(c);
  const decision = c.req.param("decision");
  if (!["approve", "decline"].includes(decision))
    throw new HttpError(404, "Not a choice.");
  const client = await pool.connect();
  try {
    await client.query("begin");
    const { rows } = await client.query(
      `select a.id, a.name, a.phone, t.slug, t.title, t.circle_id, c.name as circle_name
         from access_requests a join tools t on t.id = a.tool_id join circles c on c.id = t.circle_id
        where a.id = $1 and t.owner_id = $2 and a.status = 'pending' for update of a`,
      [c.req.param("id"), owner.id],
    );
    if (!rows[0]) throw new HttpError(404, "That request was already handled.");
    const ask = rows[0];
    await client.query("update access_requests set status = $2 where id = $1", [
      ask.id,
      decision === "approve" ? "approved" : "declined",
    ]);
    let link = null;
    if (decision === "approve") {
      const member = await addMember(client, ask.circle_id, {
        name: ask.name,
        phone: ask.phone,
      });
      link = `${publicUrl(c)}/t/${ask.slug}#m=${encodeURIComponent(member.token)}`;
    }
    await client.query("commit");
    return c.json({
      ok: true,
      name: ask.name,
      phone: ask.phone,
      title: ask.title,
      circle: ask.circle_name,
      link,
    });
  } catch (error) {
    await client.query("rollback");
    throw error;
  } finally {
    client.release();
  }
});

app.get("/mcp/:key", (c) => c.body(null, 405));

app.use(
  "/*",
  serveStatic({
    root: path.relative(process.cwd(), path.join(here, "public")),
  }),
);
app.get("*", (c) =>
  c.html(readFileSync(path.join(here, "public", "index.html"), "utf8")),
);

// ---------- boot ----------

await pool.query(readFileSync(path.join(here, "schema.sql"), "utf8"));
serve({ fetch: app.fetch, port: PORT }, () =>
  console.log(`amber-circles listening on :${PORT}`),
);
