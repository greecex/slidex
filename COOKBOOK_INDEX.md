# Skill: Nested Dynamic Lists (Phoenix LiveView + LiveComponent)

## Description

Pattern for a LiveView owning a dynamic list of child LiveComponents,
each optionally containing grandchild LiveComponents. Users add, edit,
delete, reorder items inline — no page reloads.

**Use when:** UI needs inline dynamic sub-lists — quiz questions with options,
invoices with line items, playlists with tracks, surveys with questions.

**Source of truth:** `COOKBOOK_NESTED_LIVECOMPONENTS.md` (3100 lines, all details).
This file is the index — read only sections your task needs.

## Architecture (One-Line)

```
Parent LiveView (owns data, DB, flash) → renders N Child LiveComponents (transient state)
→ each renders K Grandchild LiveComponents (same pattern, one hop to parent via send(self(), ...))
```

- `self()` in any LiveComponent = parent LiveView PID
- `send(self(), {:msg, data})` from any depth reaches LiveView's `handle_info/2` directly
- LiveView always source of truth. Components hold only transient UI state.

## Agent Workflow

1. Read this index. Find the category matching your task.
2. Open linked section in `COOKBOOK_NESTED_LIVECOMPONENTS.md`.
3. Optionally click Slidex permalink to see exact production code.
4. Implement. Keep to the pattern — no business logic in LiveView/Component.
5. Run `mix precommit` before finishing.

## Reference Implementation

All patterns from [Slidex](https://github.com/greecex/slidex) (stable, frozen tech demo).

| File | Covers |
|------|--------|
| [PollLive.Questions](https://github.com/greecex/slidex/blob/main/lib/slidex_web/live/poll_live/questions.ex) | Parent LiveView — mount, all handle_info handlers, temp CRUD |
| [QuestionLive](https://github.com/greecex/slidex/blob/main/lib/slidex_web/live/poll_live/components/question_live.ex) | Child LC — update/2, edit/save/delete, reorder, add-grandchild |
| [OptionLive](https://github.com/greecex/slidex/blob/main/lib/slidex_web/live/poll_live/components/option_live.ex) | Grandchild LC — editing guard, save helpers, delete |
| [Preloader](https://github.com/greecex/slidex/blob/main/lib/slidex/preloader.ex) | Dispatch-per-struct preloading with post-sort |
| [Reorder](https://github.com/greecex/slidex/blob/main/lib/slidex/polling/reorder.ex) | Atomic swap with position normalization |
| [Polling context](https://github.com/greecex/slidex/blob/main/lib/slidex/polling.ex) | All CRUD, authorization, position helper |
| [Authorization](https://github.com/greecex/slidex/blob/main/lib/slidex/authorization.ex) | Scope-based user authorization chain |
| [Question schema](https://github.com/greecex/slidex/blob/main/lib/slidex/polling/question.ex) | binary_id, has_many :options, cast_assoc |
| [Option schema](https://github.com/greecex/slidex/blob/main/lib/slidex/polling/option.ex) | binary_id, belongs_to, extra fields |
| [Questions migration](https://github.com/greecex/slidex/blob/main/priv/repo/migrations/20260606143924_create_questions.exs) | composite index, on_delete cascade |
| [Options migration](https://github.com/greecex/slidex/blob/main/priv/repo/migrations/20260606144051_create_options.exs) | same pattern |
| [Router](https://github.com/greecex/slidex/blob/main/lib/slidex_web/router.ex) | live_session scopes, route placement |
| [PollLive.Index](https://github.com/greecex/slidex/blob/main/lib/slidex_web/live/poll_live/index.ex) | Stream usage in list view |

## Key Rules (Violations = Bugs)

- LiveView = source of truth for persisted data. Components = transient state only.
- `phx-target={@myself}` on all component events — without it, events hit parent LV.
- Always re-fetch from DB after mutation. Never use struct from message beyond identity lookup.
- Programmatic fields (position, foreign keys) set on struct, accepted in changeset, never from user params.
- Update/2 fires on every parent re-render. Guard it with editing check to preserve user input.
- Temp records: use `"temp_"` prefix, `System.unique_integer([:positive])` for unique ID, never persist.
- Flash only for persisted operations — temp delete = no flash.
- Context module owns all DB + auth. LiveView = thin orchestration.
- `:binary_id` primary keys. `@foreign_key_type :binary_id` chain.
- `<.form for={@form}>`, never `<.form for={@changeset}>`.
- No `<script>` tags in HEEx. All JS in `assets/js/`.
- No `live_redirect`/`live_patch`. Use `<.link navigate={}>`/`<.link patch={}>`.

## Reference: Intent → Section

### Architecture & Setup
- What's the three-layer pattern? → [Sec 1](COOKBOOK_NESTED_LIVECOMPONENTS.md#1-overview-and-concepts)
- What versions do I need? → [Sec 2.1](COOKBOOK_NESTED_LIVECOMPONENTS.md#21-phoenix-version-and-framework-requirements)
- How do I configure routes? → [Sec 2.2](COOKBOOK_NESTED_LIVECOMPONENTS.md#22-router-configuration)
- How do I write migrations? → [Sec 2.3](COOKBOOK_NESTED_LIVECOMPONENTS.md#23-generating-the-schema-and-migration)
- File structure convention? → [Sec 3](COOKBOOK_NESTED_LIVECOMPONENTS.md#file-structure-convention)
- Schema and changesets? → [Sec 3](COOKBOOK_NESTED_LIVECOMPONENTS.md#schema-pattern)
- Preloader module? → [Sec 3.5](COOKBOOK_NESTED_LIVECOMPONENTS.md#35-the-preloader-strategy)

### Parent LiveView
- Mount? → [Sec 4](COOKBOOK_NESTED_LIVECOMPONENTS.md#mount)
- Render children? → [Sec 4](COOKBOOK_NESTED_LIVECOMPONENTS.md#render)
- Add child optimistically? → [Sec 4](COOKBOOK_NESTED_LIVECOMPONENTS.md#adding-a-child-optimistic)
- Handle child messages? → [Sec 4](COOKBOOK_NESTED_LIVECOMPONENTS.md#receiving-messages-from-children)
- Grandchild events at parent level? → [Sec 4](COOKBOOK_NESTED_LIVECOMPONENTS.md#receiving-messages-from-children)
- send_update/2 targeting? → [Sec 4](COOKBOOK_NESTED_LIVECOMPONENTS.md#send_update2-targeted-parent-to-child-updates)
- Layouts.app structure? → [Sec 4](COOKBOOK_NESTED_LIVECOMPONENTS.md#phoenix-18-layouts-template-structure)

### Child LiveComponent
- Component skeleton? → [Sec 5](COOKBOOK_NESTED_LIVECOMPONENTS.md#the-component)
- Mount transient state? → [Sec 5](COOKBOOK_NESTED_LIVECOMPONENTS.md#the-component)
- update/2 logic? → [Sec 5](COOKBOOK_NESTED_LIVECOMPONENTS.md#update-logic)
- Preserve edit state across re-renders? → [Sec 5](COOKBOOK_NESTED_LIVECOMPONENTS.md#update-logic)
- assign_new/3 alternative? → [Sec 5](COOKBOOK_NESTED_LIVECOMPONENTS.md#preserving-state-with-assign_new3)
- Edit / Cancel Edit? → [Sec 5](COOKBOOK_NESTED_LIVECOMPONENTS.md#edit)
- Save (create vs update)? → [Sec 5](COOKBOOK_NESTED_LIVECOMPONENTS.md#save-create-or-update)
- Delete (temp vs persisted)? → [Sec 5](COOKBOOK_NESTED_LIVECOMPONENTS.md#delete)
- Add grandchild from child? → [Sec 5](COOKBOOK_NESTED_LIVECOMPONENTS.md#add-grandchild-if-this-component-manages-a-nested-list)
- Reorder? → [Sec 5](COOKBOOK_NESTED_LIVECOMPONENTS.md#reorder)

### Grandchild LiveComponent
- Communication difference? → [Sec 6](COOKBOOK_NESTED_LIVECOMPONENTS.md#key-insight-direct-to-parent-communication)
- Scoped messages (A) vs callbacks (B)? → [Sec 6](COOKBOOK_NESTED_LIVECOMPONENTS.md#communication-approaches)
- Approach A: foreign key routing? → [Sec 6](COOKBOOK_NESTED_LIVECOMPONENTS.md#approach-a-scoped-message-with-foreign-key-routing)
- Approach B: callbacks? → [Sec 6](COOKBOOK_NESTED_LIVECOMPONENTS.md#approach-b-callback-function-unified-parentchild)
- Grandchild update/2? → [Sec 6](COOKBOOK_NESTED_LIVECOMPONENTS.md#grandchild-update2-editing-guard)
- Grandchild save with extra fields? → [Sec 6](COOKBOOK_NESTED_LIVECOMPONENTS.md#grandchild-save-private-helpers)
- Grandchild delete? → [Sec 6](COOKBOOK_NESTED_LIVECOMPONENTS.md#grandchild-save-private-helpers)
- Render from child? → [Sec 6](COOKBOOK_NESTED_LIVECOMPONENTS.md#grandchild-render-pattern)

### Data Flow & Messages
- Full event flow walkthrough? → [Sec 8](COOKBOOK_NESTED_LIVECOMPONENTS.md#event-flow-diagram)
- Complete message table? → [Sec 8](COOKBOOK_NESTED_LIVECOMPONENTS.md#complete-message-table)
- What never gets sent? → [Sec 8](COOKBOOK_NESTED_LIVECOMPONENTS.md#what-never-gets-sent)
- Handler signatures at a glance? → [Sec 17](COOKBOOK_NESTED_LIVECOMPONENTS.md#handler-signatures-in-liveview)

### Reordering
- Reorder module? → [Sec 9](COOKBOOK_NESTED_LIVECOMPONENTS.md#context-module-pure-logic)
- Swap with position normalization? → [Sec 9](COOKBOOK_NESTED_LIVECOMPONENTS.md#context-module-pure-logic)
- Context exposes reorder? → [Sec 9](COOKBOOK_NESTED_LIVECOMPONENTS.md#how-the-context-exposes-it)
- Component triggers reorder? → [Sec 9](COOKBOOK_NESTED_LIVECOMPONENTS.md#how-the-livecomponent-triggers-it)
- Parent re-fetch after reorder? → [Sec 9](COOKBOOK_NESTED_LIVECOMPONENTS.md#how-the-parent-liveview-handles-it-always-re-fetch-from-db)

### Optimistic UI & Temp Records
- Temp ID pattern? → [Sec 10](COOKBOOK_NESTED_LIVECOMPONENTS.md#the-temp-id-pattern)
- Detect temp records? → [Sec 10](COOKBOOK_NESTED_LIVECOMPONENTS.md#detecting-temp-records)
- Identity helper? → [Sec 10](COOKBOOK_NESTED_LIVECOMPONENTS.md#the-identity-helper)
- Reconcile on save? → [Sec 10](COOKBOOK_NESTED_LIVECOMPONENTS.md#reconciliation-on-save)
- Flash discipline for temps? → [Sec 10](COOKBOOK_NESTED_LIVECOMPONENTS.md#flash-message-discipline)

### PubSub & Multi-User
- When is PubSub needed? → [Sec 11.1](COOKBOOK_NESTED_LIVECOMPONENTS.md#111-when-pubsub-is-needed)
- Subscribe and handle broadcasts? → [Sec 11.2](COOKBOOK_NESTED_LIVECOMPONENTS.md#112-subscribing-and-handling-broadcasts)
- Protect edits during broadcasts? → [Sec 11.3](COOKBOOK_NESTED_LIVECOMPONENTS.md#113-protecting-edit-state-during-broadcasts)
- Temp records survive broadcasts? → [Sec 11.4](COOKBOOK_NESTED_LIVECOMPONENTS.md#114-temp-record-isolation)
- Conflict resolution strategies? → [Sec 11.5](COOKBOOK_NESTED_LIVECOMPONENTS.md#115-conflict-resolution-strategies)

### Error Recovery
- Validation error — keep form open? → [Sec 12.1](COOKBOOK_NESTED_LIVECOMPONENTS.md#121-validation-error-recovery)
- Authorization failure? → [Sec 12.2](COOKBOOK_NESTED_LIVECOMPONENTS.md#122-authorization-failure-recovery)
- Constraint violation? → [Sec 12.3](COOKBOOK_NESTED_LIVECOMPONENTS.md#123-constraint-violation-recovery)
- Network disconnection? → [Sec 12.4](COOKBOOK_NESTED_LIVECOMPONENTS.md#124-network-disconnection-and-reconnection)
- Graceful degradation? → [Sec 12.5](COOKBOOK_NESTED_LIVECOMPONENTS.md#125-graceful-degradation)

### LiveView Streams
- Streams vs direct assigns trade-offs? → [Sec 7.7](COOKBOOK_NESTED_LIVECOMPONENTS.md#77-streams-vs-direct-assigns-trade-off-analysis)
- Streams with LiveComponents? → [Sec 7.3](COOKBOOK_NESTED_LIVECOMPONENTS.md#73-streams-with-livecomponents)
- Find record by stream_id? → [Sec 7.3](COOKBOOK_NESTED_LIVECOMPONENTS.md#73-streams-with-livecomponents)
- Stream CRUD? → [Sec 7.4](COOKBOOK_NESTED_LIVECOMPONENTS.md#74-stream-based-crud-flow)
- Reorder with streams? → [Sec 7.5](COOKBOOK_NESTED_LIVECOMPONENTS.md#75-streams-and-reordering)
- idx/count with streams? → [Sec 7.6](COOKBOOK_NESTED_LIVECOMPONENTS.md#76-streams-and-the-idx--count-pattern)

### Context Module
- Functions to expose? → [Sec 13](COOKBOOK_NESTED_LIVECOMPONENTS.md#pattern-for-a-context-module)
- Position helper? → [Sec 13](COOKBOOK_NESTED_LIVECOMPONENTS.md#pattern-for-a-context-module)
- Authorization chain? → [Sec 13](COOKBOOK_NESTED_LIVECOMPONENTS.md#authorization-chain)
- Rules for context modules? → [Sec 13](COOKBOOK_NESTED_LIVECOMPONENTS.md#rules-for-the-context-module)

### No-Negotiables
- DO/DON'T list? → [Sec 14](COOKBOOK_NESTED_LIVECOMPONENTS.md#14-no-negotiables-and-guardrails)
- Phoenix 1.8 framework rules? → [Sec 14](COOKBOOK_NESTED_LIVECOMPONENTS.md#phoenix-v18-framework-rules)
- Process rules (from real failures)? → [Sec 14](COOKBOOK_NESTED_LIVECOMPONENTS.md#process-rules-from-real-world-failures)

### Testing
- Testing philosophy? → [Sec 16](COOKBOOK_NESTED_LIVECOMPONENTS.md#testing-philosophy)
- Context tests? → [Sec 16](COOKBOOK_NESTED_LIVECOMPONENTS.md#context-tests)
- LiveView interaction tests? → [Sec 16](COOKBOOK_NESTED_LIVECOMPONENTS.md#liveview-interaction-tests)
- Stream list tests? → [Sec 16](COOKBOOK_NESTED_LIVECOMPONENTS.md#testing-stream-based-lists)
- PubSub LiveView tests? → [Sec 16](COOKBOOK_NESTED_LIVECOMPONENTS.md#testing-pubsub-enabled-liveviews)

### Pitfalls (Debugging)
- Component remounts? → [Pitfall 1](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-1-component-remounts-instead-of-updating)
- State accumulates? → [Pitfall 2](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-2-components-accumulate-state)
- Grandchild messages lost? → [Pitfall 3](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-3-grandchild-messages-get-lost)
- Positions jump? → [Pitfall 4](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-4-reorder-creates-jumping-or-duplicate-positions)
- Flash on temp delete? → [Pitfall 5](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-5-flash-messages-on-temp-deletion)
- update/2 on every keystroke? → [Pitfall 6](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-6-update2-fires-on-every-keystroke)
- send_update cross-boundary? → [Pitfall 7](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-7-send_update3-targeting-across-component-boundaries)
- Stale parent data? → [Pitfall 8](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-8-stale-parent-data-after-mutation-or-reorder)
- Monolithic LiveView? → [Pitfall 9](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-9-monolithic-liveview-trying-to-handle-multiple-roles)
- PubSub overwrites edits? → [Pitfall 10](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-10-pubsub-broadcast-overwrites-users-in-progress-edits)

## Quick Reference
- Handler signatures one place? → [Sec 17](COOKBOOK_NESTED_LIVECOMPONENTS.md#handler-signatures-in-liveview)
- Update guard template? → [Sec 17](COOKBOOK_NESTED_LIVECOMPONENTS.md#component-update-guard-template)
- Full implementation checklist? → [Sec 18](COOKBOOK_NESTED_LIVECOMPONENTS.md#18-implementation-checklist)
