# Cookbook Index — Intent → Section

Questions a dev asks. Each links to the relevant section in `COOKBOOK_NESTED_LIVECOMPONENTS.md`. Read only what your task needs.

## Reference Implementation

All patterns extracted from [Slidex](https://github.com/greecex/slidex), a Phoenix LiveView tech demo (stable, frozen). Use permalinks to see exact production code:

| File | Covers |
|------|--------|
| [PollLive.Questions](https://github.com/greecex/slidex/blob/main/lib/slidex_web/live/poll_live/questions.ex) | Parent LiveView — mount, render, all handle_info handlers, temp CRUD |
| [QuestionLive](https://github.com/greecex/slidex/blob/main/lib/slidex_web/live/poll_live/components/question_live.ex) | Child LiveComponent — update/2, edit/save/delete, reorder, add-grandchild |
| [OptionLive](https://github.com/greecex/slidex/blob/main/lib/slidex_web/live/poll_live/components/option_live.ex) | Grandchild LiveComponent — editing guard, save helpers, delete |
| [Preloader](https://github.com/greecex/slidex/blob/main/lib/slidex/preloader.ex) | Dispatch-per-struct preloading with post-sort |
| [Reorder](https://github.com/greecex/slidex/blob/main/lib/slidex/polling/reorder.ex) | Atomic swap with position normalization |
| [Polling context](https://github.com/greecex/slidex/blob/main/lib/slidex/polling.ex) | All CRUD functions, authorization, position helper |
| [Authorization](https://github.com/greecex/slidex/blob/main/lib/slidex/authorization.ex) | Scope-based user authorization chain |
| [Question schema](https://github.com/greecex/slidex/blob/main/lib/slidex/polling/question.ex) | binary_id, has_many :options, cast_assoc |
| [Option schema](https://github.com/greecex/slidex/blob/main/lib/slidex/polling/option.ex) | binary_id, belongs_to, extra fields |
| [Questions migration](https://github.com/greecex/slidex/blob/main/priv/repo/migrations/20260606143924_create_questions.exs) | composite index, on_delete cascade |
| [Options migration](https://github.com/greecex/slidex/blob/main/priv/repo/migrations/20260606144051_create_options.exs) | same pattern |
| [Router](https://github.com/greecex/slidex/blob/main/lib/slidex_web/router.ex) | live_session scopes, route placement |
| [PollLive.Index (streams)](https://github.com/greecex/slidex/blob/main/lib/slidex_web/live/poll_live/index.ex) | Stream usage in a list view |

---



## Architecture & Setup

- What's the three-layer pattern? → [Sec 1: Overview](COOKBOOK_NESTED_LIVECOMPONENTS.md#1-overview-and-concepts)
- What Phoenix/Elixir versions do I need? → [Sec 2.1: Phoenix Version Requirements](COOKBOOK_NESTED_LIVECOMPONENTS.md#21-phoenix-version-and-framework-requirements)
- How do I configure routes for authenticated vs public lists? → [Sec 2.2: Router Configuration](COOKBOOK_NESTED_LIVECOMPONENTS.md#22-router-configuration)
- How do I write the migration for child/grandchild tables? → [Sec 2.3: Migration Example](COOKBOOK_NESTED_LIVECOMPONENTS.md#23-generating-the-schema-and-migration)
- What's the file structure convention? → [Sec 3: File Structure Convention](COOKBOOK_NESTED_LIVECOMPONENTS.md#file-structure-convention)
- How do the schema and changesets look? → [Sec 3: Schema Pattern](COOKBOOK_NESTED_LIVECOMPONENTS.md#schema-pattern)
- What should be in the Preloader module? → [Sec 3.5: Preloader Strategy](COOKBOOK_NESTED_LIVECOMPONENTS.md#35-the-preloader-strategy)

## Parent LiveView

- How does mount look? → [Sec 4: Mount](COOKBOOK_NESTED_LIVECOMPONENTS.md#mount)
- How do I render child LiveComponents? → [Sec 4: Render](COOKBOOK_NESTED_LIVECOMPONENTS.md#render)
- How do I add a child optimistically? → [Sec 4: Adding a Child](COOKBOOK_NESTED_LIVECOMPONENTS.md#adding-a-child-optimistic)
- How do I handle child-created/updated/deleted messages? → [Sec 4: Receiving Messages](COOKBOOK_NESTED_LIVECOMPONENTS.md#receiving-messages-from-children)
- How do I handle grandchild events at the parent level? → [Sec 4: Grandchild Events at the Parent Level](COOKBOOK_NESTED_LIVECOMPONENTS.md#receiving-messages-from-children)
- How do I target a specific child without re-rendering all? → [Sec 4: send_update/2](COOKBOOK_NESTED_LIVECOMPONENTS.md#send_update2-targeted-parent-to-child-updates)
- When should I NOT use send_update/2? → [Sec 4: When Wrong](COOKBOOK_NESTED_LIVECOMPONENTS.md#send_update2-is-the-wrong-tool-when)
- What Layouts.app template structure is needed? → [Sec 4: Layouts Template](COOKBOOK_NESTED_LIVECOMPONENTS.md#phoenix-18-layouts-template-structure)

## Child LiveComponent

- What's the basic component skeleton? → [Sec 5: The Component](COOKBOOK_NESTED_LIVECOMPONENTS.md#the-component)
- How does mount initialize transient state? → [Sec 5: The Component](COOKBOOK_NESTED_LIVECOMPONENTS.md#the-component)
- How does update/2 synchronize with parent assigns? → [Sec 5: Update Logic](COOKBOOK_NESTED_LIVECOMPONENTS.md#update-logic)
- How do I preserve edit state across re-renders? → [Sec 5: Editing-Guard Pattern](COOKBOOK_NESTED_LIVECOMPONENTS.md#update-logic)
- What's the alternative with assign_new/3? → [Sec 5: assign_new/3](COOKBOOK_NESTED_LIVECOMPONENTS.md#preserving-state-with-assign_new3)
- How do I handle events (edit, cancel_edit)? → [Sec 5: Edit / Cancel Edit](COOKBOOK_NESTED_LIVECOMPONENTS.md#edit)
- How does save distinguish create vs update? → [Sec 5: Save](COOKBOOK_NESTED_LIVECOMPONENTS.md#save-create-or-update)
- How does delete work for temp vs persisted? → [Sec 5: Delete](COOKBOOK_NESTED_LIVECOMPONENTS.md#delete)
- How do I add a child (grandchild) from the child LC? → [Sec 5: Add Grandchild](COOKBOOK_NESTED_LIVECOMPONENTS.md#add-grandchild-if-this-component-manages-a-nested-list)
- How does reorder work? → [Sec 5: Reorder](COOKBOOK_NESTED_LIVECOMPONENTS.md#reorder)

## Grandchild LiveComponent

- What's different about grandchild communication? → [Sec 6: Key Insight](COOKBOOK_NESTED_LIVECOMPONENTS.md#key-insight-direct-to-parent-communication)
- Should I use scoped messages (A) or callbacks (B)? → [Sec 6: Approaches](COOKBOOK_NESTED_LIVECOMPONENTS.md#communication-approaches)
- How does Approach A route by foreign key? → [Sec 6: Scoped Message](COOKBOOK_NESTED_LIVECOMPONENTS.md#approach-a-scoped-message-with-foreign-key-routing)
- How does Approach B use callbacks? → [Sec 6: Callback Function](COOKBOOK_NESTED_LIVECOMPONENTS.md#approach-b-callback-function-unified-parentchild)
- How does grandchild update/2 work? → [Sec 6: Grandchild update/2](COOKBOOK_NESTED_LIVECOMPONENTS.md#grandchild-update2-editing-guard)
- How does grandchild save with extra fields? → [Sec 6: Grandchild Save](COOKBOOK_NESTED_LIVECOMPONENTS.md#grandchild-save-private-helpers)
- How does grandchild delete handle temp vs persisted? → [Sec 6: Grandchild delete](COOKBOOK_NESTED_LIVECOMPONENTS.md#grandchild-save-private-helpers)
- How do I render grandchildren from the child LC? → [Sec 6: Render Pattern](COOKBOOK_NESTED_LIVECOMPONENTS.md#grandchild-render-pattern)

## Data Flow & Messages

- Walk me through the full event flow. → [Sec 8: Event Flow Diagram](COOKBOOK_NESTED_LIVECOMPONENTS.md#event-flow-diagram)
- What messages does my parent need to handle? → [Sec 8: Complete Message Table](COOKBOOK_NESTED_LIVECOMPONENTS.md#complete-message-table)
- What should never be sent in a message? → [Sec 8: What Never Gets Sent](COOKBOOK_NESTED_LIVECOMPONENTS.md#what-never-gets-sent)
- Show me all handler signatures at a glance. → [Sec 17: Handler Signatures](COOKBOOK_NESTED_LIVECOMPONENTS.md#handler-signatures-in-liveview)

## Reordering

- How does the Reorder module work? → [Sec 9: Context Module](COOKBOOK_NESTED_LIVECOMPONENTS.md#context-module-pure-logic)
- How does swap with position normalization work? → [Sec 9: swap](COOKBOOK_NESTED_LIVECOMPONENTS.md#context-module-pure-logic)
- How does the context expose reorder? → [Sec 9: Context Exposes](COOKBOOK_NESTED_LIVECOMPONENTS.md#how-the-context-exposes-it)
- How does the child trigger reorder? → [Sec 9: LiveComponent Triggers](COOKBOOK_NESTED_LIVECOMPONENTS.md#how-the-livecomponent-triggers-it)
- Why must the parent re-fetch after reorder? → [Sec 9: Parent Handles](COOKBOOK_NESTED_LIVECOMPONENTS.md#how-the-parent-liveview-handles-it-always-re-fetch-from-db)

## Optimistic UI & Temp Records

- How do temp records work? → [Sec 10: Temp ID Pattern](COOKBOOK_NESTED_LIVECOMPONENTS.md#the-temp-id-pattern)
- How do I detect temp records in a component? → [Sec 10: Detecting](COOKBOOK_NESTED_LIVECOMPONENTS.md#detecting-temp-records)
- How does the identity helper work? → [Sec 10: Identity Helper](COOKBOOK_NESTED_LIVECOMPONENTS.md#the-identity-helper)
- How do I reconcile temps on save? → [Sec 10: Reconciliation](COOKBOOK_NESTED_LIVECOMPONENTS.md#reconciliation-on-save)
- When should I show flash for temp operations? → [Sec 10: Flash Discipline](COOKBOOK_NESTED_LIVECOMPONENTS.md#flash-message-discipline)

## PubSub & Multi-User

- When do I need PubSub for this pattern? → [Sec 11.1: When PubSub](COOKBOOK_NESTED_LIVECOMPONENTS.md#111-when-pubsub-is-needed)
- How do I subscribe and handle broadcasts? → [Sec 11.2: Subscribing](COOKBOOK_NESTED_LIVECOMPONENTS.md#112-subscribing-and-handling-broadcasts)
- How do I protect user edits during broadcasts? → [Sec 11.3: Edit State Protection](COOKBOOK_NESTED_LIVECOMPONENTS.md#113-protecting-edit-state-during-broadcasts)
- How do temp records survive broadcasts? → [Sec 11.4: Temp Isolation](COOKBOOK_NESTED_LIVECOMPONENTS.md#114-temp-record-isolation)
- How do I handle edit conflicts (optimistic locking, etc.)? → [Sec 11.5: Conflict Resolution](COOKBOOK_NESTED_LIVECOMPONENTS.md#115-conflict-resolution-strategies)

## Error Recovery

- How do I keep the form open on validation error? → [Sec 12.1: Validation](COOKBOOK_NESTED_LIVECOMPONENTS.md#121-validation-error-recovery)
- How do I handle authorization failures? → [Sec 12.2: Auth Failure](COOKBOOK_NESTED_LIVECOMPONENTS.md#122-authorization-failure-recovery)
- How do I handle constraint violations? → [Sec 12.3: Constraint Violation](COOKBOOK_NESTED_LIVECOMPONENTS.md#123-constraint-violation-recovery)
- How do I handle network disconnection? → [Sec 12.4: Network](COOKBOOK_NESTED_LIVECOMPONENTS.md#124-network-disconnection-and-reconnection)
- What graceful degradation should I implement? → [Sec 12.5: Graceful](COOKBOOK_NESTED_LIVECOMPONENTS.md#125-graceful-degradation)

## LiveView Streams

- Should I use streams or direct assigns? → [Sec 7.7: Trade-offs](COOKBOOK_NESTED_LIVECOMPONENTS.md#77-streams-vs-direct-assigns-trade-off-analysis)
- How do streams work with LiveComponents? → [Sec 7.3: Streams with LCs](COOKBOOK_NESTED_LIVECOMPONENTS.md#73-streams-with-livecomponents)
- How do I find a record by stream_id? → [Sec 7.3: Strategy A/B](COOKBOOK_NESTED_LIVECOMPONENTS.md#73-streams-with-livecomponents)
- How do I CRUD with streams (insert, delete, reset)? → [Sec 7.4: Stream CRUD](COOKBOOK_NESTED_LIVECOMPONENTS.md#74-stream-based-crud-flow)
- How do I reorder with streams? → [Sec 7.5: Stream Reorder](COOKBOOK_NESTED_LIVECOMPONENTS.md#75-streams-and-reordering)
- How do I track idx/count with streams? → [Sec 7.6: idx/count](COOKBOOK_NESTED_LIVECOMPONENTS.md#76-streams-and-the-idx--count-pattern)

## Context Module

- What functions should my context module expose? → [Sec 13: Pattern](COOKBOOK_NESTED_LIVECOMPONENTS.md#pattern-for-a-context-module)
- How does the position helper work? → [Sec 13: Position Helper](COOKBOOK_NESTED_LIVECOMPONENTS.md#pattern-for-a-context-module)
- How does authorization chain work? → [Sec 13: Authorization Chain](COOKBOOK_NESTED_LIVECOMPONENTS.md#authorization-chain)
- What are the rules for context modules? → [Sec 13: Rules](COOKBOOK_NESTED_LIVECOMPONENTS.md#rules-for-the-context-module)

## No-Negotiables

- What rules can I never violate? → [Sec 14: All DO/DON'T](COOKBOOK_NESTED_LIVECOMPONENTS.md#14-no-negotiables-and-guardrails)
- What Phoenix 1.8 framework rules apply? → [Sec 14: Phoenix 1.8 Rules](COOKBOOK_NESTED_LIVECOMPONENTS.md#phoenix-v18-framework-rules)
- What process rules prevent common bugs? → [Sec 14: Process Rules](COOKBOOK_NESTED_LIVECOMPONENTS.md#process-rules-from-real-world-failures)

## Testing

- How should I structure tests? → [Sec 16: Testing Philosophy](COOKBOOK_NESTED_LIVECOMPONENTS.md#testing-philosophy)
- How do I test context module (create, reorder, auth)? → [Sec 16: Context Tests](COOKBOOK_NESTED_LIVECOMPONENTS.md#context-tests)
- How do I test LiveView interactions? → [Sec 16: LV Tests](COOKBOOK_NESTED_LIVECOMPONENTS.md#liveview-interaction-tests)
- How do I test stream-based lists? → [Sec 16: Stream Tests](COOKBOOK_NESTED_LIVECOMPONENTS.md#testing-stream-based-lists)
- How do I test PubSub-enabled LiveViews? → [Sec 16: PubSub Tests](COOKBOOK_NESTED_LIVECOMPONENTS.md#testing-pubsub-enabled-liveviews)

## Pitfalls (Debugging)

- My component remounts on every update — why? → [Pitfall 1: Remount](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-1-component-remounts-instead-of-updating)
- State accumulates across re-renders — fix? → [Pitfall 2: State Accumulation](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-2-components-accumulate-state)
- Grandchild messages get lost — why? → [Pitfall 3: Lost Messages](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-3-grandchild-messages-get-lost)
- Positions jump on reorder — fix? → [Pitfall 4: Jumping Positions](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-4-reorder-creates-jumping-or-duplicate-positions)
- Flash fires on temp delete — how to prevent? → [Pitfall 5: Temp Flash](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-5-flash-messages-on-temp-deletion)
- update/2 fires on every keystroke — what to do? → [Pitfall 6: Keystroke](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-6-update2-fires-on-every-keystroke)
- send_update can't reach my grandchild — why? → [Pitfall 7: Cross-Boundary](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-7-send_update3-targeting-across-component-boundaries)
- Parent shows stale data after reorder — fix? → [Pitfall 8: Stale Data](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-8-stale-parent-data-after-mutation-or-reorder)
- LiveView too big — how to know? → [Pitfall 9: Monolithic](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-9-monolithic-liveview-trying-to-handle-multiple-roles)
- PubSub overwrites my edit — how to protect? → [Pitfall 10: PubSub Overwrite](COOKBOOK_NESTED_LIVECOMPONENTS.md#pitfall-10-pubsub-broadcast-overwrites-users-in-progress-edits)

## Quick Reference

- Show me all handler signatures in one place. → [Sec 17: Handler Signatures](COOKBOOK_NESTED_LIVECOMPONENTS.md#handler-signatures-in-liveview)
- Show me the update/2 guard template. → [Sec 17: Update Guard Template](COOKBOOK_NESTED_LIVECOMPONENTS.md#component-update-guard-template)
- Show me a full implementation checklist. → [Sec 18: Implementation Checklist](COOKBOOK_NESTED_LIVECOMPONENTS.md#18-implementation-checklist)
