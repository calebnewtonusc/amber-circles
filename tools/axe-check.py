#!/usr/bin/env python3
import json, urllib.request
from playwright.sync_api import sync_playwright
import os, sys, pathlib, urllib.request as _u
# Usage: AMBER_URL=http://localhost:8787 AMBER_OWNER_KEY=amb_... python3 tools/axe-check.py
# Needs an owner with at least one circle and tool. Exits 1 on any violation.
BASE=os.environ.get("AMBER_URL","http://localhost:8787"); key=os.environ["AMBER_OWNER_KEY"]
req=urllib.request.Request(BASE+"/api/owner"); req.add_header("authorization",f"Bearer {key}")
ov=json.load(urllib.request.urlopen(req)); slug=ov["tools"][0]["slug"]; cid=ov["circles"][0]["id"]
cache=pathlib.Path("/tmp/axe-4.10.2.min.js")
if not cache.exists(): cache.write_bytes(_u.urlopen("https://cdn.jsdelivr.net/npm/axe-core@4.10.2/axe.min.js").read())
axe=cache.read_text()
found=0
pages={"landing":"/","make":"/make","tools":"/","toolpage":f"/tools/{slug}","share":f"/share/{slug}","circles":"/circles","circle":f"/circles/{cid}","connect":"/connect"}
with sync_playwright() as p:
    b=p.chromium.launch()
    for w in (1280,390):
        ctx=b.new_context(viewport={'width':w,'height':900}, bypass_csp=True); pg=ctx.new_page()
        for name,path in pages.items():
            pg.goto(BASE+"/"); pg.evaluate("localStorage.clear()")
            if name!="landing": pg.evaluate(f"localStorage.setItem('amber.owner', {json.dumps(key)})")
            pg.goto(BASE+path); pg.wait_for_timeout(1500)
            pg.add_script_tag(content=axe)
            r=pg.evaluate("async()=>{const r=await axe.run(document,{runOnly:['wcag2a','wcag2aa','wcag21aa','best-practice']});return r.violations.map(v=>({id:v.id,impact:v.impact,n:v.nodes.length,t:v.nodes[0]?.target?.join(' '),s:v.nodes[0]?.failureSummary?.slice(0,160)}))}")
            for v in r:
                found+=1; print(w, name, v['impact'], v['id'], v['n'], '|', v['t'], '|', (v['s'] or '').replace('\n',' '))
        ctx.close()
    b.close()
print(f"axe: {found} violation(s)")
sys.exit(1 if found else 0)
