import json, time, sys
sys.path.insert(0, '/private/tmp/amber-demo')
from lib import *
from playwright.sync_api import sync_playwright
marks = []
REQUEST = "A prayer list for my Monday Bible class. Anyone can add a prayer request, and we can mark when a prayer is answered."
with sync_playwright() as p:
    b = p.chromium.launch()
    ctx = b.new_context(viewport={'width':1280,'height':800}, record_video_dir='/private/tmp/amber-demo/make', record_video_size={'width':1280,'height':800}, bypass_csp=True)
    pg = ctx.new_page(); log(marks, 'start')
    pg.goto(BASE + "/"); pg.evaluate(f"localStorage.setItem('amber.owner', {json.dumps(KEY)})")
    pg.goto(BASE + "/make"); pg.wait_for_selector('#make-request'); pg.wait_for_timeout(600)
    log(marks, 'page')
    caption(pg, "Say what your group needs, in your own words.")
    pg.click('#make-request'); pg.keyboard.type(REQUEST, delay=28)
    pg.wait_for_timeout(500)
    pg.select_option('#make-circle', label=None, index=0)
    caption(pg, "Pick who it is for. Only they will be able to open it.")
    pg.wait_for_timeout(2200)
    caption(pg, "")
    pg.click('button[type=submit]'); log(marks, 'build_start')
    pg.wait_for_timeout(1500)
    caption(pg, "Claude builds it. Every step is named as it happens.")
    pg.wait_for_url('**/tools/**', timeout=300000); log(marks, 'build_end')
    caption(pg, "")
    pg.wait_for_timeout(3500)
    caption(pg, "It is live. One copy, the same for everyone in the class.")
    pg.wait_for_timeout(3500); log(marks, 'end')
    slug = pg.url.rsplit('/', 1)[-1]
    ctx.close(); b.close()
t0 = marks[0][1]
json.dump({'slug': slug, 'marks': {k: round(v - t0, 2) for k, v in marks}}, open('/private/tmp/amber-demo/make.json', 'w'))
print(open('/private/tmp/amber-demo/make.json').read())
