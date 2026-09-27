// Amber Circles client. No framework and no build step: the whole surface is
// six screens, and every one of them is a string rendered into #app.

const app = document.getElementById("app");
const toastEl = document.getElementById("toast");

// ---------- storage that survives private windows ----------

const store = {
  get(key) {
    try {
      return localStorage.getItem(key);
    } catch {
      return null;
    }
  },
  set(key, value) {
    try {
      localStorage.setItem(key, value);
    } catch {
      /* private mode: links still work per visit */
    }
  },
  remove(key) {
    try {
      localStorage.removeItem(key);
    } catch {
      /* nothing stored to remove */
    }
  },
};
const OWNER_KEY = "amber.owner";
const memberKey = (slug) => `amber.member.${slug}`;

// ---------- tiny helpers ----------

const esc = (value) =>
  String(value ?? "").replace(
    /[&<>"']/g,
    (ch) =>
      ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[
        ch
      ],
  );
const initials = (name) =>
  String(name || "?")
    .trim()
    .split(/\s+/)
    .slice(0, 2)
    .map((part) => part[0]?.toUpperCase() || "")
    .join("");

function timeAgo(iso) {
  if (!iso) return "never";
  const seconds = Math.max(
    1,
    Math.round((Date.now() - new Date(iso).getTime()) / 1000),
  );
  if (seconds < 60) return "just now";
  const minutes = Math.round(seconds / 60);
  if (minutes < 60) return `${minutes}m ago`;
  const hours = Math.round(minutes / 60);
  if (hours < 24) return `${hours}h ago`;
  return `${Math.round(hours / 24)}d ago`;
}

function formatPhone(phone) {
  const digits = String(phone || "").replace(/\D/g, "");
  const local = digits.length === 11 && digits.startsWith("1") ? digits.slice(1) : digits;
  if (local.length !== 10) return phone || "";
  return `(${local.slice(0, 3)}) ${local.slice(3, 6)}-${local.slice(6)}`;
}

function toast(message) {
  toastEl.textContent = message;
  toastEl.classList.add("show");
  clearTimeout(toast.timer);
  toast.timer = setTimeout(() => toastEl.classList.remove("show"), 2200);
}

async function copy(text, label = "Copied") {
  try {
    await navigator.clipboard.writeText(text);
    toast(label);
  } catch {
    window.prompt("Copy this:", text);
  }
}

// Lucide paths, inlined because the page policy only loads scripts from here.
const ICONS = {
  plus: '<path d="M12 5v14M5 12h14"/>',
  arrow: '<path d="M5 12h14M13 6l6 6-6 6"/>',
  copy: '<rect x="9" y="9" width="13" height="13" rx="2"/><path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"/>',
  message:
    '<path d="M21 15a2 2 0 0 1-2 2H7l-4 4V5a2 2 0 0 1 2-2h14a2 2 0 0 1 2 2z"/>',
  open: '<path d="M15 3h6v6M10 14 21 3M18 13v6a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V8a2 2 0 0 1 2-2h6"/>',
  users:
    '<path d="M16 21v-2a4 4 0 0 0-4-4H6a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M22 21v-2a4 4 0 0 0-3-3.87M16 3.13a4 4 0 0 1 0 7.75"/>',
  plug: '<path d="M12 22v-5M9 8V2M15 8V2M18 8v5a4 4 0 0 1-4 4h-4a4 4 0 0 1-4-4V8Z"/>',
  lock: '<rect x="3" y="11" width="18" height="11" rx="2"/><path d="M7 11V7a5 5 0 0 1 10 0v4"/>',
  share:
    '<circle cx="18" cy="5" r="3"/><circle cx="6" cy="12" r="3"/><circle cx="18" cy="19" r="3"/><path d="m8.6 13.5 6.8 4M15.4 6.5l-6.8 4"/>',
  trash:
    '<path d="M3 6h18M19 6v14a2 2 0 0 1-2 2H7a2 2 0 0 1-2-2V6M8 6V4a2 2 0 0 1 2-2h4a2 2 0 0 1 2 2v2"/>',
  alert: '<circle cx="12" cy="12" r="10"/><path d="M12 8v4M12 16h.01"/>',
  sparkle:
    '<path d="M12 3l1.9 5.8L20 11l-6.1 2.2L12 19l-1.9-5.8L4 11l6.1-2.2z"/>',
  back: '<path d="M19 12H5M11 18l-6-6 6-6"/>',
};
const icon = (name, extra = "") =>
  `<svg class="icon ${extra}" viewBox="0 0 24 24" aria-hidden="true">${ICONS[name]}</svg>`;

// ---------- API ----------

async function api(path, { method = "GET", body, member } = {}) {
  const headers = { "content-type": "application/json" };
  const ownerKey = store.get(OWNER_KEY);
  if (ownerKey) headers.authorization = `Bearer ${ownerKey}`;
  if (member) headers["x-amber-member"] = member;
  let response;
  try {
    response = await fetch(path, {
      method,
      headers,
      body: body ? JSON.stringify(body) : undefined,
    });
  } catch {
    throw Object.assign(
      new Error("You look offline. Check your connection and try again."),
      { status: 0 },
    );
  }
  const data = await response.json().catch(() => ({}));
  if (!response.ok)
    throw Object.assign(
      new Error(data.error || `Request failed (${response.status})`),
      { status: response.status, data },
    );
  return data;
}

// ---------- routing ----------

function navigate(path) {
  history.pushState({}, "", path);
  render();
}

document.addEventListener("click", (event) => {
  const link = event.target.closest("a[data-link]");
  if (!link || event.metaKey || event.ctrlKey) return;
  event.preventDefault();
  navigate(link.getAttribute("href"));
});
window.addEventListener("popstate", render);

function shell(active, content) {
  const link = (href, label, key) =>
    `<a href="${href}" data-link ${active === key ? 'aria-current="page"' : ""}>${label}</a>`;
  return `
    <div class="page">
      <header class="nav">
        <a class="brand" href="/" data-link><span class="brand-mark" aria-hidden="true"></span><span class="brand-name">Amber</span><span class="brand-sub">Circles</span></a>
        <nav class="nav-links" aria-label="Main">
          ${link("/", "Tools", "tools")}
          ${link("/circles", "Circles", "circles")}
          ${link("/connect", "Connect Claude", "connect")}
        </nav>
      </header>
      <main id="main">${content}</main>
    </div>`;
}

function stateView({ glyph = "alert", title, body, action = "" }) {
  return `<div class="state"><div class="glyph">${icon(glyph)}</div><h2>${esc(title)}</h2><p>${esc(body)}</p>${action}</div>`;
}

function errorView(error, retryLabel = "Try again") {
  return stateView({
    title: "That did not load",
    body: error.message,
    action: `<button class="btn" data-retry>${retryLabel}</button>`,
  });
}

function bindRetry() {
  app.querySelector("[data-retry]")?.addEventListener("click", render);
}

async function render() {
  document.body.classList.remove("runner");
  const path = location.pathname;
  const toolMatch = path.match(/^\/t\/([\w-]+)\/?$/);
  if (toolMatch) return runner(toolMatch[1]);
  if (!store.get(OWNER_KEY)) return landing();
  if (path === "/circles") return circlesPage();
  const circleMatch = path.match(/^\/circles\/([\w-]+)$/);
  if (circleMatch) return circlePage(circleMatch[1]);
  const shareMatch = path.match(/^\/share\/([\w-]+)$/);
  if (shareMatch) return sharePage(shareMatch[1]);
  if (path === "/new") return newToolPage();
  if (path === "/connect") return connectPage();
  return dashboard();
}

// ---------- overview cache: one fetch feeds every owner screen ----------

let overview = null;
async function loadOverview(force = false) {
  if (!overview || force) overview = await api("/api/owner");
  return overview;
}

function ownerToken(circleId) {
  const circle = overview?.circles.find((entry) => entry.id === circleId);
  return circle?.members.find((member) => member.is_owner)?.token;
}

// ---------- landing ----------

// The one committed mechanism, shown rather than described: a circle filling
// in, name by name, and the two people who have not been in for a while.
// STATE-SWAP, per DENY.md: content steps, nothing travels.
const SPECIMEN = [
  { name: "Tyler", when: "here, 6:02" },
  { name: "Maya", when: "here, 6:03" },
  { name: "Priya", when: "here, 6:05" },
  { name: "Diego", when: "here, 6:06" },
  { name: "Jordan", when: "missed the last 3", drifting: true },
  { name: "Sam", when: "missed the last 2", drifting: true },
];

function specimenView() {
  return `
    <div class="specimen enter enter-5" aria-label="Example: a circle checking in">
      <div class="specimen-head"><span class="specimen-title">GM Attendance</span><span class="specimen-count" id="specimen-count">0 of 6</span></div>
      <p class="specimen-meta">Example circle · Club cabinet · published by Claude</p>
      <ol>${SPECIMEN.map((person, index) => `<li data-index="${index}"><span class="mark"></span><span>${esc(person.name)}</span><span class="when">not yet</span></li>`).join("")}</ol>
      <p class="specimen-foot">Each person opened it from their own text. Nobody outside the cabinet can.</p>
    </div>`;
}

function runSpecimen() {
  const rows = [...app.querySelectorAll(".specimen li")];
  const count = app.querySelector("#specimen-count");
  if (!rows.length) return;
  let step = 0;
  const here = SPECIMEN.filter((person) => !person.drifting).length;
  const tick = () => {
    if (!document.body.contains(count)) return clearInterval(timer);
    if (step > SPECIMEN.length + 2) {
      step = 0;
      rows.forEach((row) => { row.className = ""; row.querySelector(".when").textContent = "not yet"; });
    } else if (step < SPECIMEN.length) {
      const person = SPECIMEN[step];
      rows[step].className = person.drifting ? "is-drifting" : "is-here";
      rows[step].querySelector(".when").textContent = person.when;
    }
    count.textContent = `${Math.min(step + 1, here)} of ${SPECIMEN.length}`;
    if (step === 0 && !rows[0].className) count.textContent = `0 of ${SPECIMEN.length}`;
    step += 1;
  };
  const timer = setInterval(tick, 1600);
  setTimeout(tick, 700);
}

function landing() {
  app.innerHTML = `
    <div class="page">
      <header class="nav">
        <a class="brand" href="/" data-link><span class="brand-mark" aria-hidden="true"></span><span class="brand-name">Amber</span><span class="brand-sub">Circles</span></a>
      </header>
      <main id="main">
        <section class="hero">
          <div>
            <p class="kicker enter enter-1">A cloud for small software</p>
            <h1 class="enter enter-2">Ask Claude for a tool. Share it <em>like a Google Doc.</em></h1>
            <p class="lede enter enter-3">The tool your club, team or trip needs, built by Claude and hosted by Amber. Only the people in your circle can open it, each from their own link. No deploys, no logins to set up.</p>
            <form id="start" class="enter enter-4">
              <label class="skip" for="start-name">Your name</label>
              <input class="input" id="start-name" name="name" placeholder="Your name" autocomplete="name" required maxlength="80">
              <button class="btn btn-primary btn-lg" type="submit">Start a circle ${icon("arrow")}</button>
            </form>
            <p class="error-text" id="start-error" role="alert"></p>
            <p class="fine enter enter-4">Free while we are in beta. Your first circle takes a minute.</p>
          </div>
          ${specimenView()}
        </section>
        <section class="notes">
          <div class="note"><b><span>1</span>Make a circle</b><p>Your cabinet, your team, your roommates. Everyone gets a personal link, so every tool knows who opened it.</p></div>
          <div class="note"><b><span>2</span>Ask Claude</b><p>"Build our attendance tracker and share it with the cabinet." Claude writes it and publishes it to Amber.</p></div>
          <div class="note"><b><span>3</span>They open a text</b><p>The tool runs sealed off from the internet. It sees names, never phone numbers, and keeps data the circle shares.</p></div>
        </section>
      </main>
    </div>`;
  runSpecimen();
  const form = app.querySelector("#start");
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = form.querySelector("button");
    button.disabled = true;
    button.textContent = "Starting…";
    try {
      const { key } = await api("/api/owners", { method: "POST", body: { name: form.name.value } });
      store.set(OWNER_KEY, key);
      navigate("/circles");
    } catch (error) {
      app.querySelector("#start-error").textContent = error.message;
      button.disabled = false;
      button.innerHTML = `Start a circle ${icon("arrow")}`;
    }
  });
}

// ---------- dashboard ----------

function skeletonGrid(count = 3) {
  return `<div class="ledger">${Array.from({ length: count }, () => '<div class="ledger-row"><div class="skeleton skeleton-line"></div></div>').join("")}</div>`;
}

async function dashboard() {
  app.innerHTML = shell(
    "tools",
    `
    <div class="masthead"><div><p class="kicker">Your tools</p><h2>What your circles are using</h2></div>
    <a class="btn btn-primary" href="/new" data-link>${icon("plus")} Publish a tool</a></div>
    <div id="tools" class="mt-4">${skeletonGrid()}</div>`,
  );
  try {
    const data = await loadOverview(true);
    const target = app.querySelector("#tools");
    if (!data.circles.length) {
      target.innerHTML = stateView({
        glyph: "users",
        title: "Start with a circle",
        body: "A tool is shared with one circle: the people it is for. Make yours first, then ask Claude to build into it.",
        action: '<a class="btn btn-primary" href="/circles" data-link>Make a circle</a>',
      });
      return;
    }
    if (!data.tools.length) {
      target.innerHTML = stateView({
        glyph: "sparkle",
        title: "Nothing published yet",
        body: "Connect Claude and ask for a tool, or publish the attendance tracker to a circle in one step.",
        action: '<div class="row"><a class="btn btn-primary" href="/connect" data-link>Connect Claude</a><a class="btn" href="/new?template=attendance" data-link>Use the attendance tracker</a></div>',
      });
      return;
    }
    target.innerHTML = `
      <div class="ledger">
        <div class="ledger-head ledger-tools"><span>Tool</span><span>Circle</span><span class="num">Opened</span><span class="num">Entries</span><span class="num">Last open</span><span></span></div>
        ${data.tools
          .map((tool) => {
            const circle = data.circles.find((entry) => entry.id === tool.circle_id);
            const size = circle?.members.length || 0;
            const token = ownerToken(tool.circle_id);
            const open = `/t/${esc(tool.slug)}${token ? `?m=${encodeURIComponent(token)}` : ""}`;
            return `
            <div class="ledger-row ledger-tools">
              <div><a class="title" href="${open}">${esc(tool.title)}</a><p class="sub">${esc(tool.description || "No description yet.")}</p></div>
              <div class="tag">${icon("users", "icon-sm")} ${esc(tool.circle_name)}</div>
              <div class="num"><span class="cell-label">Opened</span>${tool.people_opened}<small> of ${size}</small></div>
              <div class="num"><span class="cell-label">Entries</span>${tool.record_count}</div>
              <div class="num"><span class="cell-label">Last open</span><small>${timeAgo(tool.last_open)}</small></div>
              <div class="actions"><a class="btn btn-sm" href="/share/${esc(tool.slug)}" data-link>${icon("share", "icon-sm")} Links</a><a class="btn btn-sm btn-primary" href="${open}">Open</a></div>
            </div>`;
          })
          .join("")}
      </div>`;
  } catch (error) {
    if (error.status === 401) {
      store.remove(OWNER_KEY);
      return landing();
    }
    app.querySelector("#tools").innerHTML = errorView(error);
    bindRetry();
  }
}

// ---------- circles ----------

function parseMembers(text) {
  return text
    .split("\n")
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => {
      const [name, ...rest] = line.split(",");
      return { name: name.trim(), phone: rest.join(",").trim() || undefined };
    });
}

async function circlesPage() {
  app.innerHTML = shell(
    "circles",
    `
    <div class="masthead"><div><p class="kicker">Circles</p><h2>Who your tools are for</h2><p class="lede">A circle is the permission. Share a tool with one and only those people can open it, each through their own link.</p></div></div>
    <div class="split">
      <div id="circle-list">${skeletonGrid(2)}</div>
      <form class="sheet stack" id="new-circle">
        <p class="kicker">New circle</p>
        <div class="field"><label for="circle-name">Name</label><input class="input" id="circle-name" name="name" placeholder="TTS Cabinet" required maxlength="80"></div>
        <div class="field"><label for="circle-members">People, one per line</label><textarea class="input" id="circle-members" name="members" placeholder="Tyler Larsen, 310 555 0100&#10;Maya Chen, 213 555 0199"></textarea><span class="hint">Name, then phone. The phone is only used to text them their link, and tools never see it.</span></div>
        <p class="error-text" id="circle-error" role="alert"></p>
        <button class="btn btn-primary" type="submit">${icon("plus")} Create circle</button>
      </form>
    </div>`,
  );
  app.querySelector("#new-circle").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    const button = form.querySelector("button");
    button.disabled = true;
    try {
      const { id } = await api("/api/circles", {
        method: "POST",
        body: { name: form.name.value, members: parseMembers(form.members.value) },
      });
      toast("Circle created");
      navigate(`/circles/${id}`);
    } catch (error) {
      app.querySelector("#circle-error").textContent = error.message;
      button.disabled = false;
    }
  });
  try {
    const data = await loadOverview(true);
    const list = app.querySelector("#circle-list");
    list.innerHTML = data.circles.length
      ? `<div class="ledger">${data.circles
          .map((circle) => {
            const shared = data.tools.filter((tool) => tool.circle_id === circle.id).length;
            return `
            <div class="ledger-row ledger-circles">
              <div><a class="title" href="/circles/${esc(circle.id)}" data-link>${esc(circle.name)}</a><p class="sub">${shared} ${shared === 1 ? "tool" : "tools"} shared here</p></div>
              <div class="sub">${esc(circle.members.map((member) => member.name).slice(0, 5).join(", "))}${circle.members.length > 5 ? "…" : ""}</div>
              <div class="num"><span class="cell-label">People</span>${circle.members.length}</div>
              <div class="actions"><a class="btn btn-sm" href="/circles/${esc(circle.id)}" data-link>Open ${icon("arrow", "icon-sm")}</a></div>
            </div>`;
          })
          .join("")}</div>`
      : stateView({ glyph: "users", title: "No circles yet", body: "Make your first one with the form. You can add people any time." });
  } catch (error) {
    app.querySelector("#circle-list").innerHTML = errorView(error);
    bindRetry();
  }
}

function personRow(member, { link, message, removable }) {
  const sms = member.phone
    ? `sms:${encodeURIComponent(member.phone)}?&body=${encodeURIComponent(message)}`
    : null;
  return `
    <div class="person">
      <div class="avatar" aria-hidden="true">${esc(initials(member.name))}</div>
      <div class="who"><b>${esc(member.name)}${member.is_owner ? ' <span class="tag tag-neutral tag-xs">you</span>' : ""}</b><span>${esc(formatPhone(member.phone) || "no phone, copy the link instead")}</span></div>
      <span class="spacer"></span>
      ${link ? `<button class="btn btn-sm btn-ghost" data-copy="${esc(link)}" aria-label="Copy ${esc(member.name)}'s link">${icon("copy", "icon-sm")} Copy link</button>` : ""}
      ${sms && !member.is_owner ? `<a class="btn btn-sm" href="${esc(sms)}">${icon("message", "icon-sm")} Text</a>` : ""}
      ${removable && !member.is_owner ? `<button class="btn btn-sm btn-ghost" data-remove="${esc(member.id)}" aria-label="Remove ${esc(member.name)}">${icon("trash", "icon-sm")}</button>` : ""}
    </div>`;
}

function bindCopy() {
  app
    .querySelectorAll("[data-copy]")
    .forEach((button) =>
      button.addEventListener("click", () =>
        copy(button.dataset.copy, "Link copied"),
      ),
    );
}

async function circlePage(id) {
  app.innerHTML = shell(
    "circles",
    '<div class="skeleton h-320"></div>',
  );
  try {
    const data = await loadOverview(true);
    const circle = data.circles.find((entry) => entry.id === id);
    if (!circle) {
      app.querySelector("main").innerHTML = stateView({
        title: "No such circle",
        body: "It may have been deleted.",
        action: '<a class="btn" href="/circles" data-link>Back to circles</a>',
      });
      return;
    }
    const tools = data.tools.filter((tool) => tool.circle_id === id);
    app.querySelector("main").innerHTML = `
      <a class="btn btn-ghost btn-sm" href="/circles" data-link>${icon("back", "icon-sm")} Circles</a>
      <div class="masthead mt-3"><div><p class="kicker">Circle</p><h2>${esc(circle.name)}</h2></div></div>
      <div class="grid items-start">
        <div class="card">
          <h3 class="mt-0">People</h3>
          <div class="people">${circle.members.map((member) => personRow(member, { removable: true })).join("")}</div>
          <form class="row mt-4" id="add-member">
            <label class="skip" for="member-name">Name</label>
            <input class="input grow-name" id="member-name" name="name" placeholder="Name" required>
            <label class="skip" for="member-phone">Phone</label>
            <input class="input grow-phone" id="member-phone" name="phone" placeholder="Phone" inputmode="tel">
            <button class="btn" type="submit">${icon("plus")} Add</button>
          </form>
          <p class="error-text" id="member-error" role="alert"></p>
        </div>
        <div class="card">
          <h3 class="mt-0">Tools shared here</h3>
          ${
            tools.length
              ? `<div class="people">${tools
                  .map(
                    (tool) => `
            <div class="person"><div class="who"><b>${esc(tool.title)}</b><span>${tool.people_opened} of ${circle.members.length} opened</span></div><span class="spacer"></span><a class="btn btn-sm" href="/share/${esc(tool.slug)}" data-link>Share links</a></div>`,
                  )
                  .join("")}</div>`
              : `<p class="desc mb-4">Nothing yet. Ask Claude to build something for ${esc(circle.name)}.</p><a class="btn btn-primary" href="/new?circle=${esc(circle.id)}" data-link>${icon("plus")} Publish a tool</a>`
          }
        </div>
      </div>`;
    app
      .querySelector("#add-member")
      .addEventListener("submit", async (event) => {
        event.preventDefault();
        const form = event.currentTarget;
        try {
          await api(`/api/circles/${id}/members`, {
            method: "POST",
            body: { name: form.name.value, phone: form.phone.value },
          });
          toast(`${form.name.value} added`);
          circlePage(id);
        } catch (error) {
          app.querySelector("#member-error").textContent = error.message;
        }
      });
    app.querySelectorAll("[data-remove]").forEach((button) =>
      button.addEventListener("click", async () => {
        if (
          !confirm("Remove this person? Their link stops working right away.")
        )
          return;
        await api(`/api/members/${button.dataset.remove}`, {
          method: "DELETE",
        });
        circlePage(id);
      }),
    );
  } catch (error) {
    app.querySelector("main").innerHTML = errorView(error);
    bindRetry();
  }
}

// ---------- share sheet ----------

async function sharePage(slug) {
  app.innerHTML = shell(
    "tools",
    '<div class="skeleton h-360"></div>',
  );
  try {
    const data = await loadOverview(true);
    const tool = data.tools.find((entry) => entry.slug === slug);
    if (!tool) {
      app.querySelector("main").innerHTML = stateView({
        title: "No such tool",
        body: "It may have been deleted.",
        action: '<a class="btn" href="/" data-link>Back to tools</a>',
      });
      return;
    }
    const circle = data.circles.find((entry) => entry.id === tool.circle_id);
    const linkFor = (member) =>
      `${data.base}/t/${tool.slug}?m=${encodeURIComponent(member.token)}`;
    app.querySelector("main").innerHTML = `
      <a class="btn btn-ghost btn-sm" href="/" data-link>${icon("back", "icon-sm")} Tools</a>
      <div class="masthead mt-3"><div><p class="kicker">Share · ${esc(circle.name)}</p><h2>${esc(tool.title)}</h2>
      <p class="lede mt-1">Everyone gets their own link, so the tool knows who is checking in. Anyone outside ${esc(circle.name)} who opens the tool is turned away.</p></div></div>
      <div class="card">
        <div class="people">${circle.members
          .map((member) =>
            personRow(member, {
              link: linkFor(member),
              message: `${member.name.split(" ")[0]}, here's ${tool.title} for ${circle.name}: ${linkFor(member)}`,
            }),
          )
          .join("")}</div>
      </div>
      <p class="desc mt-4">${icon("lock", "icon-sm")} Links are personal. Text each person their own rather than posting one in a group chat.</p>`;
    bindCopy();
  } catch (error) {
    app.querySelector("main").innerHTML = errorView(error);
    bindRetry();
  }
}

// ---------- publish ----------

async function newToolPage() {
  const params = new URLSearchParams(location.search);
  app.innerHTML = shell(
    "tools",
    '<div class="skeleton h-420"></div>',
  );
  try {
    const data = await loadOverview(true);
    if (!data.circles.length) {
      app.querySelector("main").innerHTML = stateView({
        glyph: "users",
        title: "Make a circle first",
        body: "Every tool is shared with one circle.",
        action:
          '<a class="btn btn-primary" href="/circles" data-link>Make a circle</a>',
      });
      return;
    }
    app.querySelector("main").innerHTML = `
      <div class="masthead"><div><p class="kicker">Publish</p><h2>Put a tool in front of a circle</h2>
      <p class="lede mt-1">The fastest way is to <a href="/connect" data-link>connect Claude</a> and ask. This page is for pasting a file an agent already wrote.</p></div></div>
      <form class="card stack" id="publish">
        <div class="grid gap-3">
          <div class="field"><label for="tool-title">Title</label><input class="input" id="tool-title" name="title" required maxlength="80" placeholder="TTS Attendance"></div>
          <div class="field"><label for="tool-circle">Share with</label><select class="input" id="tool-circle" name="circle">${data.circles.map((circle) => `<option value="${esc(circle.id)}" ${params.get("circle") === circle.id ? "selected" : ""}>${esc(circle.name)} (${circle.members.length})</option>`).join("")}</select></div>
        </div>
        <div class="field"><label for="tool-desc">What it is for</label><input class="input" id="tool-desc" name="description" maxlength="500" placeholder="Check in at GMs and see who has drifted"></div>
        <div class="field"><label for="tool-html">The tool, as one HTML file</label><textarea class="input code" id="tool-html" name="html" required spellcheck="false" placeholder="&lt;!doctype html&gt;…"></textarea>
        <span class="hint">It runs sandboxed with no network. It talks to Amber through <code>window.amber</code>: me(), people(), list(), add(), update(), remove().</span></div>
        <p class="error-text" id="publish-error" role="alert"></p>
        <div class="row"><button class="btn btn-primary" type="submit">${icon("share")} Publish and share</button><button class="btn" type="button" id="use-template">Start from the attendance tracker</button></div>
      </form>`;
    const form = app.querySelector("#publish");
    const loadTemplate = async () => {
      const response = await fetch("/api/templates/attendance");
      form.html.value = await response.text();
      if (!form.title.value) form.title.value = "Attendance";
      if (!form.description.value)
        form.description.value =
          "Check in at meetings, and see who has quietly stopped coming so you can reach out.";
    };
    app.querySelector("#use-template").addEventListener("click", loadTemplate);
    if (params.get("template") === "attendance") loadTemplate();
    form.addEventListener("submit", async (event) => {
      event.preventDefault();
      const button = form.querySelector("button[type=submit]");
      button.disabled = true;
      try {
        const { slug } = await api("/api/tools", {
          method: "POST",
          body: {
            title: form.title.value,
            circle: form.circle.value,
            description: form.description.value,
            html: form.html.value,
          },
        });
        toast("Published");
        navigate(`/share/${slug}`);
      } catch (error) {
        app.querySelector("#publish-error").textContent = error.message;
        button.disabled = false;
      }
    });
  } catch (error) {
    app.querySelector("main").innerHTML = errorView(error);
    bindRetry();
  }
}

// ---------- connect Claude ----------

async function connectPage() {
  const key = store.get(OWNER_KEY);
  const base = location.origin;
  const mcp = `${base}/mcp/${key}`;
  const claudeCode = `claude mcp add --transport http amber ${mcp}`;
  const prompt =
    "Build an attendance tracker for my club and share it with my cabinet circle on Amber. Members check in at each meeting, and I can see who has missed the last three so I can reach out.";
  app.innerHTML = shell(
    "connect",
    `
    <div class="masthead"><div><p class="kicker">Connect Claude</p><h2>Let your agent publish for you</h2>
    <p class="lede mt-1">Once Claude is connected, you describe the tool and Claude builds it, publishes it here, and shares it with the circle you name.</p></div></div>
    <div class="grid items-start">
      <div class="card stack">
        <p class="kicker">Claude, the app</p>
        <h3 class="m-0">Add a custom connector</h3>
        <p class="desc">Settings, then Connectors, then Add custom connector. Paste this URL. It is your private key, so do not post it anywhere.</p>
        <div class="code-block"><code>${esc(mcp)}</code><button class="btn btn-sm btn-ghost" data-copy="${esc(mcp)}">${icon("copy", "icon-sm")} Copy</button></div>
      </div>
      <div class="card stack">
        <p class="kicker">Claude Code</p>
        <h3 class="m-0">One command</h3>
        <div class="code-block"><code>${esc(claudeCode)}</code><button class="btn btn-sm btn-ghost" data-copy="${esc(claudeCode)}">${icon("copy", "icon-sm")} Copy</button></div>
      </div>
      <div class="card stack">
        <p class="kicker">Then ask</p>
        <p class="quote">"${esc(prompt)}"</p>
        <button class="btn btn-sm" data-copy="${esc(prompt)}">${icon("copy", "icon-sm")} Copy prompt</button>
      </div>
    </div>`,
  );
  bindCopy();
}

// ---------- the runner ----------

async function runner(slug) {
  const params = new URLSearchParams(location.search);
  const fromLink = params.get("m");
  if (fromLink) {
    store.set(memberKey(slug), fromLink);
    history.replaceState({}, "", `/t/${slug}`);
  }
  const token = fromLink || store.get(memberKey(slug));
  document.body.classList.add("runner");
  app.innerHTML = `<div class="run-bar"><span class="brand-mark" aria-hidden="true"></span><div class="skeleton skeleton-line"></div></div>
    <div class="page pt-run"><div class="skeleton h-320"></div></div>`;

  let session;
  try {
    session = await api(`/api/run/${slug}`, { member: token || "" });
  } catch (error) {
    document.body.classList.remove("runner");
    const gate = error.status === 403 && error.data?.error === "not_in_circle";
    app.innerHTML = `<div class="page"><header class="nav"><a class="brand" href="/" data-link><span class="brand-mark" aria-hidden="true"></span><span class="brand-name">Amber</span></a></header><main id="main">${
      gate
        ? stateView({
            glyph: "lock",
            title: `${error.data.title} is shared with ${error.data.circle}`,
            body: `Only people in ${error.data.circle} can open it, each with their own link. Ask ${error.data.owner} to text you yours.`,
          })
        : error.status === 404
          ? stateView({
              title: "This tool is gone",
              body: "The link is wrong, or the tool was deleted.",
            })
          : errorView(error)
    }</main></div>`;
    bindRetry();
    return;
  }

  const isOwnerHere = Boolean(store.get(OWNER_KEY)) && session.me.isOwner;
  app.innerHTML = `
    <header class="run-bar">
      ${isOwnerHere ? `<a class="btn btn-ghost btn-sm" href="/" data-link aria-label="Back to your tools">${icon("back", "icon-sm")}</a>` : ""}
      <span class="brand-mark" aria-hidden="true"></span>
      <span class="run-title">${esc(session.tool.title)}</span>
      <span class="tag">${icon("users", "icon-sm")} ${esc(session.circle)}</span>
      <span class="run-me">You're ${esc(session.me.name.split(" ")[0])}</span>
    </header>
    <iframe class="run-frame" title="${esc(session.tool.title)}" sandbox="allow-scripts allow-forms allow-modals" src="/frame/${encodeURIComponent(slug)}?ticket=${encodeURIComponent(session.ticket)}"></iframe>`;
  const frame = app.querySelector("iframe");

  // CSP closes fetch, images and forms, but no browser lets a page stop a
  // sandboxed frame from navigating ITSELF, which is the one way left to carry
  // data out in a URL. A tool loads exactly once; a second load means it tried
  // to leave, so the frame is torn down and the person is told why.
  let frameLoads = 0;
  frame.addEventListener("load", () => {
    frameLoads += 1;
    if (frameLoads < 2) return;
    frame.remove();
    clearInterval(poller);
    app.insertAdjacentHTML(
      "beforeend",
      `<div class="page pt-run">${stateView({ glyph: "lock", title: "This tool tried to leave Amber", body: "Tools can only talk to your circle through Amber, so we closed it. Tell the circle owner." })}</div>`,
    );
  });

  // The stamp is how the frame hears about other people's changes: a cheap
  // poll while the tab is visible, then a nudge into the tool.
  let lastStamp = null;
  const post = (message) =>
    frame.contentWindow?.postMessage({ amber: 1, ...message }, "*");
  const checkStamp = async () => {
    if (document.hidden) return;
    try {
      const { result } = await api(`/api/run/${slug}/rpc`, {
        method: "POST",
        member: token,
        body: { op: "stamp" },
      });
      if (lastStamp !== null && result !== lastStamp)
        post({ type: "change", detail: { by: "someone" } });
      lastStamp = result;
    } catch {
      /* a missed poll is retried in four seconds */
    }
  };
  checkStamp();
  const poller = setInterval(checkStamp, 4000);
  window.addEventListener("popstate", () => clearInterval(poller), {
    once: true,
  });

  const ALLOWED = new Set([
    "me",
    "circle",
    "people",
    "list",
    "add",
    "update",
    "remove",
    "reach",
  ]);
  window.onmessage = async (event) => {
    if (event.source !== frame.contentWindow) return;
    const message = event.data || {};
    if (message.amber !== 1 || !ALLOWED.has(message.op)) return;
    try {
      if (message.op === "reach") {
        if (!session.me.isOwner)
          throw new Error("Only the circle owner can reach out from a tool.");
        const person = await api(
          `/api/run/${slug}/reach/${encodeURIComponent(message.memberId)}`,
          { member: token },
        );
        if (!person.phone)
          throw new Error(
            `${person.name} has no phone number in this circle yet.`,
          );
        location.href = `sms:${encodeURIComponent(person.phone)}?&body=${encodeURIComponent(message.message || "")}`;
        post({ id: message.id, result: { ok: true } });
        return;
      }
      const { op, id: callId, amber: _marker, ...args } = message;
      const { result } = await api(`/api/run/${slug}/rpc`, {
        method: "POST",
        member: token,
        body: { op, ...args },
      });
      post({ id: callId, result });
      if (["add", "update", "remove"].includes(op)) lastStamp = null;
    } catch (error) {
      post({ id: message.id, error: error.message });
    }
  };
}

render();
