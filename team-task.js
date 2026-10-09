// Vendored from calebnewtonusc/Chewbacca apps/team-web/lib/task.js. The board's
// task files are written by that site, tools/team.py and this server, so all
// three must render byte for byte the same. Copy it again when it changes.

export const FIELDS = [
  "id",
  "title",
  "status",
  "area",
  "parent",
  "owner",
  "priority",
  "due",
  "labels",
  "done_when",
  "proof",
  "source",
  "created",
  "updated",
];
export const STATUSES = [
  "inbox",
  "backlog",
  "todo",
  "in_progress",
  "in_review",
  "done",
  "ideas",
  "canceled",
];
export const AREAS = ["feature", "functionality", "design", "business"];
export const PRIORITIES = ["urgent", "high", "medium", "low", "none"];
export const ID_PATTERN = /^CHW-(\d+)$/;

// Terminal control bytes, minus tab and newline: see CONTROL in tools/team.py.
const CONTROL = /[\x00-\x08\x0b-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/g;
export const clean = (value) => String(value ?? "").replace(CONTROL, "");

export function oneLine(value) {
  return clean(value).replace(/\s+/g, " ").trim();
}

// See safe_notes in tools/team.py: a bare "## Activity" line inside notes
// would split the file and forge activity entries.
export function safeNotes(notes) {
  return clean(notes).trim().split("\n").map((l) => (l.trim() === "## Activity" ? "### Activity" : l)).join("\n");
}

export function parse(text) {
  const lines = text.replace(/\r\n/g, "\n").split("\n");
  if (!lines.length || lines[0].trim() !== "---")
    throw new Error("task file has no frontmatter");
  const meta = {};
  let i = 1;
  for (; i < lines.length && lines[i].trim() !== "---"; i++) {
    const at = lines[i].indexOf(":");
    if (at >= 0)
      meta[lines[i].slice(0, at).trim()] = lines[i].slice(at + 1).trim();
  }
  if (i >= lines.length) throw new Error("task frontmatter is not closed");
  const body = lines
    .slice(i + 1)
    .join("\n")
    .replace(/^\n+|\n+$/g, "");
  const task = Object.fromEntries(FIELDS.map((f) => [f, meta[f] ?? ""]));
  task.labels = task.labels
    .split(",")
    .map((x) => x.trim())
    .filter(Boolean);
  let notes = body;
  let activity = "";
  if (body.startsWith("## Activity\n")) {
    notes = "";
    activity = body.slice("## Activity\n".length);
  } else {
    const at = body.indexOf("\n## Activity\n");
    if (at >= 0) {
      notes = body.slice(0, at);
      activity = body.slice(at + "\n## Activity\n".length);
    }
  }
  task.notes = notes.trim();
  task.activity = activity
    .trim()
    .split("\n")
    .filter((a) => a.startsWith("- "))
    .map((a) => a.slice(2));
  return task;
}

export function render(task) {
  const out = ["---"];
  for (const f of FIELDS) {
    const v = f === "labels" ? (task.labels || []).join(", ") : task[f];
    out.push(`${f}: ${oneLine(v)}`);
  }
  out.push("---");
  if (task.notes) out.push("", safeNotes(task.notes));
  out.push(
    "",
    "## Activity",
    ...(task.activity || []).map((a) => `- ${oneLine(a)}`),
  );
  return out.join("\n") + "\n";
}

export function idNumber(id) {
  const m = ID_PATTERN.exec(id || "");
  return m ? Number(m[1]) : 0;
}

// Commits -> tasks. tools/team.py (parse_commit_refs, apply_commit) is the other half.
const TASK_REF = /\bCHW-(\d+)\b/gi;
const CLOSING_REF = /\b(?:fix(?:es|ed)?|close[sd]?|resolve[sd]?):? CHW-(\d+)\b/gi;

// Subject line plus trailer-style body lines only; see TRAILER in tools/team.py.
const TRAILER = /^(?:(fix(?:es|ed)?|close[sd]?|resolve[sd]?)|refs?|part of)?:? ?(CHW-\d+(?:[ ,]+CHW-\d+)*)[ ,]*$/i;
const MAX_REF_LINE = 200; // see MAX_REF_LINE in tools/team.py
const ids = (text) => new Set([...text.matchAll(TASK_REF)].map((m) => `CHW-${Number(m[1])}`));

export function parseCommitRefs(subject, body) {
  if (subject.startsWith("team:") || subject.startsWith("Merge ")) return { refs: new Set(), closing: new Set() };
  subject = subject.slice(0, MAX_REF_LINE * 2).replace(/\s+/g, " ");
  const refs = ids(subject);
  const closing = new Set([...subject.matchAll(CLOSING_REF)].map((m) => `CHW-${Number(m[1])}`));
  for (const raw of body.split("\n")) {
    const line = raw.trim().replace(/\s+/g, " ");
    if (line.length > MAX_REF_LINE) continue;
    const m = TRAILER.exec(line);
    if (!m) continue;
    for (const id of ids(m[2])) { refs.add(id); if (m[1]) closing.add(id); }
  }
  return { refs, closing };
}

export function applyCommit(task, sha, who, subject, url, isClosing, date) {
  if (task.activity.some((a) => a.includes(`commit ${sha.slice(0, 7)}`))) return false;
  task.activity.push(`${date} ${who}: commit ${sha.slice(0, 7)} ${oneLine(subject).slice(0, 160)}`);
  if (isClosing && task.status !== "done") {
    task.status = "done";
    task.proof = task.proof || url;
  } else if (["inbox", "backlog", "todo"].includes(task.status)) {
    task.status = "in_progress";
  }
  task.updated = date;
  return true;
}
