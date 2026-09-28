import SwiftUI
import WebKit

/// A double tap in the preview, waiting for what the person says about it.
struct PinDrop: Identifiable, Equatable {
    let id = UUID()
    let slug: String
    let anchor: PinAnchor
}

/// What the preview's pin layer tells the app.
enum PinEvent {
    case drop(PinAnchor)
    case resolve(String)
    case reply(String, String)
    case missing([String])

    init?(_ body: [String: Any]) {
        switch body["kind"] as? String {
        case "pin":
            guard let selector = body["selector"] as? String else { return nil }
            self = .drop(PinAnchor(selector: selector,
                                   fx: (body["fx"] as? Double) ?? 0.5,
                                   fy: (body["fy"] as? Double) ?? 0.5,
                                   label: (body["label"] as? String) ?? "this"))
        case "resolve":
            guard let id = body["id"] as? String else { return nil }
            self = .resolve(id)
        case "reply":
            guard let id = body["id"] as? String, let text = body["text"] as? String,
                  !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            self = .reply(id, text)
        case "missing":
            guard let ids = body["ids"] as? [String], !ids.isEmpty else { return nil }
            self = .missing(ids)
        default:
            return nil
        }
    }
}

/// Each person's mark: their first letter in their own colour (Caleb: "each
/// person gets their own letter"). Two names that start the same get two
/// letters, so Sam and Shirley read as "Sa" and "Sh".
enum PersonMark {
    private static let palette: [(String, Color)] = [
        ("#0A7CFF", Color(red: 10 / 255, green: 124 / 255, blue: 1)),
        ("#1FA463", Color(red: 31 / 255, green: 164 / 255, blue: 99 / 255)),
        ("#8E5CF7", Color(red: 142 / 255, green: 92 / 255, blue: 247 / 255)),
        ("#E5487F", Color(red: 229 / 255, green: 72 / 255, blue: 127 / 255)),
        ("#0FA3B1", Color(red: 15 / 255, green: 163 / 255, blue: 177 / 255)),
        ("#D14B2F", Color(red: 209 / 255, green: 75 / 255, blue: 47 / 255)),
    ]

    private static func index(_ name: String) -> Int {
        name.lowercased().unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0x7fffffff } % palette.count
    }

    static func hex(_ name: String) -> String { palette[index(name)].0 }
    static func color(_ name: String) -> Color { palette[index(name)].1 }

    static func letter(_ name: String, among names: Set<String>) -> String {
        let first = name.prefix(1).uppercased()
        let clash = names.contains { $0 != name && $0.prefix(1).uppercased() == first }
        return clash ? String(name.prefix(2)).capitalized : first
    }
}

/// Holds the web view's message handler weakly; WebKit keeps a strong
/// reference to whatever is registered, which would otherwise never go away.
final class WeakPinHandler: NSObject, WKScriptMessageHandler {
    weak var target: WKScriptMessageHandler?
    init(_ target: WKScriptMessageHandler) { self.target = target }
    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Runs inside the app's own sandboxed frame in the preview only; the site in
/// Safari never gets it (Caleb: "only in preview, the site is supposed to be
/// fully functional"). Styles go through the CSSOM because the frame's CSP
/// refuses style elements and style attributes.
enum PinScript {
    static let source = #"""
    (function () {
      if (window.__amberPinsReady) return;
      // The runner page only hosts the app's frame; pins belong inside it.
      if (window.top === window && document.querySelector('iframe')) return;
      window.__amberPinsReady = true;
      var post = function (m) { try { window.webkit.messageHandlers.amber.postMessage(m); } catch (e) {} };
      document.documentElement.style.touchAction = 'manipulation';
      var layer = document.createElement('div');
      Object.assign(layer.style, { position: 'absolute', left: '0', top: '0', width: '0', height: '0', zIndex: '2147483646' });
      document.body.appendChild(layer);

      function selectorFor(el) {
        if (el.id) return '#' + CSS.escape(el.id);
        var parts = [];
        while (el && el.nodeType === 1 && el !== document.body && el !== document.documentElement) {
          var i = 1, sib = el;
          while ((sib = sib.previousElementSibling)) if (sib.tagName === el.tagName) i++;
          parts.unshift(el.tagName.toLowerCase() + ':nth-of-type(' + i + ')');
          el = el.parentElement;
          if (el && el.id) { parts.unshift('#' + CSS.escape(el.id)); return parts.join(' > '); }
        }
        return 'body > ' + parts.join(' > ');
      }
      function labelFor(el) {
        var t = (el.innerText || el.getAttribute('aria-label') || el.getAttribute('placeholder') || el.getAttribute('alt') || '').trim().replace(/\s+/g, ' ');
        var kinds = { button: 'button', a: 'link', img: 'image', input: 'box', textarea: 'box', select: 'menu', h1: 'heading', h2: 'heading', h3: 'heading', p: 'text', li: 'item', label: 'label' };
        var kind = kinds[el.tagName.toLowerCase()] || 'section';
        return t ? '“' + t.slice(0, 40) + (t.length > 40 ? '…' : '') + '” ' + kind : 'this ' + kind;
      }
      function blob(x, y, color, letter) {
        var b = document.createElement('div');
        Object.assign(b.style, {
          position: 'absolute', left: (x - 15) + 'px', top: (y - 15) + 'px', width: '30px', height: '30px',
          borderRadius: '50% 50% 50% 6px', display: 'flex', alignItems: 'center', justifyContent: 'center',
          font: '700 13px -apple-system, system-ui', color: color, background: color + '40',
          border: '2px solid ' + color, backdropFilter: 'blur(6px)', webkitBackdropFilter: 'blur(6px)',
          boxShadow: '0 2px 10px rgba(0,0,0,.18)', cursor: 'pointer', boxSizing: 'border-box'
        });
        b.textContent = letter;
        return b;
      }

      var ghost = null;
      function drop(x, y) {
        var el = document.elementFromPoint(x, y);
        if (!el || layer.contains(el)) return;
        var r = el.getBoundingClientRect();
        if (ghost) ghost.remove();
        ghost = blob(x + window.scrollX, y + window.scrollY, '#E8820C', '+');
        layer.appendChild(ghost);
        post({ kind: 'pin', selector: selectorFor(el), fx: (x - r.left) / Math.max(1, r.width), fy: (y - r.top) / Math.max(1, r.height), label: labelFor(el) });
      }
      // A double tap drops a pin; a single tap still does whatever the app does.
      var last = 0, lx = 0, ly = 0;
      document.addEventListener('touchend', function (e) {
        var t = e.changedTouches[0], now = Date.now();
        if (now - last < 320 && Math.abs(t.clientX - lx) < 30 && Math.abs(t.clientY - ly) < 30) {
          e.preventDefault(); last = 0; drop(t.clientX, t.clientY);
        } else { last = now; lx = t.clientX; ly = t.clientY; }
      }, { capture: true, passive: false });
      document.addEventListener('dblclick', function (e) { e.preventDefault(); drop(e.clientX, e.clientY); }, true);

      var pins = [], open = null, shown = [], misses = {}, reported = {}, setAt = 0;
      function place() {
        var missing = [];
        shown.forEach(function (s) {
          var el = null;
          try { el = document.querySelector(s.pin.selector); } catch (e) {}
          var r = el && el.getBoundingClientRect();
          if (!el || (!r.width && !r.height)) {
            s.node.style.display = 'none'; if (s.card) s.card.style.display = 'none';
            misses[s.pin.id] = (misses[s.pin.id] || 0) + 1;
            // Only after the app has had time to draw, and gone five checks
            // running: an app still loading its list is not a deleted element.
            if (misses[s.pin.id] >= 5 && Date.now() - setAt > 5000 && !reported[s.pin.id]) { reported[s.pin.id] = 1; missing.push(s.pin.id); }
            return;
          }
          misses[s.pin.id] = 0;
          var x = r.left + window.scrollX + s.pin.fx * r.width, y = r.top + window.scrollY + s.pin.fy * r.height;
          s.node.style.display = 'flex'; s.node.style.left = (x - 15) + 'px'; s.node.style.top = (y - 15) + 'px';
          if (s.card) {
            s.card.style.display = 'block';
            var w = Math.min(250, document.documentElement.clientWidth - 24);
            s.card.style.width = w + 'px';
            s.card.style.left = Math.max(12, Math.min(x + 20, window.scrollX + document.documentElement.clientWidth - w - 12)) + 'px';
            s.card.style.top = (y + 18) + 'px';
          }
        });
        if (missing.length) post({ kind: 'missing', ids: missing });
      }
      function card(pin) {
        var c = document.createElement('div');
        Object.assign(c.style, { position: 'absolute', zIndex: '2147483647', background: '#fff', borderRadius: '14px', boxShadow: '0 8px 30px rgba(0,0,0,.2)', padding: '12px', font: '15px -apple-system, system-ui', color: '#171717', boxSizing: 'border-box' });
        c.addEventListener('click', function (e) { e.stopPropagation(); });
        c.addEventListener('touchend', function (e) { e.stopPropagation(); }, true);
        function line(name, text, small) {
          var d = document.createElement('div'); d.style.marginBottom = '8px';
          var n = document.createElement('div'); n.textContent = name; Object.assign(n.style, { font: '700 13px -apple-system, system-ui', color: '#666' });
          var t = document.createElement('div'); t.textContent = text; t.style.fontSize = small ? '14px' : '15px';
          d.appendChild(n); d.appendChild(t); return d;
        }
        c.appendChild(line(pin.name, pin.text));
        pin.replies.forEach(function (r) { var l = line(r.name, r.text, true); l.style.paddingLeft = '10px'; l.style.borderLeft = '2px solid #ebebeb'; c.appendChild(l); });
        var row = document.createElement('div'); Object.assign(row.style, { display: 'flex', gap: '8px', marginTop: '4px' });
        var input = document.createElement('input'); input.placeholder = 'Reply';
        Object.assign(input.style, { flex: '1', minWidth: '0', font: '15px -apple-system, system-ui', padding: '8px 10px', borderRadius: '10px', border: '1px solid #ebebeb', outline: 'none' });
        input.addEventListener('keydown', function (e) { if (e.key === 'Enter' && input.value.trim()) { post({ kind: 'reply', id: pin.id, text: input.value.trim() }); input.value = ''; input.blur(); } });
        var done = document.createElement('button'); done.textContent = 'Resolve';
        Object.assign(done.style, { font: '700 14px -apple-system, system-ui', color: '#fff', background: '#171717', border: '0', borderRadius: '999px', padding: '8px 12px' });
        done.addEventListener('click', function () { post({ kind: 'resolve', id: pin.id }); });
        row.appendChild(input); row.appendChild(done); c.appendChild(row);
        return c;
      }
      function build() {
        layer.innerHTML = ''; shown = [];
        if (ghost) { ghost.remove(); ghost = null; }
        pins.forEach(function (pin) {
          var node = blob(0, 0, pin.color, pin.letter);
          node.addEventListener('click', function (e) { e.stopPropagation(); open = open === pin.id ? null : pin.id; build(); });
          node.addEventListener('touchend', function (e) { e.stopPropagation(); }, true);
          layer.appendChild(node);
          var entry = { pin: pin, node: node, card: null };
          if (open === pin.id) { entry.card = card(pin); layer.appendChild(entry.card); }
          shown.push(entry);
        });
        place();
      }
      window.__amberSetPins = function (list) {
        pins = list || []; setAt = Date.now();
        if (open && !pins.some(function (p) { return p.id === open; })) open = null;
        build();
      };
      document.addEventListener('click', function () { if (open) { open = null; build(); } });
      window.addEventListener('resize', place);
      setInterval(place, 1000);
      post({ kind: 'ready' });
    })();
    """#
}
