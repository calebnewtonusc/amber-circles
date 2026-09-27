import json, time, sys
sys.path.insert(0, '/private/tmp/amber-demo')
from lib import *
from playwright.sync_api import sync_playwright
slug = "prayer-list-20616c"; tok = json.load(open('/private/tmp/amber-demo/tokens.json'))
marks = []
with sync_playwright() as p:
    b = p.chromium.launch()
    desk = b.new_context(viewport={'width':1280,'height':800}, record_video_dir='/private/tmp/amber-demo/desk', record_video_size={'width':1280,'height':800}, bypass_csp=True)
    phone = b.new_context(viewport={'width':390,'height':800}, device_scale_factor=2, is_mobile=True, has_touch=True, record_video_dir='/private/tmp/amber-demo/phone', record_video_size={'width':390,'height':800}, bypass_csp=True)
    d = desk.new_page(); r = phone.new_page(); log(marks, 'start')
    d.goto(BASE + "/"); d.evaluate(f"localStorage.setItem('amber.owner', {json.dumps(KEY)})")
    d.goto(BASE + f"/tools/{slug}"); d.wait_for_timeout(2500)
    caption(d, "Each person gets their own link by text. No accounts, no passwords.")
    r.goto(BASE + f"/t/{slug}?m={tok['Ruth Miller']}"); r.wait_for_timeout(2500); log(marks, 'ruth_open')
    frame = r.frames[1]
    frame.wait_for_selector('#text', timeout=20000)
    caption(d, "Ruth opens hers. It says who shared it, and there is nothing to sign up for.")
    r.wait_for_timeout(2200)
    if r.is_visible('#welcome-ok'): r.click('#welcome-ok')
    r.wait_for_timeout(600)
    frame.click('#text'); frame.type('#text', "Healing for Pastor Dan's knee after surgery.", delay=45)
    r.wait_for_timeout(400); frame.click('#add'); log(marks, 'ruth_added')
    caption(d, "She adds a prayer from her phone.")
    d.frames[1].wait_for_selector("text=Pastor Dan", timeout=12000)
    d.wait_for_timeout(300)
    d.frames[1].evaluate("[...document.querySelectorAll('*')].filter(e => e.children.length === 0 && /Pastor Dan/.test(e.textContent))[0]?.scrollIntoView({behavior: 'smooth', block: 'center'})")
    d.wait_for_timeout(4500)
    caption(d, "It shows up for the whole class, right away.")
    d.wait_for_timeout(3000)
    d.reload(); d.wait_for_timeout(3000)
    caption(d, "And you can see who is using it right now.")
    d.wait_for_timeout(3500); log(marks, 'end')
    desk.close(); phone.close(); b.close()
t0 = marks[0][1]
json.dump({k: round(v - t0, 2) for k, v in marks}, open('/private/tmp/amber-demo/share.json', 'w'))
print(open('/private/tmp/amber-demo/share.json').read())
