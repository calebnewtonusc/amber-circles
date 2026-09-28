-- Amber Circles schema. Runs on every boot, so every statement is idempotent.
--
-- Identity is by link, the way a Google Doc invite works: every circle member
-- gets a personal token, and opening their link is signing in. Owners hold a
-- separate key that can publish and manage. Tokens are stored hashed, so a
-- leaked database does not leak anyone's access.

create table if not exists owners (
  id          text primary key,
  name        text not null,
  key_hash    text not null unique,
  created_at  timestamptz not null default now()
);

create table if not exists circles (
  id          text primary key,
  owner_id    text not null references owners(id) on delete cascade,
  name        text not null,
  created_at  timestamptz not null default now()
);

create table if not exists members (
  id          text primary key,
  circle_id   text not null references circles(id) on delete cascade,
  name        text not null,
  phone       text,
  is_owner    boolean not null default false,
  token_hash  text not null unique,
  token_hint  text not null,
  created_at  timestamptz not null default now()
);
create index if not exists members_circle_id_idx on members(circle_id);

-- The raw member token is kept only so the owner can re-share a link they
-- already sent, which is the whole share sheet. It is encrypted at rest with
-- a server secret rather than stored plain.
alter table members add column if not exists token_sealed text;

create table if not exists tools (
  id           text primary key,
  slug         text not null unique,
  owner_id     text not null references owners(id) on delete cascade,
  circle_id    text not null references circles(id) on delete cascade,
  title        text not null,
  description  text not null default '',
  html         text not null,
  version      integer not null default 1,
  created_at   timestamptz not null default now(),
  updated_at   timestamptz not null default now()
);
create index if not exists tools_owner_id_idx on tools(owner_id);

create table if not exists records (
  id          text primary key,
  tool_id     text not null references tools(id) on delete cascade,
  collection  text not null,
  data        jsonb not null,
  author_id   text references members(id) on delete set null,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);
create index if not exists records_tool_collection_idx on records(tool_id, collection);

-- Every open is logged, because "who actually used it" is the number the
-- judges ask for and the one nobody can fake after the fact.
create table if not exists opens (
  id          bigserial primary key,
  tool_id     text not null references tools(id) on delete cascade,
  member_id   text not null references members(id) on delete cascade,
  at          timestamptz not null default now()
);
create index if not exists opens_tool_id_idx on opens(tool_id);

-- Every change to a tool keeps the version before it, so "go back" always
-- works. Docs taught people that nothing they do is permanent; a tool that
-- one bad edit can break with no undo teaches the opposite.
create table if not exists tool_versions (
  id          bigserial primary key,
  tool_id     text not null references tools(id) on delete cascade,
  version     integer not null,
  html        text not null,
  request     text not null default '',
  created_at  timestamptz not null default now(),
  unique (tool_id, version)
);
alter table tools add column if not exists request text not null default '';

-- Presence: the last time each member had the tool open, refreshed by the
-- runner's poll. "Here now" is anyone seen in the last two minutes.
alter table members add column if not exists last_seen timestamptz;

-- Someone opens a tool they were not given, and asks. The owner lets them in
-- with one tap, which is the Google Docs flow nobody else in this category has.
create table if not exists access_requests (
  id          text primary key,
  tool_id     text not null references tools(id) on delete cascade,
  name        text not null,
  phone       text,
  note        text not null default '',
  status      text not null default 'pending',
  created_at  timestamptz not null default now()
);
create index if not exists access_requests_tool_idx on access_requests(tool_id, status);

-- Try before it counts. A change Claude makes lands here first, the owner sees
-- it working on the real data, and only "Keep this" swaps it in. Replit and
-- Lovable users describe the opposite: each fix going live and breaking what
-- worked (research/vibe-coding-vs-docs.md, pain 1).
alter table tools add column if not exists draft_html text;
alter table tools add column if not exists draft_request text;

-- The entries as they stood when each version went live, so going back can
-- bring the data back too. Replit's rollbacks leave the database alone by
-- default, and its agent deleted SaaStr's production data
-- (research/vibe-coding-vs-docs.md, pain 4). Null when the snapshot would
-- have been too large to keep.
alter table tool_versions add column if not exists data_snapshot jsonb;

-- Presence is per tool. Tracking it per member made the tool page say Harold
-- was using the attendance tracker while he was on the prayer list, next to
-- "Not opened yet: Harold" (render review, 2026-09-27).
create table if not exists presence (
  tool_id    text not null references tools(id) on delete cascade,
  member_id  text not null references members(id) on delete cascade,
  last_seen  timestamptz not null default now(),
  primary key (tool_id, member_id)
);

-- A group chat is a circle. The iMessage app creates one the first time
-- someone builds in a thread, and everyone who taps the bubble joins it with
-- the invite the bubble carries. In a chat there is no single owner: anyone
-- in the thread can make and change things, the way anyone with edit access
-- can in a shared Drive folder.
alter table circles add column if not exists chat_invite_hash text;
-- The iMessage participant id for this person in this thread, so tapping the
-- bubble twice finds the same member instead of making a second one.
alter table members add column if not exists participant text;
create unique index if not exists members_participant_idx
  on members(circle_id, participant) where participant is not null;
alter table tools add column if not exists made_by text;
alter table tools add column if not exists explain_text text;
alter table tools add column if not exists explain_version int;

-- Thoughts people leave on a tool, like comments on a Doc: nobody gets a text
-- for each one, they wait inside the tool until someone turns them into a
-- change.
create table if not exists tool_notes (
  id          text primary key,
  tool_id     text not null references tools(id) on delete cascade,
  member_id   text references members(id) on delete set null,
  text        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists tool_notes_tool_idx on tool_notes(tool_id, created_at);

-- The conversation with each tool, kept. Chewbacca's voice is "connected to
-- the brain both ways" (docs/VOICE-DESIGN.md): every turn is logged and read
-- back into the next, so Amber knows what Ruth asked for yesterday when Stan
-- opens it today.
create table if not exists tool_talk (
  id          text primary key,
  tool_id     text not null references tools(id) on delete cascade,
  member_id   text references members(id) on delete set null,
  role        text not null,
  text        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists tool_talk_tool_idx on tool_talk(tool_id, created_at);

-- The group chat's agent (agent.js). Every turn anyone has with it, across
-- every tool, is its transcript; chat_memories is its memory, one fact per
-- row in Chewbacca's shape, with Amber's modality as a column.
create table if not exists chat_turns (
  id          text primary key,
  circle_id   text not null references circles(id) on delete cascade,
  tool_slug   text,
  member_id   text references members(id) on delete set null,
  role        text not null,
  text        text not null,
  created_at  timestamptz not null default now()
);
create index if not exists chat_turns_circle_idx on chat_turns(circle_id, created_at);

create table if not exists chat_memories (
  id           text primary key,
  circle_id    text not null references circles(id) on delete cascade,
  name         text not null,
  description  text not null,
  body         text not null,
  modality     text not null default 'fact',
  member_id    text references members(id) on delete set null,
  updated_at   timestamptz not null default now(),
  unique (circle_id, name)
);

-- From mem0 (mem0/memory/main.py, ADDITIVE_EXTRACTION_PROMPT): a changed fact
-- is recorded as a transition, and the old version is kept rather than
-- overwritten. who said it and who it is about are different people.
alter table chat_memories add column if not exists about text;
create table if not exists chat_memory_history (
  id          text primary key,
  circle_id   text not null references circles(id) on delete cascade,
  name        text not null,
  old_body    text not null,
  old_modality text not null,
  new_body    text not null,
  member_id   text references members(id) on delete set null,
  at          timestamptz not null default now()
);

-- A plan read back and waiting for a yes. make_tool is refused without one
-- (agent.js), because asking cannot be left to the model.
create table if not exists chat_plans (
  circle_id  text primary key references circles(id) on delete cascade,
  plan       text not null,
  request    text not null,
  at         timestamptz not null default now()
);

-- When each person last looked at each tool, so opening it can say what
-- happened since (Caleb: "when you open the app sent by someone else the
-- agent should update you on what's happened").
create table if not exists tool_seen (
  member_id  text not null references members(id) on delete cascade,
  tool_id    text not null references tools(id) on delete cascade,
  at         timestamptz not null default now(),
  primary key (member_id, tool_id)
);
