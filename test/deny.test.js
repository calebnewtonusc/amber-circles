// DENY.md, enforced. ux-lint reads a DENY.md for display and never turns its
// lines into rules (load_project_rules is defined and never called, checked
// 2026-09-27), so a refusal that lives only in prose here would never fire.
// Each test below is one line of DENY.md that a regex can see.
import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";

const css = readFileSync(new URL("../public/app.css", import.meta.url), "utf8");
const js = readFileSync(new URL("../public/app.js", import.meta.url), "utf8");
const code = css.replace(/\/\*[\s\S]*?\*\//g, "");
const both = `${code}\n${js}`;

const hits = (pattern, text = both) =>
  [...text.matchAll(pattern)].map((m) => m[0]);

test("no gradient of any kind", () => {
  assert.deepEqual(hits(/(linear|radial|conic)-gradient\(/g), []);
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

test("no blurred or soft drop shadow", () => {
  const shadows = hits(/box-shadow\s*:\s*([^;}]+)/g, code).filter(
    (value) => !/:\s*none/.test(value),
  );
  assert.deepEqual(shadows, []);
});

test("no weight above 600", () => {
  assert.deepEqual(hits(/font-weight\s*:\s*(700|800|900|bold)/g), []);
  assert.deepEqual(hits(/font:\s*(700|800|900)\b/g), []);
  assert.doesNotMatch(
    css,
    /wght@[^'"]*\b(700|800|900)\b/,
    "no heavy cut is even loaded",
  );
});

test("uppercase only on the kicker", () => {
  const blocks = [
    ...code.matchAll(/([^{}]+)\{[^}]*text-transform\s*:\s*uppercase/g),
  ].map((m) => m[1].trim());
  assert.deepEqual(
    blocks.filter((selector) => selector !== ".kicker"),
    [],
  );
});

test("buttons are outlines: no button rule sets a solid fill at rest", () => {
  const rest = [...code.matchAll(/(\.btn[\w-]*)\s*\{([^}]*)\}/g)]
    .filter(([, selector]) => !/:(hover|active|focus)/.test(selector))
    .filter(([, , body]) =>
      /background(-color)?\s*:\s*var\(--(gold|ink)/.test(body),
    )
    .map(([, selector]) => selector);
  assert.deepEqual(rest, []);
});

test("one hue: every colour literal is ink, gold or a state colour", () => {
  const allowed = new Set([
    "#f3f2f2",
    "#f8f7f5",
    "#201f1d",
    "#3f3d3b",
    "#605d5d",
    "#8a8683",
    "#fff3e4",
    "#ffe3bf",
    "#facb8d",
    "#c28d41",
    "#7d5411",
    "#5a3b0a",
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
