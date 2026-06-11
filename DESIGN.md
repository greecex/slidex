# Slidex – Design Document

**Project**: Slidex (Phoenix 1.8 + LiveView demo / tutorial app)  
**Goal**: Build a clean, educational, production-ready example of a real-time polling/surveying platform (inspired by Slido) that demonstrates idiomatic Elixir, Ecto, Phoenix LiveView, LiveComponents, ordering, search, modals, colocated hooks, and daisyUI.  
**Status**: Active development (June 2026)  
**Primary contexts**: `Campaigns` (Polls + ownership), `Polling` (Questions + Options), `Voting` (Sessions)

---

## 1. High-Level Architecture

- **Monolith-first, single codebase**.
- **Three main contexts**:
  - `Campaigns` – owns `Poll`, high-level lifecycle, ownership via `Scope`, PubSub.
  - `Polling` – owns `Question` + `Option` (interactive content), reordering, search.
  - `Voting` – owns `Session` (voting sessions and surveys).
- **LiveView-first UI** – everything is LiveView or LiveComponent.
- **Optimistic UI** with temporary records (`temp_id`) for questions/options before DB persistence.
- **Self-contained components** (QuestionLive, OptionLive, SessionModal uses shared modal).
- **Colocated hooks** for modals and timers (no global pollution in app.js).
- **Native primitives**: `<dialog>` + daisyUI, UUIDv4 (`:binary_id`) keys, ULID session slugs, integer `position` for ordering.

---

## 2. Domain Model

### Core Entities (UUIDv4 / `binary_id` primary keys)

| Entity     | Context   | Belongs To       | Has Many     | Key Fields                                                                 | Notes |
|------------|-----------|------------------|--------------|----------------------------------------------------------------------------|-------|
| `Poll`     | Campaigns | User (via Scope) | Questions, Sessions | `title`, `description`, `access_code`, `archived_at`                      | Top-level container. Supports duplication. |
| `Question` | Polling   | Poll             | Options      | `position`, `body`                                                         | Ordered inside poll. |
| `Option`   | Polling   | Question         | —            | `position`, `body`, `is_correct`                                           | Ordered inside question. |
| `Session`  | Voting    | Poll             | Participants, Votes | `title`, `description`, `state` (:survey/:pending/:active/:ended), `slug`, `is_public`, `access_code`, `expires_at`, `closed_at`, `show_description`, `show_poll_description`, `current_question_id` | Voting session or Survey. |
| `Participant` | Voting | Session, User (optional) | Votes | `display_name`, `token` | One row per person per session. Stable identity for presence and de-duplication. Anonymous, never shown against a vote. |
| `Vote`     | Voting    | Session, Question, Option, Participant | — | (foreign keys only) | One per participant per question (re-vote replaces). Aggregated by `Voting.Tally`. |

**Ordering**:
- Explicit `position` on Question and Option.
- New items: `max(position) + 1`.
- Reordering via `Polling.Reorder.move/3` (atomic swap + normalize in transaction).
- Preloader + parent LiveView refresh after reorder.

**Authorization**:
- Centralized in `Authorization` module.
- All mutations require `%Scope{}` + ownership check (via `poll.user_id`).

**Special Features**:
- Poll duplication (copies questions + options).
- Poll archive/unarchive.
- Session close/reopen.

---

## 3. Context Responsibilities

### Campaigns
- `Poll` CRUD, duplicate, archive/unarchive.
- Ownership + PubSub broadcasting (`user:#{id}:polls`).
- High-level views (PollLive.Index, Form, Show).

### Polling
- `Question` + `Option` CRUD (scoped to Poll).
- Search (`Search.question_body/3`, `option_body/3` with exclusion).
- Reordering (`reorder/3`).
- `Preloader` for ordered associations.

### Voting
- `Session` CRUD, close/reopen, and the MC lifecycle (`start_session/2`, `set_current_question/3`). `state` is the source of truth.
- `Participant` and `Vote` (single choice, anonymous), `cast_vote/4`, and the pure `Tally`.
- Public lookups for the join page (`get_session_by_slug/1`, `list_session_questions/1`, `list_participant_votes/2`).
- PubSub: per-owner session topic plus the per-room `session:#{slug}` topic (`session_topic/1`).
- `AccessCode` generator (Crockford Base32).

### Supporting Modules
- `Authorization` – ownership checks for Poll/Question/Option/Session.
- `Preloader` – centralized preloading + sorting (questions by position, options by position).
- `Search` – ILIKE search with exclusion lists (used by QuestionLive/OptionLive).
- `Voting.Tally` – pure per-option vote counting (`by_option/1`).
- `Slidex.Presence` – `Phoenix.Presence` tracking who is in a live session (owner, user, guest).
- `SlidexWeb.SessionQR` – builds a session's absolute join URL and renders a QR code SVG.

---

## 4. LiveView & Component Structure

### Main LiveViews
- **PollLive.Index**: List polls (with archived filter), duplicate, archive/unarchive, delete.
- **PollLive.Form**: Create/edit Poll (with description).
- **PollLive.Show**: Poll details + two-column view of **Voting sessions** and **Surveys**. Actions: edit (via form), close/reopen, delete. Add buttons navigate to SessionLive.Form.
- **PollLive.Questions**: Dedicated page for managing questions/options (reorder, edit, search existing bodies, add options).
- **SessionLive.Form**: Create/edit Session (kind selector: voting/survey, poll selector when creating, access code generator, expiration, is_public).
- **SessionLive.Present**: Presenter / MC view (`/sessions/:id/present`, owner only). Start/Previous/Next/End, live results with the correct option revealed, presence count and roster, and a QR join code.
- **SessionLive.Join**: Public participant view (`/join/:slug`). Guest or logged-in voting (single choice), presence count. Public sessions admit guests; non-public sessions require login. Live results are presenter only; the final results are shown here once the session ends.

### LiveComponents (self-contained where possible)
- **QuestionLive** (in PollLive.Questions):
  - View mode: number, reorder buttons, body, list of OptionLive, "Add Option".
  - Edit mode: textarea + live search for existing questions + Save/Cancel/Delete.
  - Supports temporary questions (`temp_id`).
- **OptionLive** (nested in QuestionLive):
  - View mode: number, reorder, body + correct badge, Edit/Delete.
  - Edit mode: textarea + live search for existing options + "Correct" toggle (styled checkbox) + Save/Cancel.
  - Temporary options supported.
- **SessionModal** (legacy/optional – currently Show uses dedicated Form; modal component still available with colocated hook).

### Shared Phoenix Components
- **Modals.modal/1**: Reusable daisyUI `<dialog>` with:
  - Portal to `#modal-root`.
  - Colocated hook (`phx-hook="Modal"`, `open-dialog`/`close-dialog` events).
  - `on_cancel` JS command support.
  - Focus management.
- **Timers.expires_at/1**: Colocated hook for human-readable relative time (e.g. "in 2 days").

---

## 5. Key Technical Decisions (Current State)

| Decision                          | Rationale |
|-----------------------------------|-----------|
| **UUIDv4 primary keys (`:binary_id`)** | Random, URL-safe, secure (Ecto's `binary_id` default). |
| **ULID session slugs (`Ecto.ULID`)** | Sortable, URL-safe public identifiers for sessions. |
| **Explicit `position`**           | Simple manual ordering + easy normalization. |
| **Temporary records (`temp_id`)** | Optimistic UI for questions/options. |
| **Separate `Polling` + `Voting` contexts** | Reusability + clean boundaries. |
| **LiveComponent per Question/Option** | Fine-grained reactivity, easy reordering/search. |
| **Colocated hooks** (`<script :type={Phoenix.LiveView.ColocatedHook}>`) | Self-contained components (Modal, RelativeTime). |
| **Native `<dialog>` + daisyUI**   | Accessibility (focus trap, ESC, backdrop) + beautiful UI. |
| **Dedicated SessionLive.Form**    | Cleaner UX than inline modal for complex session creation (kind, poll selector, code gen). |
| **Search with exclusion**         | Reuse existing questions/options without duplication. |
| **Message passing** (`send(self(), ... )`) | Clean parent ↔ child communication. |
| **Preloader helper**              | Central place for ordered preloads + sorting. |
| **Full auth (magic link + optional password)** | Modern, secure login experience. |
| **`state` is the lifecycle source of truth** | `closed_at` is just a timestamp; presenter transitions drive `state`. |
| **Per-room PubSub + `Phoenix.Presence`** | Live sessions broadcast on `session:#{slug}`; presence shows who is connected. |
| **Anonymous single-choice votes** | One vote per participant per question (re-vote replaces); results are aggregate counts. |
| **QR join code (`qr_code`)** | Scannable link to the join page on the presenter view. |

---

## 6. Data Flow Highlights

### Question + Option Creation (Optimistic)
1. "Add Question" → temporary map added to `@questions`.
2. `QuestionLive` enters edit mode.
3. Live search (debounced) → `Search.question_body/3`.
4. Save → `Polling.create_question/3` → parent replaces temp with real record via `{:question_created, ...}`.
5. Same for options inside each question.

### Reordering
- Button → `Polling.reorder/3` → `Reorder.move/3` (transaction).
- Parent receives `{:questions_reordered, ...}` or `{:options_reordered, ...}`.
- Reload via `Preloader` or `list_*`.

### Session Management
- From PollLive.Show: "Add Voting/Survey" → navigates to `SessionLive.Form` with `?poll=...&kind=...`.
- Form handles poll selector (when creating), kind radio, access code generation, expiration.
- On save → redirects back to PollLive.Show (refreshed sessions list).

### Poll Duplication
- Copies title/description + all questions + all options (with positions and `is_correct`).

---

## 7. Current Feature Set (June 2026)

**Polls**
- Create, edit, duplicate, archive/unarchive, delete.
- Description support.

**Questions & Options** (in dedicated Questions page)
- Add/edit/delete with optimistic UI.
- Live search for existing bodies.
- Manual reordering (up/down buttons).
- Correct option toggle.
- Empty states + helpful buttons.

**Sessions** (Voting + Surveys)
- Create via dedicated form (kind selector, access code generator, expiration, is_public).
- List in PollLive.Show (separate columns).
- Edit, close/reopen, delete.
- State machine (`:survey` vs voting states).

**Live voting sessions**
- Presenter MC flow: start, advance through questions, end (`SessionLive.Present`).
- Public join page by slug with a QR code (`SessionLive.Join`); guests allowed for public sessions.
- Single-choice anonymous voting, one per question (re-vote replaces).
- Live results on the presenter view with the correct option revealed.
- Presence: a live count and roster (owner, logged-in users, guests).

**UI/UX**
- daisyUI + Tailwind.
- Colocated hooks for modals and relative timers.
- Flash messages, dropdown actions, tooltips.
- Responsive layouts.

**Auth**
- Magic link login (primary).
- Optional password.
- Email change, password change (sudo mode).
- Session management.

---

## 8. File / Module Map (Key Files)

```
lib/slidex/
├── accounts/               # Full auth (User, UserToken, Scope, Notifier)
├── campaigns.ex + poll.ex
├── polling.ex + question.ex + option.ex + reorder.ex
├── voting.ex + session.ex + participant.ex + vote.ex + tally.ex + access_code.ex
├── authorization.ex
├── preloader.ex
├── search.ex
├── presence.ex
├── web/
│   ├── live/
│   │   ├── poll_live/
│   │   │   ├── index.ex, form.ex, show.ex, questions.ex
│   │   │   └── components/
│   │   │       ├── question_live.ex, option_live.ex, session_modal.ex
│   │   └── session_live/form.ex, present.ex, join.ex
│   ├── session_qr.ex
│   └── components/
│       ├── modals.ex (colocated Modal hook)
│       ├── timers.ex (colocated RelativeTime hook)
│       └── core_components.ex
```

---

**This document reflects the current state of the concatenated codebase (June 2026).**

*Updated: 2026-06-11*