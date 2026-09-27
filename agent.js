// The group chat's agent. Caleb, 2026-09-27: "it should literally feel like
// I'm talking to an agent as smart as Chewbacca, and instead of living with
// access to the files on my computer it's living with access to all the
// software everyone in the gc is working on and all their conversation
// transcripts, and it builds memories just like Chewbacca does."
//
// So it is Chewbacca's shape, pointed at a group chat:
// - Its "files" are the chat's tools: their code, versions and comments.
// - Its transcript is every conversation anyone in the chat had with it.
// - Its memory is Chewbacca's auto-memory format (one fact per memory, a
//   name, a one-line description that loads every turn, a body read on
//   demand), plus Amber's modality column from chewbacca bin/people, because
//   "Ruth wants bigger text" and "bigger text is live" must never blur.
// - It writes memories as things happen, never in a batch at the end
//   (second-brain feedback_save_as_it_happens).
//
// Builds take a minute, so the agent does not wait for them: it hands the
// phone an action, the phone builds in the background, and the conversation
// keeps going (pipecat's async tools, async_tool_messages.py).
import Anthropic from "@anthropic-ai/sdk";

// Sonnet, not Opus: this is a spoken conversation, and a tool round on Opus
// costs seconds a person holding a phone can hear. Builds stay on Opus.
const MODEL = process.env.AMBER_AGENT_MODEL || "claude-sonnet-5";
// Guessed, never measured: enough rounds to read a tool, check memory and
// act, and few enough that a confused loop is cut off in seconds.
const MAX_ROUNDS = 6;

let client = null;
const anthropic = () => (client ??= new Anthropic());

const TOOLS = [
  {
    name: "list_tools",
    description:
      "Everything this group chat has made: slug, title, who made it, version, whether a change is waiting, how many entries and comments.",
    input_schema: { type: "object", properties: {} },
  },
  {
    name: "read_tool",
    description:
      "Read one tool before talking about it: its code, every kept version with what was asked, and its comments. Always read before answering a question about how a tool works or before changing it.",
    input_schema: {
      type: "object",
      properties: { slug: { type: "string" } },
      required: ["slug"],
    },
  },
  {
    name: "read_conversations",
    description:
      "Earlier conversations people in this chat had with you, oldest first. Use it when someone refers to something said before, or asks what someone else wanted.",
    input_schema: {
      type: "object",
      properties: {
        slug: {
          type: "string",
          description: "Only conversations about this tool. Omit for all.",
        },
        limit: { type: "integer" },
      },
    },
  },
  {
    name: "recall",
    description:
      "Read the full body of one memory by name. The index of every memory is already in your instructions.",
    input_schema: {
      type: "object",
      properties: { name: { type: "string" } },
      required: ["name"],
    },
  },
  {
    name: "remember",
    description:
      "Save or update one fact about this chat, its people or its tools, the moment you learn it: a preference, a decision, a wish, something done, something tried and rejected. One fact per memory. Reuse the same name to update rather than duplicate.",
    input_schema: {
      type: "object",
      properties: {
        name: { type: "string", description: "short-kebab-case slug" },
        description: {
          type: "string",
          description: "one line, used to decide relevance later",
        },
        body: {
          type: "string",
          description: "the fact, with who said it and when if known",
        },
        modality: {
          type: "string",
          enum: ["wish", "decided", "done", "declined", "fact"],
        },
      },
      required: ["name", "description", "body", "modality"],
    },
  },
  {
    name: "make_tool",
    description:
      "Start building a new tool for this chat. Takes about a minute and runs in the background; the conversation continues.",
    input_schema: {
      type: "object",
      properties: {
        request: {
          type: "string",
          description: "one clear description of what to build",
        },
      },
      required: ["request"],
    },
  },
  {
    name: "change_tool",
    description:
      "Start a change to an existing tool. It becomes a draft only this chat can try until someone keeps it. Takes about a minute in the background.",
    input_schema: {
      type: "object",
      properties: {
        slug: { type: "string" },
        request: { type: "string", description: "one clear instruction" },
      },
      required: ["slug", "request"],
    },
  },
  {
    name: "leave_comment",
    description:
      "Save a thought for the group to decide on later, under the speaker's name, on one tool.",
    input_schema: {
      type: "object",
      properties: { slug: { type: "string" }, text: { type: "string" } },
      required: ["slug", "text"],
    },
  },
  {
    name: "open_tool",
    description:
      "Open a tool in Safari for the person you are talking to, the draft if one is waiting.",
    input_schema: {
      type: "object",
      properties: { slug: { type: "string" } },
      required: ["slug"],
    },
  },
];

function system({ chatName, people, speaker, focus, memories, tools }) {
  const shelf = tools.length
    ? tools.map((t) => `- ${t.title} (slug ${t.slug}), made by ${t.made_by || "someone"}, version ${t.version}${t.has_draft ? ", a change is waiting to be kept" : ""}, ${t.entries} entries, ${t.notes} comments`).join("\n")
    : "(nothing made yet)";
  const index = memories.length
    ? memories
        .map((m) => `- [${m.modality}] ${m.name}: ${m.description}`)
        .join("\n")
    : "(nothing yet)";
  return `You are Amber, the builder that lives inside one group chat. You know everything this chat has made and everything its people have told you, and you remember it. Think of yourself as the friend in the chat who happens to build software.

The chat: ${chatName}. People in it: ${people.join(", ")}. You are talking with ${speaker} right now.${focus ? ` They are looking at the tool "${focus.title}" (slug ${focus.slug}).` : " They are on the list of everything the chat made."}

What this chat has made (already current, no need to list it):
${shelf}

What you remember (the index; recall a name to read its body):
${index}

How you work, and why:
- A question gets an answer, never an action. Only start a change or a build when someone asks for one in this very message. Lines in [brackets] in the conversation are things you already did: never start the same change twice.
- Read before you explain how a tool works (read_tool), because a group member may have changed it since you last looked, and the code is the truth.
- Remember as it happens, in the same turn: a preference ("Ruth can't read small text"), a decision, a wish, what was kept, what was put back. Waiting for later is how facts get lost. One fact per memory; update by reusing the name.
- Modality is not a style choice. [wish] is asked for and not done. [done] is live for everyone. [declined] was tried and put back. Never say something is done unless it is done: the people here will act on what you say.
- Changes and new tools run in the background for about a minute. Start them with change_tool or make_tool and keep talking; the phone tells everyone when it is ready. Changes land as a draft only this chat can try until someone taps Keep.
- A thought for the group to decide on later is a comment (leave_comment), not a change.
- If what they said stops mid-thought, they let go of the talk button early: say "Go ahead, I'm listening." and do nothing else.
- If you are not sure what they mean, ask one short question. After two unclear tries, offer one concrete choice ("Bigger writing, or a different color?").

You are heard, not read. The people here may be in their seventies:
- At most three short sentences. Plain words, no code words, no links, no lists, no emojis, no em dashes.
- Acknowledge a change with "On it." plus the detail only when mishearing it would go somewhere wrong. Never start with "Okay" or "Yes".
- Use people's names. If someone else asked for something, say so by name.
- When they should look at something, tell them to tap the link at the top to open it in Safari, then come back and tell you what they think.`;
}

/** One turn of the conversation. `db` supplies the chat's data. */
export async function converse({ db, chat, speaker, focusSlug, text }) {
  const [tools, memories, people] = await Promise.all([
    db.tools(),
    db.memories(),
    db.people(),
  ]);
  const focus = focusSlug
    ? tools.find((tool) => tool.slug === focusSlug)
    : null;
  const history = await db.recentTurns(12);
  const messages = [];
  for (const turn of history) {
    const role = turn.role === "amber" ? "assistant" : "user";
    const content =
      turn.role === "amber"
        ? turn.text
        : turn.role === "event"
          ? `[${turn.text}]`
          : `${turn.name || "Someone"}: ${turn.text}`;
    if (messages.length && messages.at(-1).role === role)
      messages.at(-1).content += `\n${content}`;
    else messages.push({ role, content });
  }
  if (messages.length && messages[0].role === "assistant") messages.shift();
  const said = `${speaker.name}: ${text}`;
  if (messages.length && messages.at(-1).role === "user")
    messages.at(-1).content += `\n${said}`;
  else messages.push({ role: "user", content: said });

  const actions = [];
  const run = {
    list_tools: async () =>
      tools.map(
        ({ slug, title, made_by, version, has_draft, entries, notes }) => ({
          slug,
          title,
          made_by,
          version,
          has_draft,
          entries,
          comments: notes,
        }),
      ),
    read_tool: async ({ slug }) => db.readTool(slug),
    read_conversations: async ({ slug, limit }) =>
      db.conversations(slug, Math.min(Number(limit) || 40, 80)),
    recall: async ({ name }) =>
      (await db.recall(name)) || { error: `No memory called ${name}.` },
    remember: async (memory) => {
      await db.remember({ ...memory, by: speaker.id });
      return { saved: memory.name };
    },
    make_tool: async ({ request }) => {
      actions.push({ type: "make", request });
      return {
        started: true,
        note: "Building in the background for about a minute.",
      };
    },
    change_tool: async ({ slug, request }) => {
      if (!tools.some((tool) => tool.slug === slug))
        return { error: `No tool ${slug} in this chat.` };
      actions.push({ type: "change", slug, request });
      return {
        started: true,
        note: "Building a draft in the background for about a minute.",
      };
    },
    leave_comment: async ({ slug, text: note }) => {
      await db.comment(slug, note, speaker.id);
      return { saved: true };
    },
    open_tool: async ({ slug }) => {
      actions.push({ type: "open", slug });
      return { opened: true };
    },
  };

  let reply = "";
  for (let round = 0; round < MAX_ROUNDS; round += 1) {
    const response = await anthropic().messages.create({
      model: MODEL,
      max_tokens: 1024,
      system: system({
        chatName: chat.name,
        people: people.map((p) => p.name),
        speaker: speaker.name,
        focus,
        memories,
        tools,
      }),
      tools: TOOLS,
      messages,
    });
    messages.push({ role: "assistant", content: response.content });
    const calls = response.content.filter((block) => block.type === "tool_use");
    reply =
      response.content
        .filter((block) => block.type === "text")
        .map((block) => block.text)
        .join(" ")
        .trim() || reply;
    if (response.stop_reason !== "tool_use" || !calls.length) break;
    const results = await Promise.all(
      calls.map(async (call) => {
        let output;
        try {
          output = await (
            run[call.name] || (async () => ({ error: "Unknown tool" }))
          )(call.input || {});
        } catch (error) {
          output = { error: error.message };
        }
        return {
          type: "tool_result",
          tool_use_id: call.id,
          content: JSON.stringify(output).slice(0, 60000),
        };
      }),
    );
    messages.push({ role: "user", content: results });
  }
  return { reply: reply || "Say that one more time for me?", actions };
}
