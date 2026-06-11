# Slidex – Architecture Document

**Version**: 2.1 (Updated)  
**Date**: 2026-06-11  
**Status**: Reflects current concatenated codebase

---

## 1. System Overview

Slidex is a **Phoenix 1.8 + LiveView** monolith that demonstrates a complete interactive polling/survey platform.

**Core principles**:
- LiveView / LiveComponent everywhere possible.
- Clear context separation (`Campaigns`, `Polling`, `Voting`).
- Self-contained components with **colocated hooks**.
- Optimistic UI via temporary records.
- Native browser features (`<dialog>`), UUIDv4 (`:binary_id`) keys, ULID session slugs, and integer `position` ordering.
- Centralized authorization and preloading.

**Deployment**: Standard Phoenix release.

---

## 2. Context & Module Boundaries

```
Slidex App
├── Accounts          (User, UserToken, Scope, magic-link auth)
├── Campaigns         (Poll lifecycle, ownership, duplicate, archive)
├── Polling           (Question + Option + Reorder + Search)
├── Voting            (Sessions, participants, votes, MC lifecycle, live room, Tally, AccessCode)
├── Presence          (Phoenix.Presence: who is in a live session)
├── Authorization     (central ownership checks)
├── Preloader         (ordered preloads + sorting)
└── Search            (body search with exclusion)
```

**Why three contexts?**
- `Campaigns`: High-level ownership and campaign management.
- `Polling`: Reusable content structure (questions/options).
- `Voting`: Session-specific logic (state machine, access codes, expiration).

---

## 3. Database Schema (Current)

All tables use `@primary_key {:id, :binary_id, autogenerate: true}` and `@foreign_key_type :binary_id`, i.e. **UUIDv4** keys (Ecto's default `binary_id` autogeneration). The only ULID in the system is the session `slug`, generated with `Ecto.ULID` (see `Voting.Session.put_slug/1`).

### Key Relationships

```mermaid
erDiagram
    USERS ||--o{ POLLS : owns
    POLLS ||--o{ QUESTIONS : contains
    POLLS ||--o{ SESSIONS : contains
    QUESTIONS ||--o{ OPTIONS : contains
    SESSIONS ||--o| QUESTIONS : current_question
    SESSIONS ||--o{ PARTICIPANTS : has
    SESSIONS ||--o{ VOTES : has
    PARTICIPANTS ||--o{ VOTES : casts
    QUESTIONS ||--o{ VOTES : receives
    OPTIONS ||--o{ VOTES : chosen_in

    POLLS {
        binary_id id PK
        binary_id user_id FK
        string title
        text description
        string access_code
        utc_datetime_usec archived_at
        timestamps
    }

    QUESTIONS {
        binary_id id PK
        binary_id poll_id FK
        integer position
        string body
        timestamps
    }

    OPTIONS {
        binary_id id PK
        binary_id question_id FK
        integer position
        string body
        boolean is_correct
        timestamps
    }

    SESSIONS {
        binary_id id PK
        binary_id poll_id FK
        binary_id current_question_id FK
        string slug
        string title
        text description
        boolean show_description
        boolean show_poll_description
        enum state [:survey, :pending, :active, :ended]
        boolean is_public
        string access_code
        utc_datetime expires_at
        utc_datetime_usec closed_at
        timestamps
    }

    PARTICIPANTS {
        binary_id id PK
        binary_id session_id FK
        binary_id user_id FK
        string display_name
        string token
        timestamps
    }

    VOTES {
        binary_id id PK
        binary_id session_id FK
        binary_id question_id FK
        binary_id option_id FK
        binary_id participant_id FK
        timestamps
    }
```

**Position handling**: Integer columns on Question and Option. Normalized after every reorder.

---

## 4. LiveView Hierarchy (Current)

```
PollLive.Index
PollLive.Form
PollLive.Show
├── Lists of Voting Sessions + Surveys
└── Navigation to SessionLive.Form

PollLive.Questions
├── QuestionLive (×N)
│   └── OptionLive (×M inside each)

SessionLive.Form
SessionLive.Present   (presenter / MC, owner only: /sessions/:id/present)
SessionLive.Results   (owner results, live updating: /sessions/:id/results)
SessionLive.Join      (public participant: /join/:slug)
```

### Component Communication

- **Parent → Child**: Assigns (`current_scope`, `poll`, `question`, `is_survey`, etc.).
- **Child → Parent**: `send(self(), {:event_name, payload})` (e.g. `{:question_created, ...}`, `{:options_reordered, ...}`).
- **PubSub**: `user:#{user_id}:polls`, `user:#{user_id}:sessions`, and the per-room `session:#{slug}` topic (live lifecycle, question, results events, and Presence).
- **Form handling**: `phx-change` / `phx-submit` with `to_form/1`.

---

## 5. Key Modules & Responsibilities

### Contexts

| Context     | Key Public Functions |
|-------------|----------------------|
| `Campaigns` | `list_polls/2`, `create_poll/2`, `duplicate_poll/2`, `archive_poll/2`, `get_poll!/2` |
| `Polling`   | `create_question/3`, `update_question/3`, `reorder/3`, `list_questions/2`, `Search.question_body/3` |
| `Voting`    | `create_session/3`, `start_session/2`, `set_current_question/3`, `close_session/2`, `reopen_session/2`, `find_or_create_participant/3`, `cast_vote/4`, `tally/2`, `get_session_by_slug/1` |

### Supporting

- **Authorization.authorize/2** — ownership checks for all mutable entities.
- **Preloader.with_preloads/2** — handles nested preloads + sorting (questions by `position`, options by `position`).
- **Search** — ILIKE + `distinct` + exclusion lists (used heavily by QuestionLive/OptionLive search dropdowns).
- **Polling.Reorder** — atomic position swapping + normalization in a transaction.
- **Voting.AccessCode** — Crockford Base32 6-char codes with separators.
- **Voting.Tally**: pure per-option vote counting (`by_option/1`), used by the presenter results.
- **Slidex.Presence**: `Phoenix.Presence` tracking who is in a live session (owner, logged-in user, or guest).
- **SlidexWeb.SessionQR**: builds a session's absolute join URL and renders it as a QR code SVG.

---

## 6. Data Flows (Current Implementation)

### 1. Optimistic Question + Option Creation
1. `PollLive.Questions` adds temporary map to `@questions`.
2. `QuestionLive` renders in edit mode.
3. Debounced `phx-change="search"` → `Search.question_body/3` (with exclusion of current poll/question).
4. Save → `Polling.create_question/3` → parent receives `{:question_created, saved, temp_id}` and replaces temp record.
5. Same pattern inside `OptionLive` for options.

### 2. Reordering
- Button in `QuestionLive` or `OptionLive` → `Polling.reorder(scope, record, :higher/:lower)`.
- `Reorder.move/3` performs swap + re-normalization in `Repo.transaction`.
- Parent receives `{:questions_reordered, poll}` or `{:options_reordered, question}`.
- Reloads list via `Preloader` or `list_*` functions.

### 3. Session Lifecycle
- From `PollLive.Show` → "Add Voting/Survey" navigates to `SessionLive.Form` with query params.
- `SessionLive.Form`:
  - Kind radio buttons (voting vs survey) → updates `state`.
  - Poll selector (when creating new).
  - Access code generator (`AccessCode.generate/0`).
  - Expiration datetime.
- On save → `Voting.create_session/3` or `update_session/3` → redirect back to `PollLive.Show`.

### 4. Poll Duplication
- `Campaigns.duplicate_poll/2`:
  - Creates new poll with incremented "(copy N)" title.
  - Copies all questions + all options (preserving `position` and `is_correct`).

### 5. Archive / Close Flows
- Archive: `Campaigns.archive_poll/2` sets `archived_at`.
- Session close: `Voting.close_session/2` stamps `closed_at` and, for a voting session, also sets `state: :ended` (a survey keeps its `:survey` state). `reopen_session/2` mirrors this back to `:active`.
- Both broadcast via PubSub and update UI.

### 6. Live Voting Session
- The owner opens `SessionLive.Present` (`/sessions/:id/present`) and starts the session (`start_session/2`, `state: :active`). Start, Previous, Next, and End drive `set_current_question/3` and `close_session/2`, broadcasting on `session:#{slug}`.
- Participants open `SessionLive.Join` (`/join/:slug`), receive a guest token from the `ensure_participant_token` plug, and become a `Participant` via `find_or_create_participant/3`. Public sessions admit guests; non-public sessions require login.
- A vote calls `cast_vote/4` (single choice, a re-vote replaces) and broadcasts `{:results_updated, question_id}`.
- The presenter recomputes `tally/2` live and reveals the correct option. `Slidex.Presence` shows who is connected on both views.
- The owner can copy a session's join link from `PollLive.Show` and review its tally any time via `SessionLive.Results` (`/sessions/:id/results`), which also updates live (handy for surveys, which have no presenter).
- After the session ends the presenter keeps the final results on screen, and participants see them on the join page.

---

## 7. Technical Stack & Notable Decisions

| Area                        | Implementation                              | Notes |
|-----------------------------|---------------------------------------------|-------|
| Primary keys                | UUIDv4 (`:binary_id`)                       | Random, URL-safe, secure |
| Session slugs               | ULID (`Ecto.ULID`)                          | Sortable, URL-safe public id |
| Ordering                    | Integer `position` + `Reorder` module       | Predictable, easy to normalize |
| Modals                      | Native `<dialog>` + daisyUI + colocated hook | Accessible, self-contained |
| Search                      | ILIKE + exclusion + distinct                | Simple & sufficient for demo |
| Forms                       | `to_form/1` + `phx-change`/`phx-submit`     | LiveView idiomatic |
| Hooks                       | Colocated (`<script :type={Phoenix.LiveView.ColocatedHook}>`) | Modal + RelativeTime |
| Auth                        | Magic link (primary) + optional password    | Modern & secure |
| Preloading                  | Centralized `Preloader` module              | Handles sorting automatically |
| Real-time                   | PubSub (user topics + per-room `session:#{slug}`) + `Phoenix.Presence` | Owner dashboards and live sessions |
| QR codes                    | `qr_code` SVG via `SlidexWeb.SessionQR`     | Scannable join link on the presenter |

---

## 8. Security & Authorization

- Every context mutation function receives `%Scope{}`.
- `Authorization.authorize/2` checks `user_id` ownership (with preloads where needed).
- No raw Ecto queries in LiveViews.
- Temporary records never hit DB until explicitly persisted.
- Session tokens + remember-me cookies with proper expiry.

---

## 9. Testing Strategy (Recommended)

- Context tests for `Polling`, `Voting`, `Campaigns` (especially `Reorder` and duplication).
- LiveView tests for `PollLive.Questions`, `PollLive.Show`, `SessionLive.Form`.
- Component tests for `QuestionLive` and `OptionLive` (search, edit, reorder, temporary state).
- Integration test covering full flow: create poll → add questions + options → create session → close session.

---

## 10. Open / Future Work

Done in the live voting sessions work (2026-06-11): real-time participant view (`SessionLive.Join`), live vote counting and results (`SessionLive.Present`), presence, and a QR join code. See `docs/live-voting-sessions.md`.

Still open:
- Drag-and-drop reordering (SortableJS or LiveView drag events).
- Enforce `access_code` for public sessions. Today the unguessable `slug` link is the access mechanism; the code can be set in the session form (marked not enforced), but it is not shown to participants or checked at join.
- Live results for participants during voting. Today the final results are shown to participants once the session ends; live tallies stay presenter only.
- Quiz scoring or a leaderboard (currently `is_correct` is reveal only).
- Rich question content (markdown, images).
- Oban jobs (e.g. auto-close expired sessions).

---

**This architecture document is aligned with the current concatenated codebase (June 2026).**

*Updated: 2026-06-11*