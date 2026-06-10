# Slidex – Architecture Document

**Version**: 2.0 (Updated)  
**Date**: 2026-06-10  
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
├── Voting            (Session management, close/reopen, AccessCode)
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
```

### Component Communication

- **Parent → Child**: Assigns (`current_scope`, `poll`, `question`, `is_survey`, etc.).
- **Child → Parent**: `send(self(), {:event_name, payload})` (e.g. `{:question_created, ...}`, `{:options_reordered, ...}`).
- **PubSub**: `user:#{user_id}:polls` and `user:#{user_id}:sessions`.
- **Form handling**: `phx-change` / `phx-submit` with `to_form/1`.

---

## 5. Key Modules & Responsibilities

### Contexts

| Context     | Key Public Functions |
|-------------|----------------------|
| `Campaigns` | `list_polls/2`, `create_poll/2`, `duplicate_poll/2`, `archive_poll/2`, `get_poll!/2` |
| `Polling`   | `create_question/3`, `update_question/3`, `reorder/3`, `list_questions/2`, `Search.question_body/3` |
| `Voting`    | `create_session/3`, `close_session/2`, `reopen_session/2`, `list_sessions/2` |

### Supporting

- **Authorization.authorize/2** — ownership checks for all mutable entities.
- **Preloader.with_preloads/2** — handles nested preloads + sorting (questions by `position`, options by `position`).
- **Search** — ILIKE + `distinct` + exclusion lists (used heavily by QuestionLive/OptionLive search dropdowns).
- **Polling.Reorder** — atomic position swapping + normalization in a transaction.
- **Voting.AccessCode** — Crockford Base32 6-char codes with separators.

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
- Session close: `Voting.close_session/2` sets `closed_at`.
- Both broadcast via PubSub and update UI.

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
| Real-time                   | PubSub (user-scoped topics)                 | Clean multi-user support |

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

- Drag-and-drop reordering (SortableJS or LiveView drag events).
- Real-time participant view (separate LiveView consuming `current_question`).
- Access code entry page for guests.
- Results / live vote counting LiveView.
- Rich question content (markdown, images).
- Oban jobs (e.g. auto-close expired sessions).

---

**This architecture document is aligned with the current concatenated codebase (June 2026).**

*Updated: 2026-06-10*