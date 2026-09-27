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
