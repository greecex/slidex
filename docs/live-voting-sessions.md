# Live voting sessions

**Status**: Design and build plan. Decisions resolved 2026-06-11. Not yet implemented.
**Date**: 2026-06-11
**Owner**: Petros (taking over from Isaak).

This document specifies the next batch of work: turning a `Voting.Session` into something a presenter can run live in a room, with participants (logged in or guests) joining, voting, and seeing results in real time. It is written to be self-contained. A new session pointed at this file should be able to read it top to bottom and start building.

---

## 0. How to use this document

Read these first, in order, then come back here:
1. `CLAUDE.md` (root). Project summary, commands, code conventions, the "existing code predates these rules; new code follows them" policy. Note the style rules: no em dashes, sentence case headings, imperative commit titles under 52 characters, atomic commits.
2. `AGENTS.md` (root). Phoenix 1.8, Elixir, Ecto, LiveView, and HEEx conventions. Read before writing any UI, template, or LiveView code. Pay attention to the authentication section (router scopes and `live_session` blocks) and the Ecto rule that programmatic fields are set on the struct, not via `cast`.
3. `ARCHITECTURE.md` and `DESIGN.md`. Current architecture and domain model. They describe the present state; the features here are listed only as one-line bullets under ARCHITECTURE.md section 10.
4. `docs/testing-posture.md`. Pure functions first, doctests on public functions, minimal LiveView testing.

Working basics:
- Run the app: `mix phx.server` (or `iex -S mix phx.server`). Tests: `mix test`. Pre-push gate: `mix precommit`.
- Dev login: the only seeded account is `demo@example.com` (username `demo`), magic link only. Submit it on `/users/log-in`, then read the link from the local mailbox in IEx with `Swoosh.Adapters.Local.Storage.Memory.all()`, or visit `/dev/mailbox`. After login you land on `/polls`.
- Verify UI changes by driving the app, not just by reading code.

---

## 1. What we are building

Four features, one coherent experience:
1. **Presence**, including guest visitors. Show who is currently in a session.
2. **MC flow** (presenter / master of ceremonies). The presenter starts a session, advances through questions one at a time, and ends it.
3. **Vote tracking** plus an optional **live display of votes** (results).
4. A **join page** for a `Voting.Session`, with an optional **QR code** linking to it (use `{:qr_code, "~> 3.2"}`).

The target user story: an owner opens a session in present mode on the projector. The screen shows an access code, a join URL, and a QR code. People in the room scan or type the link, optionally enter a name, and land on a participant screen. The presenter advances to a question; everyone's screen shows it; people vote; the presenter (and optionally the participants) watch the tally update live. Presence shows how many people are connected. The presenter advances to the next question, and so on, then ends the session.

Note on surveys: a `Session` with `state: :survey` is self paced. It has no presenter advancing questions. It should share the participant and vote model, but skip the MC flow. Treat surveys as "all questions available at once, vote any time until closed."

---

## 2. Current state (what already exists to build on)

Database (six tables, via `priv/repo/migrations`): `users`, `users_tokens`, `polls`, `questions`, `options`, `sessions`. There is **no votes, responses, answers, or participants table**. There is no guest identity concept.

Relevant schema, `Slidex.Voting.Session` (`lib/slidex/voting/session.ex`):
- `slug` (a ULID string, generated in `put_slug/1`, suitable as a public, unguessable identifier),
- `title`, `description`, `show_description`, `show_poll_description`,
- `state`, an `Ecto.Enum` of `[:survey, :pending, :active, :ended]`, default `:pending`,
- `is_public` (boolean), `access_code` (Crockford Base32, see `Voting.AccessCode`),
- `expires_at`, `closed_at`,
- `belongs_to :poll`, `belongs_to :current_question` (`current_question_id`).

So the data scaffolding for an MC flow already exists (`state` plus `current_question_id`), but nothing drives it yet. Today `close_session/2` and `reopen_session/2` only toggle `closed_at`; the `state` enum is never transitioned, and the badge label is derived from `closed_at` (see `SlidexWeb.PollLive.Show.status_label/1`). Reconciling `state` and `closed_at` is an open decision (see section 3).

Context, `Slidex.Voting` (`lib/slidex/voting.ex`):
- `list_sessions/1,2`, `get_session!/2`, `create_session/3`, `update_session/3`, `delete_session/2`, `change_session/3`, `close_session/2`, `reopen_session/2`.
- PubSub helpers: `subscribe_sessions/1` and `broadcast_session/2`, both on the per-owner topic `"user:#{user_id}:sessions"`. There is no per-session (per-room) topic yet.

Supporting modules:
- `Slidex.Authorization.authorize/2`. Ownership checks. Every mutating context function takes a `%Scope{}` and authorizes against `poll.user_id`. Pattern used as `:ok = authorize(scope, record)`, which raises `MatchError` when unauthorized.
- `Slidex.Accounts.Scope` (`for_user/1`). Wraps the current user. Guests have no scope today.
- `Slidex.Preloader.with_preloads/2`. Centralized ordered preloads. For a `Session` it preloads `:poll` and `current_question: [options: <sorted>]`.

Routing (`lib/slidex_web/router.ex`): all poll and session routes live in `live_session :require_authenticated_user`. There are **no public participant routes** and **no participant-facing session view**. Public routes today are only registration, login, and confirmation, inside `live_session :current_user`.

Real time:
- `{Phoenix.PubSub, name: Slidex.PubSub}` is in the supervision tree (`lib/slidex/application.ex`).
- The endpoint exposes the built in LiveView socket at `/live` (`lib/slidex_web/endpoint.ex`); there is no custom user socket.
- There is **no `Phoenix.Presence` module** yet. `Phoenix.Presence` ships with `phoenix`, so no new dependency is needed for it.

Auth: magic link first, optional password, plus a required `username` (collected at registration). Guests are not users and cannot register their way into a session; they need the guest identity model below.

---

## 3. Key design decisions

These cut across multiple features. All are resolved (summarized in section 7); each subsection records the decision and its rationale.

### 3.1 Guest identity (Decided: participant record)
Guests are not `User`s. Add `Voting.Participant` (one row per person per session): `session_id`, `display_name` (nullable), `user_id` (nullable, set when the joiner is logged in), and a `token` (random, stored in the browser via a signed cookie or in the LiveView session). Joining finds or creates the participant for `(session, token)`. This gives a stable identity for presence display and for one vote per question enforcement. Votes themselves are anonymous (see 3.2): the participant link is used only for de-duplication and presence, never to attribute a vote to a named person in the UI.

### 3.2 Vote data model (Decided: single choice, anonymous)
Add `Voting.Vote`: `session_id`, `question_id`, `option_id`, `participant_id`, timestamps. Owned by the `Voting` context (session runtime data). Votes are anonymous: the row carries `participant_id` only so we can enforce one vote per question and update a re-vote. It is never used to show who voted for what. Results are aggregate counts only.
Single choice per question: enforce one vote per question per participant with a unique index on `(session_id, question_id, participant_id)`, and treat a re-vote as a change (update the existing row) rather than an error. Multiple selection is out of scope for this version, so no question kind field is needed.

### 3.3 Session lifecycle and MC flow (Decided: state is the source of truth)
Make `state` the source of truth for the lifecycle and drive it from new context functions:
- `:pending` to `:active` via `start_session/2` (presenter starts; joins and votes open).
- advance with `set_current_question/3` (or `advance_session/2` to the next question by position).
- `:active` to `:ended` via `end_session/2` (voting closes).
- `:ended` back to `:active` via `reopen_session/2` (reopen is kept).
- `:survey` never transitions (surveys are self paced).

Reconcile `state` and `closed_at`: `end_session/2` sets `state: :ended` and stamps `closed_at`; `reopen_session/2` sets `state: :active` and clears `closed_at`. `closed_at` becomes only a timestamp. Update `SlidexWeb.PollLive.Show.status_label/1` and the close, reopen, and edit controls to read `state` instead of `closed_at`.

### 3.4 Per-session PubSub topic (needed by 4.2 to 4.5)
Add a room topic keyed by the public slug: `"session:#{session.slug}"`. Presenter and participants both subscribe. Event messages (proposed): `{:state_changed, state}`, `{:question_changed, question_id}`, `{:results_updated, question_id}`. Keep the existing `"user:#{id}:sessions"` topic for the owner's dashboard. Use the slug (not the internal id) in the topic so guests never need the internal id.

### 3.5 Presence (needed by 4.4)
Add `Slidex.Presence` using `Phoenix.Presence`, `pubsub_server: Slidex.PubSub`, and add it to the supervision tree after PubSub. Track in the presenter and participant LiveViews on mount when `connected?`. Presence metas carry `display_name`, `role` (`:owner` or `:guest` or `:user`), and `joined_at`. Topic is the same `"session:#{slug}"`.

### 3.6 Public access and the join page (Decided: slug link, defer the code)
Add public routes in a `live_session` that mounts the current scope but does not require authentication (mirror the existing `:current_user` block, or add a dedicated one). Join route: `live "/join/:slug", SessionLive.Join`. For this version the unguessable `slug` is the access mechanism, so there is no access code prompt. `is_public` still gates who may join: a public session admits guests, while a non public session requires the visitor to be logged in (a guest is sent to log in and returned). The `access_code` is displayed by the presenter but not enforced yet. Enforcing it later, only for public sessions, is the owner's stated preference and is left as a refinement.

### 3.7 Quiz semantics and is_correct (Decided: reveal only)
`Option.is_correct` exists and is shown in the editor, but nothing consumes it. Decision: after a question ends, the results reveal the correct option or options (highlight those marked correct). There is no scoring and no leaderboard in this version. Results are presenter only (see 4.5), so the reveal appears on the presenter view.

---

## 4. Feature specifications

Each feature lists its goal, data, context functions, web layer, real time, authorization, and tests. Function names are proposals; keep signatures scope first to match the codebase.

### 4.1 Foundation: participants and votes
**Goal.** A place to store who joined and what they voted. This unblocks everything else.

**Data.** New migrations and schemas:
- `Voting.Participant`: `belongs_to :session`, `display_name :string` nullable, `belongs_to :user` nullable, `token :string`. Unique index on `(session_id, token)`. Binary id primary key, `@foreign_key_type :binary_id`, like the rest of the app.
- `Voting.Vote`: `belongs_to :session`, `belongs_to :question`, `belongs_to :option`, `belongs_to :participant`. Unique index on `(session_id, question_id, participant_id)` (single choice, see 3.2). Consider an index on `(session_id, question_id)` for tallying.

**Context (`Slidex.Voting`).**
- `find_or_create_participant(session, token, attrs)`. No scope (guests allowed); validate the session is joinable.
- `cast_vote(session, participant, question, option)`. Validates the question belongs to the session's poll, the option belongs to the question, the session is `:active` (or a survey that is open), and the question is the current one when in MC mode. Upserts under the unique index. Broadcasts `{:results_updated, question_id}` on the room topic.
- `tally(session, question)`. Returns counts per option. Keep the counting logic pure and tested (take the list of votes in, return a map or list out), with a thin wrapper that loads the votes.
- Once votes exist, implement the existing TODOs in `Slidex.Polling` that guard editing or deleting a question or option that already has responses.

**Tests.** Context tests and doctests for `cast_vote` (happy path, one vote per question, re-vote updates, wrong option rejected, inactive session rejected) and for the pure `tally` function. Add `Voting` fixtures (`participant_fixture`, `vote_fixture`) alongside the existing fixtures.

### 4.2 Session lifecycle and MC flow
**Goal.** A presenter drives the session and the current question; everyone sees changes live.

**Context.** `start_session/2`, `end_session/2`, `set_current_question/3` (and optionally `advance_session/2` and `previous_question/2`). All take `%Scope{}` and authorize against the poll owner. Each transition broadcasts on `"session:#{slug}"` and on the owner topic. Reconcile `state` and `closed_at` per 3.3.

**Web.** A presenter LiveView, for example `SlidexWeb.SessionLive.Present` at `live "/sessions/:id/present", SessionLive.Present` inside the authenticated `live_session`. It shows the current question and options, presence count, the access code, the join URL, the QR code (4.5, 6), and controls: start, next, previous, end. It subscribes to the room topic and re-renders on broadcasts.

**Authorization.** Presenter actions are owner only. Reuse `authorize/2`.

**Tests.** Context tests for the transitions (pending to active to ended, advancing current question, survey rejects MC actions, non owner rejected). Minimal LiveView test that the presenter controls exist and advancing changes the displayed question, using element ids.

### 4.3 Join page (participant entry)
**Goal.** A public URL that lets anyone in the room enter a session.

**Web.** `SlidexWeb.SessionLive.Join` at `live "/join/:slug", SessionLive.Join`, in a public `live_session` that mounts the current scope without requiring auth (see 3.6 and the AGENTS.md auth guidance; tell the owner which scope and why). Behavior: look up the session by slug. If not joinable (ended, expired, or missing), show a friendly state. If the session is non public and the visitor is not logged in, send them to log in and back. There is no access code prompt in this version (3.6). Optionally prompt for a display name (prefilled with the logged in user's username when present). On join, establish the participant (3.1), store the token in the browser, and route into the participant voting view (4.4), or render voting inline in the same LiveView.

**Authorization.** Public route. Guests allowed for public sessions; non public sessions require a logged in user. No access code check in this version.

**Tests.** LiveView tests: public session lets you join; non public session requires the code; ended or expired session is blocked.

### 4.4 Participant voting plus presence
**Goal.** A participant sees the current question, votes, and is counted as present.

**Web.** The participant view (inside `SessionLive.Join` or a dedicated `SessionLive.Participate`). It subscribes to `"session:#{slug}"`, renders the current question and options (for MC sessions, the session's `current_question`; for surveys, all questions), submits votes via `Voting.cast_vote`, and reflects `{:question_changed, ...}` and `{:state_changed, ...}`. It tracks presence on mount when connected, with the participant's display name and role.

**Presence.** Add `Slidex.Presence` and supervise it (3.5). The presenter view (4.2) and this view both track and both can display the count and, optionally, the list. Handle the `"presence_diff"` broadcast and recompute. "Guests too" means guest metas appear in the same list, distinguished by `role`.

**Tests.** LiveView test that voting records a vote and that a `{:question_changed}` broadcast updates the participant's screen. Presence can be exercised at the context or LiveView level minimally.

### 4.5 Live results display plus QR
**Goal (results).** Show vote tallies updating live on the presenter view. Participants do not see results in this version (presenter only).

**Web (results).** A results component rendered from `Voting.tally`, on the presenter view only. Recompute and re-render on `{:results_updated, question_id}`. Show counts and percentages. After a question ends, highlight the correct option or options (`is_correct`, see 3.7).

**Goal (QR).** A scannable code on the presenter and share views that encodes the absolute join URL.

**Web (QR).** Add `{:qr_code, "~> 3.2"}` to `mix.exs` and run `mix deps.get`. Generate an SVG from `url(~p"/join/#{session.slug}")` and render it next to the access code and join URL. Keep generation in a small helper so it is easy to test the URL it encodes. QR rendering is a static SVG; no hook needed.

**Tests.** Pure tests for the tally and for the helper that builds the join URL. Minimal LiveView assertion that the results region and the QR image are present.

---

## 5. Build order

Dependency sequenced. Each batch ends green (`mix test`) and is committed atomically.
1. **Foundation (4.1).** Participants and votes schemas, migrations, `Voting` functions, fixtures, tests. Linchpin for the rest.
2. **MC flow (4.2).** Lifecycle transitions, room topic, presenter LiveView. Reconcile `state` and `closed_at` here.
3. **Join plus participant voting (4.3, 4.4 voting half).** Public route, access gate, participant identity, the core vote loop.
4. **Presence (4.4 presence half).** `Slidex.Presence`, supervision, tracking and display in present and participant views.
5. **Live results (4.5 results half).** Tally broadcasts and the results component.
6. **QR (4.5 QR half).** Add the dependency and render the code. Small and optional; can be pulled earlier if useful for demos.

Presence (4) can move earlier if the owner wants a "people are here" feel before voting works. QR (6) is independent and quick.

---

## 6. Conventions checklist

- Scope and authorization first. Owner mutations take `%Scope{}` and call `authorize/2`. Participant and guest paths are public and gate only on `is_public` and `access_code`.
- Programmatic fields (`slug`, `token`, foreign keys, `state`) are set on the struct, not listed in `cast`. See the existing `Voting.Session.put_slug/1` and the `next_position/3` helper in `Slidex.Polling` for the pattern.
- Binary id primary keys and `@foreign_key_type :binary_id` on every new schema. Primary keys are UUIDv4; ULID is used only for the session `slug`.
- Pure functions first. Put tally and any non trivial logic in pure functions with doctests. LiveViews hold presentation only. See `docs/testing-posture.md`.
- Real time uses `Slidex.PubSub`. New room topic is `"session:#{slug}"`. Presence uses the same topic.
- LiveView and HEEx per AGENTS.md: `<Layouts.app ...>` wrappers, `to_form/2`, the imported `<.input>` and `<.icon>`, unique DOM ids for testable elements, no inline scripts, list syntax for conditional classes.
- Routing per AGENTS.md: put authenticated views in the existing `live_session :require_authenticated_user`; put public participant views in a scope that mounts the current scope without requiring auth, and state which scope and why.
- Docs and commits: no em dashes, sentence case headings, imperative commit titles under 52 characters, no attribution, atomic commits. Run `mix precommit` before pushing.
- Verify in the browser, not only with tests.

---

## 7. Decisions (resolved 2026-06-11)

All eight questions are answered. These are binding for this version.
1. Guest identity: a `Voting.Participant` table (3.1).
2. Voting: single choice per question only; a re-vote updates the existing vote. Multiple selection is out of scope (3.2).
3. Attribution: votes are anonymous; results are aggregate counts only (3.2).
4. Quiz mode: reveal only, no scoring or leaderboard (3.7).
5. Lifecycle: `state` is the source of truth; `closed_at` is only a timestamp; reopen is kept (3.3).
6. Access: the `slug` link is the access mechanism; no access code prompt in this version; `is_public` gates guest versus logged in (3.6).
7. Results visibility: presenter only in this version (4.5).
8. Surveys: reuse the participant and vote model but skip the MC flow; all questions stay open until the session is closed (sections 1 and 4.4).

---

*With these decisions recorded, this document plus the code is enough to implement the work batches in section 5 in order. Start with batch 1 (the foundation).*
