// DENY.md, enforced. ux-lint reads a DENY.md for display and never turns its
// lines into rules (load_project_rules is defined and never called, checked
// 2026-09-27), so a refusal that lives only in prose here would never fire.
// Each test below is one line of DENY.md that a regex can see. Rewritten the
// same day for the signage stance, after the editorial one read as generated.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const read = (path) => readFileSync(new URL(path, import.meta.url), "utf8");
const css = read("../public/app.css");
const js = read("../public/app.js");
const favicon = read("../public/favicon.svg");
const code = css.replace(/\/\*[\s\S]*?\*\//g, "");
const both = `${code}\n${js}`;

const hits = (pattern, text = both) =>
  [...text.matchAll(pattern)].map((m) => m[0]);

test("no italic anywhere", () => {
  assert.deepEqual(hits(/font-style\s*:\s*italic|<em>|<i>/g), []);
  assert.doesNotMatch(css, /ital[,@]/, "no italic cut is even loaded");
});

test("no serif: one hyperlegible family", () => {
  const families = hits(/font-family\s*:\s*([^;}]+)/g, code).map((rule) =>
    rule.split(":")[1].trim(),
  );
  assert.deepEqual(
    families.filter((value) => !/^var\(--(sans|mono)\)$/.test(value)),
    [],
  );
  assert.deepEqual(hits(/Newsreader|Georgia|(?<!sans-)\bserif\b/g, code), []);
});

test("no uppercase and no kicker", () => {
  assert.deepEqual(hits(/text-transform\s*:\s*uppercase/g), []);
  assert.deepEqual(hits(/class="kicker"|\.kicker\b/g), []);
});

test("no gradient of any kind, favicon included", () => {
  assert.deepEqual(hits(/(linear|radial|conic)-gradient\(/g), []);
  assert.doesNotMatch(favicon, /Gradient/);
});

test("no radius above 4px, except 50% for people", () => {
  const radii = hits(/border-radius\s*:\s*([^;}"]+)/g, code).map((r) =>
    r.split(":")[1].trim(),
  );
  const bad = radii.filter(
    (value) => !/^(0|4px|var\(--radius\)|50%)$/.test(value),
  );
  assert.deepEqual(bad, []);
  assert.deepEqual(hits(/9999px|rounded-full|--radius-full/g), []);
});

test("shadows are hard offsets with no blur", () => {
  const values = hits(/(box-shadow|--lift[\w-]*)\s*:\s*([^;}]+)/g, code)
    .map((rule) => rule.split(":").slice(1).join(":").trim())
    .filter((value) => value !== "none" && !value.startsWith("var(--lift"));
  const blurred = values.filter(
    (value) => !/^-?\d+(px)? -?\d+(px)? 0( 0)? (var\(--[\w-]+\)|#[0-9a-f]{6})$/i.test(value),
  );
  assert.deepEqual(blurred, []);
});

test("the primary button is a solid amber block", () => {
  const rule = code.match(/\.btn-primary\s*\{([^}]*)\}/);
  assert.ok(rule, ".btn-primary is declared");
  assert.match(rule[1], /background-color\s*:\s*var\(--amber\)/);
});

test("one accent: every colour literal is ink, paper, amber or a state colour", () => {
  const allowed = new Set([
    "#f2eee3",
    "#fffcf5",
    "#17150f",
    "#2e2b24",
    "#5c574c",
    "#ffb300",
    "#ffe9b0",
    "#8a5700",
    "#1d6b3f",
    "#a8321f",
  ]);
  const literals = hits(/#[0-9a-fA-F]{6}\b/g, code).map((hex) =>
    hex.toLowerCase(),
  );
  assert.deepEqual(
    [...new Set(literals)].filter((hex) => !allowed.has(hex)),
    [],
  );
});

test("no text under 15px", () => {
  const small = hits(/font-size\s*:\s*(\d+)px/g, code).filter(
    (rule) => Number(rule.match(/(\d+)px/)[1]) < 15,
  );
  assert.deepEqual(small, []);
});

test("entrance stagger stays under the 400ms total cap", () => {
  const delays = hits(
    /\.enter-\d+\s*\{\s*animation-delay:\s*(\d+)ms/g,
    code,
  ).map((rule) => Number(rule.match(/(\d+)ms/)[1]));
  assert.ok(delays.length > 0, "the entrance is declared");
  assert.ok(
    Math.max(...delays) <= 400,
    `last item starts at ${Math.max(...delays)}ms`,
  );
});

// Amber means "you can tap this". The first signage landing painted a
// headline, a header and a band amber too, and design-gate read it as LOUD,
// ink 0.52 against 0.15 (2026-09-27).
test("amber fills only things you can tap", () => {
  const tappable = new Set([
    ".btn-primary",
    ".btn-primary:hover",
    ".tile-new",
    ".tile-new:hover",
    ".link-card",
    ".brand-mark",
    ".skip:focus",
  ]);
  const filled = [...code.matchAll(/([^{}]+)\{[^}]*background-color\s*:\s*var\(--amber\)\s*;/g)]
    .flatMap((m) => m[1].split(",").map((selector) => selector.trim()));
  assert.deepEqual(filled.filter((selector) => !tappable.has(selector)), []);
});
