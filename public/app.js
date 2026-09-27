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
          ${link("/make", "Make", "make")}
          ${link("/", "Tools", "tools")}
          ${link("/circles", "Circles", "circles")}
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
  cleanupActive();
  // A private sign-in link carries the owner key once, then it is stored and
  // stripped from the address bar so it never lands in history or a screenshot.
  // Secrets ride in the fragment, which browsers never send to the server,
  // so they cannot land in an edge request log. The query form still works
  // for links sent before 2026-09-27.
  const fragment = new URLSearchParams(location.hash.slice(1));
  const signIn = fragment.get("owner") || new URLSearchParams(location.search).get("owner");
  if (signIn) {
    store.set(OWNER_KEY, signIn);
    history.replaceState({}, "", location.pathname);
  }
  document.body.classList.remove("runner");
  const path = location.pathname;
  const toolMatch = path.match(/^\/t\/([\w-]+)\/?$/);
  if (toolMatch) return runner(toolMatch[1]);
  const chatMatch = path.match(/^\/c\/([\w-]+)\/?$/);
  if (chatMatch) return chatPage(chatMatch[1]);
  if (!store.get(OWNER_KEY)) return landing();
  if (path === "/circles") return circlesPage();
  const circleMatch = path.match(/^\/circles\/([\w-]+)$/);
  if (circleMatch) return circlePage(circleMatch[1]);
  const shareMatch = path.match(/^\/share\/([\w-]+)$/);
  if (shareMatch) return sharePage(shareMatch[1]);
  if (path === "/new") return newToolPage();
  if (path === "/make") return makePage();
  const toolPageMatch = path.match(/^\/tools\/([\w-]+)$/);
  if (toolPageMatch) return toolPage(toolPageMatch[1]);
  if (path === "/connect") return connectPage();
  return dashboard();
}

// ---------- overview cache: one fetch feeds every owner screen ----------

let overview = null;
async function loadOverview(force = false) {
  if (!overview || force) overview = await api("/api/owner");
  return overview;
}

// Who, besides the owner, has opened a tool. The owner's own previews are
// not the group receiving it, so they never count toward "opened".
function openedCount(tool, circle) {
  const others = (circle?.members || []).filter((member) => !member.is_owner);
  const opened = others.filter((member) => (tool.opened_by || []).includes(member.id)).length;
  return { opened, of: others.length };
}

function ownerToken(circleId) {
  const circle = overview?.circles.find((entry) => entry.id === circleId);
  return circle?.members.find((member) => member.is_owner)?.token;
}

// A group as a row of faces: filled once that person has opened the tool,
// ringed in green while they are on it right now.
function facesView(tool, circle) {
  const others = (circle?.members || []).filter((member) => !member.is_owner);
  if (!others.length) return "";
  const shown = others.slice(0, 6);
  const { opened, of } = openedCount(tool, circle);
  return `<div class="faces" role="img" aria-label="${opened} of ${of} have opened it">${shown
    .map((member) => {
      const isIn = (tool.opened_by || []).includes(member.id);
      const isHere = (tool.here_now_ids || []).includes(member.id);
      const state = isHere ? "is using it now" : isIn ? "has opened it" : "has not opened it yet";
      return `<span class="face${isIn ? " is-in" : ""}${isHere ? " is-here" : ""}" title="${esc(member.name)} ${state}">${esc(initials(member.name))}</span>`;
    })
    .join("")}${others.length > shown.length ? `<span class="face" title="and ${others.length - shown.length} more">+${others.length - shown.length}</span>` : ""}</div>`;
}

// ---------- landing ----------

// The one committed mechanism, shown rather than described: the text a
// group actually gets. STATE-SWAP, per DENY.md: one message appears at a
// time, opacity only, nothing travels. Example content, labelled as such.
const THREAD = [
  { out: true, text: "Here's our prayer list for Monday class. This link is just for you, Ruth." },
  { out: true, link: true },
  { who: "Ruth", text: "Added Harold's knee surgery. It opened right up, no password!" },
  { who: "Harold", text: "Thank you all. I can see everyone's names on it." },
];

function threadView() {
  return `
    <figure class="thread enter enter-4 m-0" aria-label="Example: the text a Bible class gets">
      <div class="thread-head"><span class="avatar" aria-hidden="true">MB</span><div><b>Monday Bible Class</b><span>Ruth, Harold, Dottie and you</span></div></div>
      <ol class="thread-body">${THREAD.map((message) =>
        message.link
          ? `<li class="msg msg-out msg-link"><span class="link-card"><b>Prayer list</b><span>Opens as Ruth, for Monday Bible Class</span></span></li>`
          : `<li class="msg ${message.out ? "msg-out" : "msg-in"}">${message.who ? `<span class="who">${esc(message.who)}</span>` : ""}${esc(message.text)}</li>`,
      ).join("")}</ol>
      <figcaption class="thread-foot">An example. Each person gets their own link, so the list knows who wrote what.</figcaption>
    </figure>`;
}

function runThread() {
  const messages = [...app.querySelectorAll(".thread .msg")];
  if (!messages.length) return;
  const reduce = matchMedia("(prefers-reduced-motion: reduce)").matches;
  if (reduce) return messages.forEach((message) => message.classList.add("is-shown"));
  let step = 0;
  const tick = () => {
    if (!document.body.contains(messages[0])) return clearInterval(timer);
    if (step >= messages.length + 2) {
      step = 0;
      messages.forEach((message) => message.classList.remove("is-shown"));
      return;
    }
    messages[step]?.classList.add("is-shown");
    step += 1;
  };
  const timer = setInterval(tick, 1400);
  setTimeout(tick, 400);
}

const PENDING_KEY = "amber.pendingRequest";

function landing() {
  app.innerHTML = `
    <div class="page">
      <header class="nav">
        <a class="brand" href="/" data-link><span class="brand-mark" aria-hidden="true"></span><span class="brand-name">Amber</span><span class="brand-sub">Circles</span></a>
      </header>
      <main id="main">
        <section class="hero">
          <div>
            <h1 class="enter enter-1">Ask Claude for a tool. Share it like a Google&nbsp;Doc.</h1>
            <p class="lede enter enter-2">Say what your Bible class, club or family needs, in plain words. Claude builds it in about a minute, and each person gets their own link by text. Nobody makes an account.</p>
            <form id="start" class="start enter enter-3">
              <label for="start-request">What do you want to make?</label>
              <textarea class="input" id="start-request" name="request" maxlength="4000" placeholder="A prayer list for my Monday Bible class"></textarea>
              <div class="start-row">
                <div class="field"><label for="start-name">Your name</label><input class="input" id="start-name" name="name" autocomplete="name" required maxlength="80"></div>
                <button class="btn btn-primary btn-lg" type="submit">Make it ${icon("arrow")}</button>
              </div>
              <p class="error-text" id="start-error" role="alert"></p>
            </form>
            <p class="fine">Free while we are in beta.</p>
            <p class="fine" id="demo-link" hidden>Or <a href="#">open the example prayer list as Ruth</a>, a member of a Monday Bible class.</p>
          </div>
          ${threadView()}
        </section>
        <section class="band" aria-label="How it works">
          <ol class="steps">
            <li><span class="step-n">1</span><b>Say what you need</b><p>"A sign-up sheet for who is bringing what to Sunday's potluck." Plain words are enough.</p></li>
            <li><span class="step-n">2</span><b>Pick who it's for</b><p>Type their names and phone numbers once. That group is the only one who can open it.</p></li>
            <li><span class="step-n">3</span><b>They open a text</b><p>Each person taps their own link. No app, no password, and it already knows their name.</p></li>
          </ol>
        </section>
        <section class="docs">
          <div><h2>What we took from Google Docs</h2><p class="lede">Docs made sharing the default. We put the same habits on small software.</p></div>
          <dl class="docs-list">
            <div><dt>One live copy</dt><dd>There is no publish button. What you keep is what everyone has.</dd></div>
            <div><dt>Try a change first</dt><dd>You see a change on your real list. Nobody else does until you tap Keep this.</dd></div>
            <div><dt>Every version kept</dt><dd>One tap goes back, and the entries can come back too.</dd></div>
            <div><dt>Ask to join</dt><dd>Someone outside the group asks by name, and you let them in with one tap.</dd></div>
            <div><dt>Sealed off</dt><dd>A tool can't reach the internet and never sees a phone number.</dd></div>
          </dl>
        </section>
        <footer class="foot">Amber Circles. Made by Amber, built with Claude.</footer>
      </main>
    </div>`;
  runThread();
  fetch("/api/demo")
    .then((response) => response.json())
    .then(({ link }) => {
      const line = app.querySelector("#demo-link");
      if (!link || !line) return;
      line.querySelector("a").href = link;
      line.hidden = false;
    })
    .catch(() => {
      /* no demo on this deployment; the line stays hidden */
    });
  const form = app.querySelector("#start");
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = form.querySelector("button");
    button.disabled = true;
    button.textContent = "Starting…";
    try {
      const { key } = await api("/api/owners", { method: "POST", body: { name: form.name.value } });
      store.set(OWNER_KEY, key);
      // What they typed on the front page is carried to the make page, so
      // the first thing they wrote is the first thing that gets built.
      if (form.request.value.trim()) store.set(PENDING_KEY, form.request.value.trim());
      navigate("/make");
    } catch (error) {
      app.querySelector("#start-error").textContent = error.message;
      button.disabled = false;
      button.innerHTML = `Make it ${icon("arrow")}`;
    }
  });
}

// ---------- dashboard ----------

function skeletonGrid(count = 3) {
  return `<div class="shelf">${Array.from({ length: count }, () => '<div class="skeleton h-320"></div>').join("")}</div>`;
}

// People who opened a tool they were not given and asked to join. One tap
// lets them in and hands the owner a text with their personal link.
async function loadRequests() {
  const target = app.querySelector("#requests");
  if (!target) return;
  try {
    const { requests } = await api("/api/requests");
    if (!requests.length) return;
    target.innerHTML = `<section class="asks"><h2 class="section-title">Waiting to join</h2>${requests
      .map(
        (ask) => `<div class="ask" data-ask="${esc(ask.id)}"><div><b>${esc(ask.name)}</b> wants to join ${esc(ask.circle_name)} for ${esc(ask.title)}${ask.note ? `<span class="sub">"${esc(ask.note)}"</span>` : ""}</div>
          <div class="actions"><button class="btn btn-sm btn-primary" data-decide="approve">Let them in</button><button class="btn btn-sm btn-ghost" data-decide="decline">No thanks</button></div></div>`,
      )
      .join("")}</section>`;
    target.querySelectorAll("[data-decide]").forEach((button) =>
      button.addEventListener("click", async () => {
        const row = button.closest("[data-ask]");
        try {
          const result = await api(`/api/requests/${row.dataset.ask}/${button.dataset.decide}`, { method: "POST" });
          if (!result.link) {
            row.remove();
            return;
          }
          const message = `${result.name.split(" ")[0]}, you're in! Here's ${result.title} for ${result.circle}: ${result.link}`;
          row.innerHTML = `<div><b>${esc(result.name)}</b> is in. Send them their link:</div><div class="actions">${
            result.phone ? `<a class="btn btn-sm btn-primary" href="sms:${encodeURIComponent(result.phone)}?&body=${encodeURIComponent(message)}">${icon("message", "icon-sm")} Text it</a>` : ""
          }<button class="btn btn-sm" data-copy="${esc(result.link)}">${icon("copy", "icon-sm")} Copy link</button></div>`;
          bindCopy();
        } catch (error) {
          toast(error.message);
        }
      }),
    );
  } catch {
    /* the list of tools still loads; requests will show on the next visit */
  }
}

async function dashboard() {
  app.innerHTML = shell(
    "tools",
    `
    <div class="masthead"><h1>Your tools</h1></div>
    <div id="requests"></div>
    <div id="tools">${skeletonGrid()}</div>
    <p class="fine mt-4"><a href="/connect" data-link>Your sign-in link and Claude connection</a>, to use Amber on another device or publish from Claude.</p>`,
  );
  loadRequests();
  try {
    const data = await loadOverview(true);
    const target = app.querySelector("#tools");
    const newTile = `<a class="tile-new" href="/make" data-link>${icon("plus")}<b>Make something new</b><span>Say it in plain words. Claude builds it.</span></a>`;
    if (!data.tools.length) {
      target.innerHTML = `<div class="shelf">${newTile}</div>`;
      return;
    }
    target.innerHTML = `
      <div class="shelf">${newTile}
        ${data.tools
          .map((tool) => {
            const circle = data.circles.find((entry) => entry.id === tool.circle_id);
            const { opened, of } = openedCount(tool, circle);
            return `
            <article class="tile">
              <a class="tile-thumb" href="/tools/${esc(tool.slug)}" data-link tabindex="-1" aria-hidden="true" data-thumb="${esc(tool.slug)}" data-circle="${esc(tool.circle_id)}"></a>
              <div class="tile-body">
                <a class="tile-title" href="/tools/${esc(tool.slug)}" data-link>${esc(tool.title)}</a>
                <span class="tile-circle">${esc(tool.circle_name)}</span>
                <div class="tile-foot">${facesView(tool, circle)}<span class="tile-meta">${opened} of ${of} opened<br>${tool.last_open ? `last ${timeAgo(tool.last_open)}` : "not opened yet"}</span></div>
              </div>
            </article>`;
          })
          .join("")}
      </div>`;
    mountThumbs();
  } catch (error) {
    if (error.status === 401) {
      store.remove(OWNER_KEY);
      return landing();
    }
    app.querySelector("#tools").innerHTML = errorView(error);
    bindRetry();
  }
}

// Each tile shows the live tool, the way Docs shows each page. They run as
// the owner, whose opens are not counted (server.js, /api/run).
async function mountThumbs() {
  const stops = [];
  activeCleanup = () => stops.forEach((stop) => stop());
  await Promise.all(
    [...app.querySelectorAll("[data-thumb]")].map(async (holder) => {
      const slug = holder.dataset.thumb;
      const token = ownerToken(holder.dataset.circle);
      if (!token) return;
      try {
        const session = await api(`/api/run/${slug}`, { member: token });
        if (!document.body.contains(holder)) return;
        stops.push(mountTool({ container: holder, slug, token, session, frameClass: "thumb-frame" }));
      } catch {
        /* the tile still links to the tool; it just has no preview */
      }
    }),
  );
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
    <div class="masthead"><div><h1>Your circles</h1><p class="lede">A circle is the permission. Share a tool with one and only those people can open it, each through their own link.</p></div></div>
    <div class="split">
      <div id="circle-list">${skeletonGrid(2)}</div>
      <form class="sheet stack" id="new-circle">
        <h2 class="section-title">New circle</h2>
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
  // Only a row that carries a link can text one. The circle page has no tool
  // in hand, and once sent the literal word "undefined" (2026-09-27).
  const sms = member.phone && link && message
    ? `sms:${encodeURIComponent(member.phone)}?&body=${encodeURIComponent(message)}`
    : null;
  return `
    <div class="person">
      <div class="avatar" aria-hidden="true">${esc(initials(member.name))}</div>
      <div class="who"><b>${esc(member.name)}${member.is_owner ? ' <span class="tag tag-neutral tag-xs">you</span>' : ""}</b><span>${esc(formatPhone(member.phone) || "No phone number yet")}</span></div>
      <div class="person-actions">
        ${sms && link && message && !member.is_owner ? `<a class="btn btn-sm btn-primary" href="${esc(sms)}">${icon("message", "icon-sm")} Text ${esc(member.name.split(" ")[0])}</a>` : ""}
        ${link ? `<button class="btn btn-sm btn-ghost" data-copy="${esc(link)}" aria-label="Copy ${esc(member.name)}'s link">${icon("copy", "icon-sm")} Copy link</button>` : ""}
        ${removable && !member.is_owner ? `<button class="btn btn-sm btn-ghost" data-remove="${esc(member.id)}" aria-label="Remove ${esc(member.name)}">${icon("trash", "icon-sm")}</button>` : ""}
      </div>
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
      <div class="masthead mt-3"><div><h1>${esc(circle.name)}</h1></div></div>
      <div class="split">
        <div class="card">
          <h2 class="card-title mt-0">People</h2>
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
          <h2 class="card-title mt-0">Tools shared here</h2>
          ${
            tools.length
              ? `<div class="people">${tools
                  .map(
                    (tool) => `
            <div class="person"><div class="who"><b>${esc(tool.title)}</b><span>${openedCount(tool, circle).opened} of ${openedCount(tool, circle).of} opened</span></div><span class="spacer"></span><a class="btn btn-sm" href="/share/${esc(tool.slug)}" data-link>Share links</a></div>`,
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
      `${data.base}/t/${tool.slug}#m=${encodeURIComponent(member.token)}`;
    app.querySelector("main").innerHTML = `
      <a class="btn btn-ghost btn-sm" href="/" data-link>${icon("back", "icon-sm")} Tools</a>
      <div class="masthead mt-3"><div><h1>Send ${esc(tool.title)}</h1>
      <p class="lede mt-1">Tap Text next to each person. Their phone gets their own link, and the tool will know who they are. Nobody outside ${esc(circle.name)} can open it.</p></div></div>
      <div class="card">
        <div class="people">${circle.members
          .filter((member) => !member.is_owner)
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
      <div class="masthead"><div><h1>Put a tool in front of a circle</h1>
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
  const signInLink = `${base}/#owner=${encodeURIComponent(key)}`;
  app.innerHTML = shell(
    "connect",
    `
    <div class="masthead"><div><h1>Let Claude publish for you</h1>
    <p class="lede mt-1">Once Claude is connected, you describe the tool and Claude builds it, publishes it here, and shares it with the circle you name.</p></div></div>
    <div class="grid items-start">
      <div class="card stack">
        <h2 class="card-title m-0">In the Claude app</h2>
        <p class="desc">Settings, then Connectors, then Add custom connector. Paste this URL. It is your private key, so do not post it anywhere.</p>
        <div class="code-block"><code>${esc(mcp)}</code><button class="btn btn-sm btn-ghost" data-copy="${esc(mcp)}">${icon("copy", "icon-sm")} Copy</button></div>
      </div>
      <div class="card stack">
        <h2 class="card-title m-0">In Claude Code</h2>
        <div class="code-block"><code>${esc(claudeCode)}</code><button class="btn btn-sm btn-ghost" data-copy="${esc(claudeCode)}">${icon("copy", "icon-sm")} Copy</button></div>
      </div>
      <div class="card stack">
        <h2 class="card-title m-0">Then ask</h2>
        <p class="quote">"${esc(prompt)}"</p>
        <button class="btn btn-sm" data-copy="${esc(prompt)}">${icon("copy", "icon-sm")} Copy prompt</button>
      </div>
      <div class="card stack">
        <h2 class="card-title m-0">Your sign-in link</h2>
        <p class="desc">Open this on another device to use Amber there. Anyone with it can manage your groups, so keep it to yourself.</p>
        <div class="code-block"><code>${esc(signInLink)}</code><button class="btn btn-sm btn-ghost" data-copy="${esc(signInLink)}">${icon("copy", "icon-sm")} Copy</button></div>
      </div>
    </div>`,
  );
  bindCopy();
}

// ---------- the runner ----------

// ---------- mounting a tool: the only code that talks to a tool frame ----------

let activeCleanup = null;
function cleanupActive() {
  activeCleanup?.();
  activeCleanup = null;
}

function mountTool({ container, slug, token, session, draft = false, frameClass = "run-frame" }) {
  container.insertAdjacentHTML(
    "beforeend",
    `<iframe class="${frameClass}" title="${esc(session.tool.title)}" sandbox="allow-scripts allow-forms allow-modals" src="/frame/${encodeURIComponent(slug)}?ticket=${encodeURIComponent(session.ticket)}${draft ? "&draft=1" : ""}"></iframe>`,
  );
  const frame = container.querySelector("iframe:last-of-type");

  // CSP closes fetch, images and forms, but no browser lets a page stop a
  // sandboxed frame from navigating ITSELF, which is the one way left to carry
  // data out in a URL. A tool loads exactly once; a second load means it tried
  // to leave, so the frame is torn down and the person is told why.
  let frameLoads = 0;
  frame.addEventListener("load", () => {
    frameLoads += 1;
    if (frameLoads < 2) return;
    frame.remove();
    stop();
    container.insertAdjacentHTML("beforeend", stateView({ glyph: "lock", title: "This tool tried to leave Amber", body: "Tools can only talk to your circle through Amber, so we closed it. Tell the circle owner." }));
  });

  // The stamp is how the frame hears about other people's changes, and it is
  // the presence heartbeat: a cheap poll while the tab is visible.
  let lastStamp = null;
  const post = (message) => frame.contentWindow?.postMessage({ amber: 1, ...message }, "*");
  const checkStamp = async () => {
    if (document.hidden) return;
    try {
      const { result } = await api(`/api/run/${slug}/rpc`, { method: "POST", member: token, body: { op: "stamp" } });
      if (lastStamp !== null && result !== lastStamp) post({ type: "change", detail: { by: "someone" } });
      lastStamp = result;
    } catch {
      /* a missed poll is retried in four seconds */
    }
  };
  checkStamp();
  const poller = setInterval(checkStamp, 4000);

  const ALLOWED = new Set(["me", "circle", "people", "list", "add", "update", "remove", "reach"]);
  const onMessage = async (event) => {
    if (event.source !== frame.contentWindow) return;
    const message = event.data || {};
    if (message.amber !== 1 || !ALLOWED.has(message.op)) return;
    try {
      if (message.op === "reach") {
        if (!session.me.isOwner) throw new Error("Only the circle owner can reach out from a tool.");
        const person = await api(`/api/run/${slug}/reach/${encodeURIComponent(message.memberId)}`, { member: token });
        if (!person.phone) throw new Error(`${person.name} has no phone number in this circle yet.`);
        location.href = `sms:${encodeURIComponent(person.phone)}?&body=${encodeURIComponent(message.message || "")}`;
        post({ id: message.id, result: { ok: true } });
        return;
      }
      const { op, id: callId, amber: _marker, ...args } = message;
      const { result } = await api(`/api/run/${slug}/rpc`, { method: "POST", member: token, body: { op, ...args } });
      post({ id: callId, result });
      if (["add", "update", "remove"].includes(op)) lastStamp = null;
    } catch (error) {
      post({ id: message.id, error: error.message });
    }
  };
  window.addEventListener("message", onMessage);
  function stop() {
    clearInterval(poller);
    window.removeEventListener("message", onMessage);
  }
  return stop;
}

// ---------- the member's view ----------

async function runner(slug) {
  const params = new URLSearchParams(location.search);
  const fromLink = new URLSearchParams(location.hash.slice(1)).get("m") || params.get("m");
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
      gate ? askView(error.data) : error.status === 404 ? stateView({ title: "This tool is gone", body: "The link is wrong, or the tool was deleted." }) : errorView(error)
    }</main></div>`;
    if (gate) bindAsk(slug, error.data);
    bindRetry();
    return;
  }

  const isOwnerHere = Boolean(store.get(OWNER_KEY)) && session.me.isOwner;
  app.innerHTML = `
    <header class="run-bar">
      ${isOwnerHere ? `<a class="btn btn-ghost btn-sm" href="/tools/${esc(slug)}" data-link aria-label="Back to the tool's page">${icon("back", "icon-sm")}</a>` : ""}
      <span class="brand-mark" aria-hidden="true"></span>
      <span class="run-title">${esc(session.tool.title)}</span>
      <span class="tag">${icon("users", "icon-sm")} ${esc(session.circle)}</span>
      <span class="run-me">You're ${esc(session.me.name.split(" ")[0])}</span>
      ${isOwnerHere ? "" : `<button class="btn btn-sm btn-ghost" id="copy-tool">Make your own</button>`}
    </header>`;
  // The first open says whose this is and that nothing is being signed up
  // for. Older people are taught that a texted link is a scam, and a tool
  // nobody trusts enough to tap is a tool nobody uses.
  const welcomeKey = `amber.welcomed.${slug}`;
  if (!isOwnerHere && !store.get(welcomeKey)) {
    document.body.classList.add("welcoming");
    app.querySelector(".run-bar").insertAdjacentHTML(
      "afterend",
      `<div class="welcome" role="note"><p><b>${esc(session.owner)}</b> shared this with ${esc(session.circle)}, just for the group. There is nothing to sign up for.</p><button class="btn btn-sm" id="welcome-ok">Got it</button></div>`,
    );
    app.querySelector("#welcome-ok").addEventListener("click", () => {
      store.set(welcomeKey, "1");
      document.body.classList.remove("welcoming");
      app.querySelector(".welcome")?.remove();
    });
  }
  activeCleanup = mountTool({ container: app, slug, token, session, draft: params.get("draft") === "1" });
  app.querySelector("#copy-tool")?.addEventListener("click", () => copyTool(slug, token, session));
}

// "Make your own", the Google Docs copy: the tool without its data, into one
// of the viewer's own groups. Someone with no Amber account is sent to start
// one, which is how a shared tool brings its circle into Amber.
async function copyTool(slug, token, session) {
  if (!store.get(OWNER_KEY)) {
    toast(`Start your own group, then come back to copy ${session.tool.title}.`);
    setTimeout(() => navigate("/"), 1400);
    return;
  }
  try {
    const { circles } = await loadOverview(true);
    if (!circles.length) {
      toast("Make a group first, then copy it into that group.");
      return navigate("/circles");
    }
    const names = circles.map((circle, index) => `${index + 1}. ${circle.name}`).join("\n");
    const pick = circles.length === 1 ? 1 : Number(prompt(`Copy ${session.tool.title} into which group?\n${names}`, "1"));
    const circle = circles[pick - 1];
    if (!circle) return;
    const copied = await api(`/api/run/${slug}/copy`, { method: "POST", member: token, body: { circle: circle.id } });
    toast(`Copied into ${circle.name}. None of this group's entries came with it.`);
    navigate(`/tools/${copied.slug}`);
  } catch (error) {
    toast(error.message);
  }
}

// The Google Docs "Request access" flow: someone opens a tool they were not
// given, asks by name, and the owner lets them in with one tap.
function askView(data) {
  return `
    <div class="state">
      <div class="glyph">${icon("lock")}</div>
      <h2>${esc(data.title)} is for ${esc(data.circle)}</h2>
      <p>Only people in ${esc(data.circle)} can open it. Ask ${esc(data.owner)} to let you in, and you will get your own link by text.</p>
      <form id="ask" class="stack">
        <div class="field"><label for="ask-name">Your name</label><input class="input" id="ask-name" name="name" required maxlength="80" autocomplete="name"></div>
        <div class="field"><label for="ask-phone">Your phone number</label><input class="input" id="ask-phone" name="phone" inputmode="tel" autocomplete="tel" required></div>
        <div class="field"><label for="ask-note">A note for ${esc(data.owner)} (optional)</label><input class="input" id="ask-note" name="note" maxlength="280"></div>
        <p class="error-text" id="ask-error" role="alert"></p>
        <button class="btn btn-primary btn-lg" type="submit">Ask to join</button>
      </form>
    </div>`;
}

function bindAsk(slug, data) {
  const form = app.querySelector("#ask");
  form?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const button = form.querySelector("button");
    button.disabled = true;
    try {
      await api(`/api/run/${slug}/ask`, { method: "POST", body: { name: form.name.value, phone: form.phone.value, note: form.note.value } });
      form.outerHTML = `<p class="quote">Sent. ${esc(data.owner)} will see your name next time they open Amber, and you will get a text with your link.</p>`;
    } catch (error) {
      app.querySelector("#ask-error").textContent = error.message;
      button.disabled = false;
    }
  });
}

// ---------- a group chat's things, on the web ----------

// Where an iMessage bubble lands when it is opened in a browser: on a Mac, on
// a phone without the app, or forwarded. Everything a chat makes lives on the
// web; the iMessage app is only where the chat edits it.
function chatPage(chatId) {
  const fragment = new URLSearchParams(location.hash.slice(1));
  const invite = fragment.get("i");
  const slug = fragment.get("t");
  const key = `amber.chat.${chatId}`;
  if (invite) store.set(`${key}.invite`, invite);
  history.replaceState({}, "", `/c/${chatId}`);
  let participant = store.get("amber.participant");
  if (!participant) {
    participant = `web-${crypto.randomUUID()}`;
    store.set("amber.participant", participant);
  }
  const token = store.get(key);
  const frame = (content) => {
    app.innerHTML = `<div class="page"><header class="nav"><a class="brand" href="/" data-link><span class="brand-mark" aria-hidden="true"></span><span class="brand-name">Amber</span></a></header><main id="main">${content}</main></div>`;
  };
  const show = async (memberToken) => {
    if (slug) {
      location.replace(`/t/${slug}#m=${encodeURIComponent(memberToken)}`);
      return;
    }
    frame('<div class="skeleton h-320"></div>');
    try {
      const response = await fetch(`/api/chats/${chatId}`, { headers: { "x-amber-chat": memberToken } });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "That did not load.");
      frame(`<div class="masthead"><h1>Made in this chat</h1></div>
        <div class="shelf">${data.tools.length ? data.tools.map((tool) => `
          <article class="tile"><div class="tile-body">
            <a class="tile-title" href="/t/${esc(tool.slug)}#m=${encodeURIComponent(memberToken)}">${esc(tool.title)}</a>
            <span class="tile-circle">${tool.made_by ? `By ${esc(tool.made_by)}` : ""}</span>
            <span class="tile-meta">${tool.entries} ${tool.entries === 1 ? "entry" : "entries"}, changed ${timeAgo(tool.updated_at)}</span>
          </div></article>`).join("") : '<p class="lede">Nothing yet. Make something from the Amber app in Messages.</p>'}</div>
        <p class="fine mt-4">In this chat: ${esc(data.people.map((person) => person.name).join(", "))}</p>`);
    } catch (error) {
      frame(errorView(error));
      bindRetry();
    }
  };
  if (token) return show(token);
  const savedInvite = store.get(`${key}.invite`);
  if (!savedInvite) {
    frame(stateView({ glyph: "lock", title: "This link is missing its invite", body: "Ask someone in the chat to send it again from the Amber app." }));
    return;
  }
  frame(`<div class="state"><h2>You're invited</h2><p>Someone in your chat made something with Amber. Say your name once, and you can open everything the chat makes.</p>
    <form id="join" class="stack"><div class="field"><label for="join-name">Your first name</label><input class="input" id="join-name" name="name" required maxlength="80" autocomplete="given-name"></div>
    <p class="error-text" id="join-error" role="alert"></p><button class="btn btn-primary btn-lg" type="submit">Open it ${icon("arrow")}</button></form></div>`);
  app.querySelector("#join").addEventListener("submit", async (event) => {
    event.preventDefault();
    const form = event.currentTarget;
    form.querySelector("button").disabled = true;
    try {
      const response = await fetch(`/api/chats/${chatId}/join`, {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({ invite: savedInvite, name: form.name.value, participant }),
      });
      const data = await response.json();
      if (!response.ok) throw new Error(data.error || "That did not work. Try again.");
      store.set(key, data.token);
      show(data.token);
    } catch (error) {
      app.querySelector("#join-error").textContent = error.message;
      form.querySelector("button").disabled = false;
    }
  });
}

// ---------- make: the page Grandpa starts on ----------

const IDEAS = [
  "A prayer list for my Monday Bible class. Anyone can add a request, and we can mark when a prayer is answered.",
  "A sign-up sheet for who is bringing what to Sunday's potluck.",
  "Rides to church: who can drive, who needs a ride, and who is going with whom.",
  "Attendance for our club meetings, and who we have not seen in a while.",
];

// Reading what the model is doing into words a person can follow. A two
// minute blank wait reads as broken, and older users blame themselves (NN/g,
// research/vibe-coding-vs-docs.md), so every stage is named as it happens.
function progressView() {
  return `
    <div class="progress" aria-live="polite">
      <ol class="stages">
        <li data-stage="thinking"><span class="mark"></span><span>Reading what you asked for</span><span class="when"></span></li>
        <li data-stage="writing"><span class="mark"></span><span>Writing it</span><span class="when"></span></li>
        <li data-stage="checking"><span class="mark"></span><span>Checking it works</span><span class="when"></span></li>
      </ol>
      <p class="fine" id="elapsed">Usually takes about a minute.</p>
    </div>`;
}

async function streamBuild(body, root) {
  const order = ["thinking", "writing", "checking"];
  const started = Date.now();
  const clock = setInterval(() => {
    const seconds = Math.round((Date.now() - started) / 1000);
    const el = root.querySelector("#elapsed");
    if (el) el.textContent = `${seconds} seconds so far. Usually takes about a minute.`;
  }, 1000);
  const mark = (stage, detail = "") => {
    const index = order.indexOf(stage);
    root.querySelectorAll(".stages li").forEach((row, rowIndex) => {
      row.className = rowIndex < index ? "is-done" : rowIndex === index ? "is-now" : "";
      if (rowIndex === index && detail) row.querySelector(".when").textContent = detail;
    });
  };
  try {
    const headers = { "content-type": "application/json", authorization: `Bearer ${store.get(OWNER_KEY)}` };
    const response = await fetch("/api/build", { method: "POST", headers, body: JSON.stringify(body) });
    if (!response.ok) {
      const data = await response.json().catch(() => ({}));
      throw new Error(data.error || "That did not start. Try again.");
    }
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      let split;
      while ((split = buffer.indexOf("\n\n")) >= 0) {
        const chunk = buffer.slice(0, split);
        buffer = buffer.slice(split + 2);
        const event = chunk.match(/^event: (.*)$/m)?.[1];
        const data = JSON.parse(chunk.match(/^data: (.*)$/m)?.[1] || "{}");
        if (event === "progress") mark(data.stage, data.chars ? `${data.chars.toLocaleString()} letters` : "");
        if (event === "error") throw new Error(data.message);
        if (event === "done") return data;
      }
    }
    throw new Error("The connection dropped before it finished. Try again.");
  } finally {
    clearInterval(clock);
  }
}

async function makePage() {
  app.innerHTML = shell("make", '<div class="skeleton h-360"></div>');
  let data;
  try {
    data = await loadOverview(true);
  } catch (error) {
    app.querySelector("main").innerHTML = errorView(error);
    return bindRetry();
  }
  app.querySelector("main").innerHTML = `
    <div class="masthead"><div><h1>What do you want to make?</h1>
    <p class="lede">Say it the way you would say it to a friend. Claude builds it, and only the people you choose can open it.</p></div></div>
    <div class="make-layout">
    <form id="make" class="make">
      <label class="skip" for="make-request">What you want</label>
      <textarea class="input make-request" id="make-request" name="request" required maxlength="4000" placeholder="A prayer list for my Monday Bible class…"></textarea>
      <div class="ideas"><span class="fine">Or start from one of these:</span>${IDEAS.map((idea, index) => `<button type="button" class="idea" data-idea="${index}">${esc(idea.split(".")[0])}</button>`).join("")}</div>
      <div class="field who">
        <label for="make-circle">Who is it for?</label>
        <select class="input" id="make-circle" name="circle">
          ${data.circles.map((circle) => `<option value="${esc(circle.id)}">${esc(circle.name)} (${circle.members.length} ${circle.members.length === 1 ? "person" : "people"})</option>`).join("")}
          <option value="__new" ${data.circles.length ? "" : "selected"}>A new group…</option>
        </select>
      </div>
      <div class="new-group stack" id="new-group" ${data.circles.length ? "hidden" : ""}>
        <div class="field"><label for="group-name">What do you call this group?</label><input class="input" id="group-name" name="groupName" placeholder="Monday Bible Class" maxlength="80"></div>
        <div class="field"><label for="group-people">Who is in it? One person per line: name, then phone</label><textarea class="input" id="group-people" name="groupPeople" placeholder="Ruth Miller, 253 555 0101&#10;Harold Jensen, 253 555 0102"></textarea><span class="hint">Phones are only used to text each person their own link. The tool never sees them.</span></div>
      </div>
      <p class="error-text" id="make-error" role="alert"></p>
      <button class="btn btn-primary btn-lg" type="submit">Make it ${icon("arrow")}</button>
    </form>
    <aside class="gets" aria-live="polite"><h2 class="section-title">Who gets it</h2><div id="gets-list"></div></aside>
    </div>
    <div id="make-progress"></div>`;
  const form = app.querySelector("#make");
  const pending = store.get(PENDING_KEY);
  if (pending) {
    form.request.value = pending;
    store.remove(PENDING_KEY);
  }
  form.querySelectorAll("[data-idea]").forEach((button) =>
    button.addEventListener("click", () => {
      form.request.value = IDEAS[Number(button.dataset.idea)];
      form.request.focus();
    }),
  );
  // The circle is the permission, so it is shown as people while it is
  // being chosen: the faces of exactly who will get a text.
  const drawGets = () => {
    const list = app.querySelector("#gets-list");
    const picked = data.circles.find((circle) => circle.id === form.circle.value);
    const people = picked
      ? picked.members.filter((member) => !member.is_owner).map((member) => member.name)
      : parseMembers(form.groupPeople.value).map((person) => person.name);
    list.innerHTML = people.length
      ? `<ul class="gets-people">${people.map((name) => `<li><span class="avatar" aria-hidden="true">${esc(initials(name))}</span>${esc(name)}</li>`).join("")}</ul>
         <p class="fine">Each of them gets their own link by text. Nobody else can open it.</p>`
      : '<p class="fine">Nobody yet. Type each person on their own line, with a phone number so you can text them their link.</p>';
  };
  form.circle.addEventListener("change", () => {
    app.querySelector("#new-group").hidden = form.circle.value !== "__new";
    drawGets();
  });
  form.groupPeople.addEventListener("input", drawGets);
  drawGets();
  form.addEventListener("submit", async (event) => {
    event.preventDefault();
    const error = app.querySelector("#make-error");
    error.textContent = "";
    try {
      let circle = form.circle.value;
      if (circle === "__new") {
        if (!form.groupName.value.trim()) throw new Error("Give the group a name first.");
        const created = await api("/api/circles", { method: "POST", body: { name: form.groupName.value, members: parseMembers(form.groupPeople.value) } });
        circle = created.id;
      }
      form.hidden = true;
      app.querySelector(".gets").hidden = true;
      const progress = app.querySelector("#make-progress");
      progress.innerHTML = progressView();
      const done = await streamBuild({ request: form.request.value, circle }, progress);
      toast("It is ready");
      navigate(`/tools/${done.slug}`);
    } catch (problem) {
      form.hidden = false;
      app.querySelector(".gets").hidden = false;
      app.querySelector("#make-progress").innerHTML = "";
      error.textContent = problem.message;
    }
  });
}

// ---------- the tool's page: see it, change it, go back, share it ----------

async function toolPage(slug) {
  app.innerHTML = shell("tools", '<div class="skeleton h-420"></div>');
  let data;
  let versions;
  try {
    [data, { versions }] = await Promise.all([loadOverview(true), api(`/api/tools/${slug}/versions`)]);
  } catch (error) {
    app.querySelector("main").innerHTML = errorView(error);
    return bindRetry();
  }
  const tool = data.tools.find((entry) => entry.slug === slug);
  if (!tool) {
    app.querySelector("main").innerHTML = stateView({ title: "No such tool", body: "It may have been deleted.", action: '<a class="btn" href="/" data-link>Back to your tools</a>' });
    return;
  }
  const circle = data.circles.find((entry) => entry.id === tool.circle_id);
  const token = ownerToken(tool.circle_id);
  const hereNow = circle.members.filter((member) => !member.is_owner && (tool.here_now_ids || []).includes(member.id)).map((member) => member.name.split(" ")[0]);
  const others = circle.members.filter((member) => !member.is_owner);
  const notYet = others.filter((member) => !(tool.opened_by || []).includes(member.id)).map((member) => member.name.split(" ")[0]);
  app.querySelector("main").innerHTML = `
    <div class="tool-head">
      <div><a class="crumb" href="/" data-link>${icon("back", "icon-sm")} Your tools</a><h1>${esc(tool.title)}</h1><a class="circle-link" href="/circles/${esc(circle.id)}" data-link>For ${esc(circle.name)}</a></div>
      <div class="tool-head-actions">${facesView(tool, circle)}<a class="btn" href="/t/${esc(slug)}#m=${encodeURIComponent(token)}">${icon("open", "icon-sm")} Full screen</a><a class="btn btn-primary" href="/share/${esc(slug)}" data-link>${icon("message", "icon-sm")} Send to ${esc(circle.name)}</a></div>
    </div>
    <div class="workspace">
      <div class="phone" id="preview">${tool.has_draft ? '<p class="phone-label">The change, with your real data. Nobody else sees it yet.</p>' : '<p class="phone-label">What everyone sees right now</p>'}</div>
      <div class="panel">
        ${
          tool.has_draft
            ? `<section class="sheet stack draft">
                <h2 class="section-title">Your change is ready to try</h2>
                <p class="quote">"${esc(tool.draft_request)}"</p>
                <p class="lede">Try it in the preview. If you like it, keep it and everyone gets it. If not, put it back and nothing changes.</p>
                <div class="row"><button class="btn btn-primary btn-lg" id="keep">Keep this</button><button class="btn btn-lg" id="discard">Put it back</button></div>
              </section>`
            : `<form class="stack" id="change">
                <h2 class="section-title">Change something</h2>
                <label class="skip" for="change-request">What to change</label>
                <textarea class="input" id="change-request" name="request" required maxlength="4000" placeholder="Make the writing bigger. Add a place for the date."></textarea>
                <p class="error-text" id="change-error" role="alert"></p>
                <button class="btn btn-primary" type="submit">Make the change</button>
                <p class="fine">You will see it here first. Nothing changes for anyone else until you keep it.</p>
              </form>
              <div id="change-progress"></div>`
        }
        <section class="stack">
          <h2 class="section-title">Who has it</h2>
          <p class="lede">${others.length - notYet.length} of ${others.length} have opened it${hereNow.length ? `. <span class="present">${esc(hereNow.join(", "))} ${hereNow.length === 1 ? "is" : "are"} using it right now.</span>` : "."}</p>
          ${notYet.length ? `<p class="fine">Not opened yet: ${esc(notYet.join(", "))}. <a href="/share/${esc(slug)}" data-link>Send ${notYet.length === 1 ? "their link" : "their links"}</a></p>` : ""}
        </section>
        <section class="stack">
          <h2 class="section-title">Earlier versions</h2>
          <ol class="versions">${versions
            .map(
              (version) => `<li><div><b>Version ${version.version}</b><span>${esc(version.request || "The first version")}</span><span class="fine">${timeAgo(version.created_at)}</span></div>${
                version.current
                  ? '<span class="tag">Live now</span>'
                  : `<div class="restore"><button class="btn btn-sm" data-restore="${version.version}">Go back to this</button>${
                      version.has_entries ? `<button class="btn btn-sm btn-ghost" data-restore="${version.version}" data-entries="${version.entry_count}">Entries too (${version.entry_count})</button>` : ""
                    }</div>`
              }</li>`,
            )
            .join("")}</ol>
        </section>
      </div>
    </div>`;

  try {
    const session = await api(`/api/run/${slug}`, { member: token });
    activeCleanup = mountTool({ container: app.querySelector("#preview"), slug, token, session, draft: tool.has_draft, frameClass: "phone-frame" });
  } catch (error) {
    app.querySelector("#preview").insertAdjacentHTML("beforeend", errorView(error));
  }

  app.querySelector("#keep")?.addEventListener("click", async () => {
    await api(`/api/tools/${slug}/keep`, { method: "POST" });
    toast("Kept. Everyone has the new version now.");
    toolPage(slug);
  });
  app.querySelector("#discard")?.addEventListener("click", async () => {
    await api(`/api/tools/${slug}/discard`, { method: "POST" });
    toast("Put back. Nothing changed.");
    toolPage(slug);
  });
  app.querySelectorAll("[data-restore]").forEach((button) =>
    button.addEventListener("click", async () => {
      const entries = button.dataset.entries !== undefined;
      const question = entries
        ? `Put version ${button.dataset.restore} back, with the list exactly as it was then (${button.dataset.entries} entries)? Anything added since goes away, and you can undo this from this same list.`
        : `Go back to version ${button.dataset.restore}? Everyone will get that version. The saved entries stay as they are.`;
      if (!confirm(question)) return;
      try {
        await api(`/api/tools/${slug}/restore`, { method: "POST", body: { version: Number(button.dataset.restore), entries } });
      } catch (error) {
        toast(error.message);
        return toolPage(slug);
      }
      toast(entries ? `Back to version ${button.dataset.restore}, entries too` : `Back to version ${button.dataset.restore}`);
      toolPage(slug);
    }),
  );
  const change = app.querySelector("#change");
  change?.addEventListener("submit", async (event) => {
    event.preventDefault();
    const progress = app.querySelector("#change-progress");
    change.hidden = true;
    progress.innerHTML = progressView();
    try {
      await streamBuild({ request: change.request.value, slug }, progress);
      cleanupActive();
      toolPage(slug);
    } catch (problem) {
      change.hidden = false;
      progress.innerHTML = "";
      app.querySelector("#change-error").textContent = problem.message;
    }
  });
}

render();
