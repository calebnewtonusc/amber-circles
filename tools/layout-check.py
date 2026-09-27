#!/usr/bin/env python3
"""Measure what a phone actually renders, on every screen, at 390 wide.

Usage: AMBER_URL=http://localhost:8787 AMBER_OWNER_KEY=amb_... python3 tools/layout-check.py
Exits 1 on any failure.

Born 2026-09-27: on production the landing page's one-line name box rendered
200px tall on a phone, because a flex-basis meant as a width became a height
once the form stacked. Nothing else caught it: the deny test reads CSS text,
axe reads semantics, and design-gate only looks at the pages it is pointed at.
"""
import json, os, sys, urllib.request
from playwright.sync_api import sync_playwright

BASE = os.environ.get("AMBER_URL", "http://localhost:8787")
KEY = os.environ["AMBER_OWNER_KEY"]
req = urllib.request.Request(BASE + "/api/owner", headers={"authorization": f"Bearer {KEY}"})
ov = json.load(urllib.request.urlopen(req))
slug = ov["tools"][0]["slug"]
cid = ov["circles"][0]["id"]
pages = {"landing": "/", "make": "/make", "tools": "/", "toolpage": f"/tools/{slug}", "share": f"/share/{slug}",
         "circles": "/circles", "circle": f"/circles/{cid}", "connect": "/connect"}

# A single-line input taller than this is a layout accident, not a design.
MAX_INPUT = 64
# WCAG 2.5.5's 44px target, held for the primary-size buttons; .btn-sm is
# the deliberate secondary size and is held to WCAG 2.5.8's 24px instead.
MIN_BUTTON, MIN_SMALL = 44, 24

MEASURE = """() => {
  const out = [];
  const seen = (el) => { const r = el.getBoundingClientRect(); return r.width > 0 && r.height > 0; };
  document.querySelectorAll('input.input, select.input').forEach((el) => {
    if (seen(el)) out.push({kind: 'input', id: el.id || el.name, h: el.getBoundingClientRect().height});
  });
  document.querySelectorAll('.btn').forEach((el) => {
    if (seen(el)) out.push({kind: el.classList.contains('btn-sm') ? 'small' : 'button', id: el.textContent.trim().slice(0, 30), h: el.getBoundingClientRect().height});
  });
  const overflow = document.documentElement.scrollWidth - document.documentElement.clientWidth;
  return {items: out, overflow};
}"""

failures = 0
with sync_playwright() as p:
    browser = p.chromium.launch()
    page = browser.new_page(viewport={"width": 390, "height": 844})
    for name, path in pages.items():
        page.goto(BASE + "/")
        page.evaluate("localStorage.clear()")
        if name != "landing":
            page.evaluate(f"localStorage.setItem('amber.owner', {json.dumps(KEY)})")
        page.goto(BASE + path)
        page.wait_for_timeout(1500)
        result = page.evaluate(MEASURE)
        if result["overflow"] > 1:
            failures += 1
            print(f"{name}: page scrolls sideways by {result['overflow']}px")
        for item in result["items"]:
            if item["kind"] == "input" and item["h"] > MAX_INPUT:
                failures += 1; print(f"{name}: input {item['id']!r} is {item['h']:.0f}px tall")
            if item["kind"] == "button" and item["h"] < MIN_BUTTON:
                failures += 1; print(f"{name}: button {item['id']!r} is {item['h']:.0f}px, under {MIN_BUTTON}")
            if item["kind"] == "small" and item["h"] < MIN_SMALL:
                failures += 1; print(f"{name}: small button {item['id']!r} is {item['h']:.0f}px, under {MIN_SMALL}")
    browser.close()
print(f"layout: {failures} failure(s)")
sys.exit(1 if failures else 0)
