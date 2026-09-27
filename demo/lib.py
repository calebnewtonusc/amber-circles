import json, time
BASE = "https://web-production-058309.up.railway.app"
KEY = open('/tmp/demo.key').read().strip()

CAPTION_JS = """(text) => {
  let el = document.getElementById('__cap');
  if (!el) {
    el = document.createElement('div'); el.id='__cap';
    Object.assign(el.style, {position:'fixed', left:'50%', bottom:'28px', transform:'translateX(-50%)', zIndex:'99999',
      background:'#201f1d', color:'#fffdf7', font:'500 22px/1.3 Outfit, sans-serif', padding:'14px 22px', borderRadius:'4px',
      maxWidth:'80vw', textAlign:'center', letterSpacing:'-0.005em', transition:'opacity 200ms ease-out'});
    document.body.appendChild(el);
  }
  el.style.opacity = text ? '1' : '0';
  if (text) el.textContent = text;
}"""

def caption(page, text):
    page.evaluate(CAPTION_JS, text)

def log(marks, name):
    marks.append((name, time.time()))
