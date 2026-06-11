# CLAUDE.md

## Project

Slidex is a Phoenix 1.8 and LiveView application: an interactive polling and survey platform inspired by Slido. It also serves as an educational reference for idiomatic Elixir, Ecto, and LiveView.

Authenticated users (magic link, optional password) author and manage polls. The domain is split into three contexts:

- **Campaigns**: polls and their lifecycle (create, edit, duplicate, archive, delete).
- **Polling**: ordered questions and options within a poll, with manual reordering and a correct-answer flag for quiz-style questions.
- **Voting**: voting sessions and surveys created from a poll, each with an access code, public or private visibility, optional expiration, and a close/reopen lifecycle.

The owner-facing authoring and session management is built, and so is the participant-facing live voting experience: a public join page (by slug, with a QR code), single-choice voting, presence, presenter-side live results, and final results shown to participants after the session ends. See [docs/live-voting-sessions.md](docs/live-voting-sessions.md). Deferred for later: enforcing the access code for public sessions, live results for participants during voting, and quiz scoring.

## Existing code

The initial implementation was written by Isaak, before the conventions in this file existed, and Petros is now taking it over to finish it. As a result, parts of the existing code and the older docs (ARCHITECTURE.md, DESIGN.md) predate these rules and do not always follow them. That is expected. Do not rewrite or reformat working code just to satisfy the conventions. Any new code must follow the guidelines in this file and in AGENTS.md.

## Key documentation

- [ARCHITECTURE.md](ARCHITECTURE.md) - Shared foundation and project structure.
- [DESIGN.md](DESIGN.md) - Design and next steps 
- [docs/testing-posture.md](docs/testing-posture.md) - Testing strategy. Pure functions first, doctests on every public function, no business logic in LiveView.
- [AGENTS.md](AGENTS.md) - Phoenix 1.8, Elixir, LiveView, Ecto, and HEEx conventions. Read before writing any UI, template, or LiveView code.
- [docs/live-voting-sessions.md](docs/live-voting-sessions.md) - Design and build plan for live sessions: presence, MC flow, vote tracking and results, join page, and QR code.
- [docs/running-a-live-session.md](docs/running-a-live-session.md) - Runbook for hosting a live session in front of an audience, with a deploy and day-of checklist.

## Commands

```bash
mix setup              # Install deps, create DB, build assets
mix phx.server         # Start the server
iex -S mix phx.server  # Start with interactive shell
mix test               # Run tests
mix precommit          # Run before pushing: format, credo --strict, tests
```

## Code conventions

- All business logic in pure functions. Side effects (HTTP, DB) pushed to the boundaries.
- Every public function gets `@moduledoc`, `@doc`, and at least one doctest.

## Style

- No em dashes. Use commas or periods.
- Commit titles start with a verb in the imperative, max 52 characters, no attribution.
- Atomic commits
- Markdown docs use sentence case for titles
