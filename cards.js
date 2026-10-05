// Group cards: the shapes a card and an answer may take. Everything a client
// sends is rebuilt from these whitelists, so a field nobody planned for (a
// phone number, an email, a token) cannot be stored by accident or on purpose.

export const CARD_KINDS = ["free", "split", "pick", "who", "remind"];

/** Half-hour slots per day, 9am to 10pm. Mirrored in the app (Together.swift). */
export const SLOTS_PER_DAY = 26;

const isInt = (v, min, max) => Number.isInteger(v) && v >= min && v <= max;
const text = (v, max) => (typeof v === "string" && v.trim() && v.length <= max ? v.trim() : null);
const DAY = /^\d{4}-\d{2}-\d{2}$/;
const HANDLE = /^[A-Za-z0-9_-]{1,40}$/;

export class CardError extends Error {}
const bad = (message) => {
  throw new CardError(message);
};

export function cleanSpec(kind, raw) {
  const s = raw && typeof raw === "object" ? raw : {};
  switch (kind) {
    case "free": {
      const days = Array.isArray(s.days) ? s.days.filter((d) => typeof d === "string" && DAY.test(d)) : [];
      if (days.length < 1 || days.length > 5) bad("Pick between one and five days.");
      return { days: [...new Set(days)].sort() };
    }
    case "split": {
      if (!isInt(s.total, 1, 10_000_000)) bad("Enter the total in cents, above zero.");
      const tip = s.tip ?? 0;
      if (!isInt(tip, 0, 40)) bad("Tip must be between 0 and 40 percent.");
      const out = { total: s.total, tip };
      const what = text(s.what, 80);
      if (what) out.what = what;
      if (s.venmo != null && s.venmo !== "") {
        const handle = String(s.venmo).replace(/^@/, "");
        if (!HANDLE.test(handle)) bad("That Venmo handle has characters Venmo does not use.");
        out.venmo = handle;
      }
      return out;
    }
    case "pick": {
      const options = (Array.isArray(s.options) ? s.options : [])
        .map((o) => {
          const name = text(o?.name, 80);
          if (!name) return null;
          const opt = { name };
          const detail = text(o?.detail, 120);
          if (detail) opt.detail = detail;
          if (typeof o?.url === "string" && /^https:\/\/\S{1,290}$/.test(o.url)) opt.url = o.url;
          return opt;
        })
        .filter(Boolean);
      if (options.length < 2 || options.length > 12) bad("A vote needs between two and twelve options.");
      return { options };
    }
    case "who": {
      const question = text(s.question, 200);
      if (!question) bad("Say who you are looking for.");
      return { question };
    }
    case "remind": {
      const at = new Date(s.at);
      if (typeof s.at !== "string" || Number.isNaN(at.getTime())) bad("A reminder needs a time.");
      return { at: at.toISOString() };
    }
    default:
      bad("That kind of card does not exist.");
  }
}

export function cleanEntry(kind, spec, raw) {
  const d = raw && typeof raw === "object" ? raw : {};
  switch (kind) {
    case "free": {
      const max = spec.days.length * SLOTS_PER_DAY - 1;
      const slots = Array.isArray(d.slots) ? d.slots.filter((n) => isInt(n, 0, max)) : [];
      return { slots: [...new Set(slots)].sort((a, b) => a - b), amber: d.amber === true };
    }
    case "split":
      return { in: d.in !== false, paid: d.paid === true };
    case "pick":
      if (!isInt(d.vote, 0, spec.options.length - 1)) bad("Vote for one of the options.");
      return { vote: d.vote };
    case "who": {
      const people = (Array.isArray(d.people) ? d.people : [])
        .slice(0, 10)
        .map((p) => {
          const name = text(p?.name, 80);
          if (!name) return null;
          const about = text(p?.about, 120);
          return about ? { name, about } : { name };
        })
        .filter(Boolean);
      return { people, amber: d.amber === true };
    }
    case "remind":
      return { in: d.in !== false, saved: d.saved === true };
    default:
      bad("That kind of card does not exist.");
  }
}
