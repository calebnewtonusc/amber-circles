// The in-app builder: a person describes a tool in plain words and Claude
// writes it. This exists because the first version needed a connector URL
// pasted into Claude's settings, and the person this is for, Caleb's
// grandfather, is never going to do that. Nothing here asks him to.
import Anthropic from "@anthropic-ai/sdk";

const MODEL = process.env.AMBER_BUILD_MODEL || "claude-opus-5";

// Guessed, never measured under load: a finished attendance tracker with
// states and styling runs about 9k tokens, so 32k leaves room for a larger
// tool without letting a runaway generation bill for 128k.
const MAX_OUTPUT_TOKENS = 32000;

export const BRIDGE_GUIDE = `The tool runs in a sandbox inside Amber with NO network access: fetch, XHR and WebSockets are blocked, and images may only be data: or blob: URLs. Everything it needs comes from the global \`amber\` object, which already exists before your script runs:

  await amber.me()                         -> { id, name, isOwner }   the person looking at it right now
  await amber.circle()                     -> { name, owner }         the group it is shared with
  await amber.people()                     -> [{ id, name, isOwner }] everyone in the group
  await amber.list(collection)             -> [{ id, data, author: { id, name }, createdAt, updatedAt }] oldest first
  await amber.add(collection, data)        -> { id }   saved for the whole group
  await amber.update(collection, id, data) -> { id }   merges data into the record
  await amber.remove(collection, id)
  amber.reachOut(memberId, message)        opens a text message to that person; only works for the owner
  amber.onChange(callback)                 fires when someone else in the group changed something; reload and redraw

Collection names are short lowercase words like "prayers" or "rides". Every call returns a promise that can reject with an Error whose message is written for people; show it. Scripts may load from cdn.jsdelivr.net or unpkg.com, fonts from Google Fonts.`;

const SYSTEM = `You build small tools for small groups of people: a Bible class, a club, a family, a potluck. The person asking is often not technical and may be in their seventies. The people using the tool open it from a text message on their phone.

${BRIDGE_GUIDE}

Write ONE complete HTML file. Rules that matter more than anything else:

Reading and tapping
- Body text at least 18px, headings larger, line height 1.5. High contrast: near-black text on a warm off-white page.
- Every button and tappable row at least 48px tall with generous spacing between them. Labels are words, never icons alone.
- Plain words. Say "Add a prayer", never "Create entry". No jargon, no abbreviations, no emojis, no em dashes.
- Build for a 390px wide phone first; it must also look right on a laptop.

Behaviour
- Show a loading state while amber calls are in flight, a friendly empty state that says what to do first, and an error state with a "Try again" button.
- After someone adds or changes something, confirm it in plain words ("Saved. Everyone in the class can see it now.").
- Anything only the owner should do (delete other people's entries, reset, close a sign-up), hide unless (await amber.me()).isOwner.
- Use the group's real names from amber.people() wherever a person appears. Never ask someone to type their own name; you already know it from amber.me().
- Call amber.onChange to redraw when someone else changes data.
- Deleting asks for confirmation first. People can only remove entries they added themselves (compare author.id with amber.me().id); the owner can remove any. Only show a Remove button where it will work.

Look: make it feel like a polished app, not a form. The bar is something a person shows their friends.
- Type: "Geist" from Google Fonts, weights 400, 500 and 600 only. A real header: the app name large (30 to 36px, weight 600, letter-spacing -0.02em) with one short line under it in #666666.
- Color: page #fafafa, cards #ffffff. Pick ONE accent that fits the vibe they asked for and the group (warm amber #f59e0b for friendly, calm blue #2563eb for simple, green #16a34a for church or outdoors, violet #7c3aed for fun) and use it only for the main button, selected states and small highlights. Everything else is ink #171717 and greys.
- Surfaces: cards with 16px corners, a 1px #ebebeb border and a soft shadow (0 1px 2px rgba(0,0,0,0.04), 0 8px 24px rgba(0,0,0,0.04)). Generous spacing: 20px padding inside cards, 16px between them.
- Icons: small inline SVG icons (Lucide style, 1.75 stroke, 18 to 20px) next to headings and on buttons, drawn inline in the file. Never emojis.
- Lists: each entry as a row or card with the person's initials in a small colored circle, their name, and the detail; the newest at the top with a gentle fade-in when added.
- Buttons: pill shaped. The main action is solid accent with white text, 48px tall; others are white with a 1px #ebebeb border. A pressed state (scale 0.98) and a hover state.
- Motion: 150 to 250ms ease-out transitions on hover, on items appearing and on tabs; nothing bounces or loops.
- Empty state: a friendly line with a small inline SVG illustration or icon, and the first action right there.
- No gradients except a very subtle one in the header background if it suits the vibe, no heavy shadows, no italics, no uppercase labels.

Reply with the HTML file only, inside one \`\`\`html code block, and nothing after it.`;

let client = null;
function anthropic() {
  if (!process.env.ANTHROPIC_API_KEY) {
    throw Object.assign(new Error("The builder is not switched on here yet."), {
      status: 503,
    });
  }
  client ??= new Anthropic();
  return client;
}

export function extractHtml(text) {
  const fenced =
    text.match(/```html\s*([\s\S]*?)```/i) ||
    text.match(/```html\s*([\s\S]*)$/i);
  const html = (fenced ? fenced[1] : text).trim();
  if (!/<(html|body|script|div|main)\b/i.test(html) || html.length < 200) {
    throw Object.assign(
      new Error(
        "Claude did not send back a working tool that time. Try again, or say it a different way.",
      ),
      { status: 502 },
    );
  }
  if (!/<\/html>\s*$/i.test(html) && /<html/i.test(html)) {
    throw Object.assign(
      new Error(
        "The tool came back cut off before the end. Try again with a shorter request.",
      ),
      { status: 502 },
    );
  }
  return html;
}

// A title for the tool, taken from what the person asked for rather than a
// second model call: "a prayer list for my Monday class" -> "Prayer List".
export function titleFrom(request) {
  const firstSentence = String(request).split(/[.:!?\n]/)[0];
  const cleaned = firstSentence
    .replace(/^(please\s+)?(make|build|create|i need|i want|can you make|could you make)\s+(me\s+|us\s+)?/i, "")
    .replace(/^(a|an|the|our|my)\s+/i, "")
    .split(/\s+(for|so|that|where|which|with)\s+/i)[0]
    .replace(/[^\w\s'-]/g, "")
    .trim()
    .split(/\s+/)
    .slice(0, 5)
    .join(" ");
  const title = cleaned || "New tool";
  return title.charAt(0).toUpperCase() + title.slice(1);
}

// Streams one build. onProgress receives { stage, chars } so the page can
// show real progress: a two-minute blank wait reads as broken, and the person
// this is for will assume they did something wrong.
export async function build({
  request,
  circleName,
  people,
  currentHtml,
  onProgress,
}) {
  const context = [
    `The group is called "${circleName}". The people in it: ${people.join(", ")}.`,
    currentHtml
      ? `Here is the tool as it is now. Change it as asked, keep everything else working the same, keep the same collection names so saved data still shows up, and send back the whole file.\n\n\`\`\`html\n${currentHtml}\n\`\`\`\n\nWhat to change: ${request}`
      : `What they asked for, in their words: ${request}`,
  ].join("\n\n");

  const stream = anthropic().beta.messages.stream({
    model: MODEL,
    max_tokens: MAX_OUTPUT_TOKENS,
    thinking: { type: "adaptive" },
    output_config: { effort: "medium" },
    betas: ["server-side-fallback-2026-07-01"],
    fallbacks: "default",
    system: SYSTEM,
    messages: [{ role: "user", content: context }],
  });

  let text = "";
  let lastReport = 0;
  onProgress?.({ stage: "thinking", chars: 0 });
  for await (const event of stream) {
    if (
      event.type === "content_block_delta" &&
      event.delta.type === "text_delta"
    ) {
      text += event.delta.text;
      if (text.length - lastReport > 400) {
        lastReport = text.length;
        // The half-written page goes along too, so the phone can show the
        // interface appearing as it is written, and say what is being added.
        const partial = text.includes("```html") ? text.slice(text.indexOf("```html") + 7) : "";
        onProgress?.({ stage: "writing", chars: text.length, html: partial.slice(0, 120000), doing: narrate(partial) });
      }
    }
  }
  const message = await stream.finalMessage();
  if (message.stop_reason === "refusal") {
    throw Object.assign(
      new Error(
        "Claude would not build that one. Try describing it differently.",
      ),
      { status: 422 },
    );
  }
  if (message.stop_reason === "max_tokens") {
    throw Object.assign(
      new Error(
        "That tool came out too long to finish. Try asking for a simpler version first, then add to it.",
      ),
      { status: 502 },
    );
  }
  onProgress?.({ stage: "checking", chars: text.length });
  return { html: extractHtml(text), usage: message.usage };
}

// Two or three sentences a person in their seventies can read before they
// ever open the tool: what it is for, and the first thing to tap. Haiku,
// because this is a summary of a file already written, not a build.
export async function explain({ title, html }) {
  const message = await anthropic().messages.create({
    model: "claude-haiku-4-5",
    max_tokens: 300,
    system:
      "You explain a small tool to someone who did not make it and may be in their seventies. Write two or three short sentences in plain words: what it is for, then the first thing to tap. No jargon, no code words, no emojis, no em dashes. Reply with the sentences only.",
    messages: [
      {
        role: "user",
        content: `The tool is called "${title}". Here is its file:\n\n${String(html).slice(0, 60000)}`,
      },
    ],
  });
  return message.content
    .filter((block) => block.type === "text")
    .map((block) => block.text)
    .join("")
    .trim();
}

// One box, two jobs, the way you talk to a person: "how does it know who
// added what?" gets an answer, "make the names bigger" gets a change.
// Caleb, 2026-09-27: "you ask some questions and you're like, oh, how does it
// do that?" Haiku reads the tool and decides.
export async function talk({ title, html, text, notes = [], memory = [], speaker = "" }) {
  const message = await anthropic().messages.create({
    model: "claude-haiku-4-5",
    max_tokens: 400,
    system:
      'You are Amber, talking with someone about a small tool their group chat uses. They may be in their seventies. Decide what they want. INCOMPLETE: the words stop mid-thought ("make the button", "can you add a") because they let go of the talk button early; never build half an idea (pipecat user turn completion, turns/user_turn_completion_mixin.py). CHANGE: they want the tool to be different now. COMMENT: they are leaving a thought or feedback for the group to decide on later ("leave a note", "someone should", "I think it would be nice if"). QUESTION: anything else. Reply with JSON only: {"kind":"incomplete","reply":"Go ahead, I\'m listening."} or {"kind":"change","request":"<their change, restated as one clear instruction>","reply":"<one short friendly sentence saying you are on it>"} or {"kind":"comment","note":"<their thought, cleaned up in their own words>","reply":"<one short sentence saying you saved it for the chat>"} or {"kind":"answer","reply":"<two or three plain sentences answering them from the file, and if it helps, suggest opening it in Safari to see>"}. No jargon, no code words, no emojis, no em dashes.\n\nYou are heard, not read (rules from Chewbacca docs/VOICE-DESIGN.md): at most three short sentences. A change is acknowledged with "On it." plus the detail only when a mishearing would go somewhere wrong, never "Okay" or "Yes". Use the conversation so far: if someone else asked for something, you may say so by name. Lines in [brackets] are what actually happened: [Kept: ...] is live for everyone, [Declined: ...] was tried and put back. Anything people only asked for is a wish, not done: never say something is done unless it was Kept. If you are not sure what they mean, ask one short question, one at a time, because a list of questions is hard to hold in your head by ear. If it is still unclear after two tries, offer one concrete choice ("Bigger writing, or a different color?"), because choosing is easier than describing (AWS voice agent studio, prompt_best_practices/claude/SKILL.md).',
    messages: [
      {
        role: "user",
        content: `Tool: "${title}"\nSpeaking now: ${speaker || "someone in the chat"}\n${memory.length ? `The conversation so far, oldest first:\n${memory.join("\n")}\n` : ""}${notes.length ? `Thoughts people left: ${notes.join(" | ")}\n` : ""}File:\n${String(html).slice(0, 50000)}\n\nThey said: "${text}"`,
      },
    ],
  });
  const raw = message.content.filter((b) => b.type === "text").map((b) => b.text).join("");
  try {
    const parsed = JSON.parse(raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1));
    if (parsed.kind === "change" && parsed.request) return parsed;
    if (parsed.kind === "comment" && parsed.note) return parsed;
    if (parsed.kind === "incomplete") return { kind: "incomplete", reply: parsed.reply || "Go ahead, I'm listening." };
    if (parsed.reply) return { kind: "answer", reply: parsed.reply };
  } catch {
    /* fall through: treat it as a change, which is the safe, reversible reading */
  }
  return { kind: "change", request: text, reply: "On it." };
}

// After a change is written, say what is different, the way a person would
// before asking you to look: "Here is what changed. Try it and tell me."
export async function describeChange({ before, after, request }) {
  const message = await anthropic().messages.create({
    model: "claude-haiku-4-5",
    max_tokens: 250,
    system:
      "Compare two versions of a small tool and tell someone who is not technical what changed, in two or three short sentences, ending by asking them to try it. Plain words, no code words, no emojis, no em dashes.",
    messages: [
      {
        role: "user",
        content: `They asked: "${request}"\n\nBEFORE:\n${String(before).slice(0, 30000)}\n\nAFTER:\n${String(after).slice(0, 30000)}`,
      },
    ],
  });
  return message.content.filter((b) => b.type === "text").map((b) => b.text).join("").trim();
}

// What the builder is adding right now, in words a person would use, from
// the newest heading, button or field in the half-written page.
export function narrate(html) {
  const found = [
    ...html.matchAll(/<(h1|h2|h3|button|label)[^>]*>([^<]{2,60})</gi),
    ...html.matchAll(/placeholder="([^"]{2,60})"/gi),
  ].sort((a, b) => a.index - b.index);
  const last = found.at(-1);
  if (!last) return html.includes("<style") && !html.includes("<body") ? "Choosing the look" : "Setting up the page";
  if (last.length === 2) return `Adding a box for "${last[1].trim()}"`;
  const [, tag, words] = last;
  const clean = words.trim().replace(/\s+/g, " ");
  if (/^h/i.test(tag)) return `Adding the "${clean}" section`;
  if (/^button$/i.test(tag)) return `Adding the "${clean}" button`;
  return `Adding "${clean}"`;
}

// A change as a patch, not a rewrite. Rewriting the whole page for "make the
// names bigger" took about a minute and could move things nobody asked about;
// Bob-the-Builder's rule is to patch one thing and leave the rest alone
// (projects/bob-the-builder README, "Bob edits a patch"). Each edit must match
// the current page exactly once, or the whole patch is refused and the caller
// falls back to a full rebuild.
export async function patch({ request, currentHtml, circleName }) {
  const message = await anthropic().messages.create({
    model: "claude-sonnet-5",
    max_tokens: 6000,
    system:
      'You change one small web tool by returning exact text edits. Reply with JSON only: {"edits":[{"find":"<exact text copied from the file, long enough to appear only once>","replace":"<the new text>"}]}. Change only what was asked, keep collection names and everything else identical. If the request needs a large restructure, reply {"edits":[],"rebuild":true}.',
    messages: [
      {
        role: "user",
        content: `Group: ${circleName}\n\nThe file:\n\`\`\`html\n${currentHtml}\n\`\`\`\n\nWhat to change: ${request}`,
      },
    ],
  });
  const raw = message.content.filter((b) => b.type === "text").map((b) => b.text).join("");
  let parsed;
  try {
    parsed = JSON.parse(raw.slice(raw.indexOf("{"), raw.lastIndexOf("}") + 1));
  } catch {
    return null;
  }
  if (parsed.rebuild || !Array.isArray(parsed.edits) || !parsed.edits.length) return null;
  let html = currentHtml;
  for (const edit of parsed.edits) {
    if (typeof edit.find !== "string" || typeof edit.replace !== "string" || !edit.find) return null;
    if (html.split(edit.find).length !== 2) return null;
    html = html.replace(edit.find, () => edit.replace);
  }
  return { html, edits: parsed.edits.length, usage: message.usage };
}
