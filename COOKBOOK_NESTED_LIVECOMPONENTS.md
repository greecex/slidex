# Cookbook: Nested Dynamic Lists with Phoenix LiveView + LiveComponent

> **Target:** Phoenix LiveView v1.2+ (as included in Phoenix 1.8), Elixir 1.17+, Ecto 3+
>
> **Pattern:** Parent LiveView owns a dynamic list of child LiveComponents. Each child may contain
> a nested list of grandchild LiveComponents. Users add, edit, delete, and reorder items.
> Created from studying the [Slidex](https://github.com/greecex/slidex) polling application.
>
> **Use case template:** Any form where a user creates a record and needs inline dynamic
> sub-lists — quiz questions with options, invoices with line items, playlists with tracks,
> surveys with questions, etc.

---

## Table of Contents

1. [Overview and Concepts](#1-overview-and-concepts)
2. [Prerequisites and Setup](#2-prerequisites-and-setup)
3. [Architecture: The Golden Pattern](#3-architecture-the-golden-pattern)
4. [Parent LiveView: Owning the List](#4-parent-liveview-owning-the-list)
5. [Child LiveComponent: Self-Contained Item](#5-child-livecomponent-self-contained-item)
6. [Grandchild LiveComponent: Two Levels Deep](#6-grandchild-livecomponent-two-levels-deep)
7. [LiveView Streams for Dynamic Lists](#7-liveview-streams-for-dynamic-lists)
8. [Communication Contract](#8-communication-contract)
9. [The Reordering Pattern](#9-the-reordering-pattern)
10. [Optimistic UI with Temporary Records](#10-optimistic-ui-with-temporary-records)
11. [PubSub and Multi-User Coordination](#11-pubsub-and-multi-user-coordination)
12. [Error Recovery and Resilience](#12-error-recovery-and-resilience)
13. [The Context Module in Depth](#13-the-context-module-in-depth)
14. [No-Negotiables and Guardrails](#14-no-negotiables-and-guardrails)
15. [Common Pitfalls](#15-common-pitfalls)
16. [Testing the Pattern](#16-testing-the-pattern)
17. [Cheat Sheet: Messages Reference](#17-cheat-sheet-messages-reference)
18. [Implementation Checklist](#18-implementation-checklist)

---

## 1. Overview and Concepts

### The Problem

You have an Ecto schema with `has_many` associations (potentially nested). You need a UI where
a user can dynamically add, edit, delete, and reorder items within the parent — all on a single
page, without page reloads, with immediate visual feedback.

### The Solution

A three-layer architecture where each layer has a distinct responsibility:

```
┌──────────────────────────────────────────────────┐
│                   Parent LiveView                 │
│  - Source of truth for the list                   │
│  - Owns all data (fetched from DB)                │
│  - Handles CRUD by calling context functions      │
│  - Re-renders children by passing updated assigns │
│  - Receives child messages via handle_info/2      │
└───────────┬──────────────────────────┬────────────┘
            │ renders × N              │ renders × M
            ▼                          ▼
┌──────────────────────┐   ┌──────────────────────┐
│  Child LiveComponent  │   │  Child LiveComponent  │
│  - Owns its edit/view │   │  - ID: #item-{id}    │
│    state (editing,    │   │  - Handles own events │
│    search results)    │   │  - Sends messages up  │
│  - May render N       │   └──────────┬───────────┘
│    grandchild LCs     │              │ renders × K
│  - phx-target=@myself │              ▼
└──────────────────────┘   ┌──────────────────────┐
                           │ Grandchild LC          │
                           │  - Same pattern        │
                           │  - Sends messages up   │
                           └──────────────────────┘
```

### Key Insight

LiveComponents run **inside the LiveView process**. `self()` in a LiveComponent returns the
**LiveView PID**, not a component PID. This is what makes upward communication trivial:
`send(self(), {:some_message, payload})` from any depth reaches the parent LiveView's
`handle_info/2`.

### Core Principle

**The LiveView is always the source of truth for persisted data.** LiveComponents hold only
transient UI state (whether a form is in edit mode, search results, temporary IDs for optimistic
items). When a change needs to be persisted, the component sends a message up; the LiveView
calls the context, updates its assigns, and re-renders, which automatically updates the
component with the new data.

---

## 2. Prerequisites and Setup

Before you build a nested dynamic list, ensure your project meets these requirements and
understand the routing constraints.

### 2.1. Phoenix Version and Framework Requirements

| Requirement | Minimum Version | Notes |
|-------------|-----------------|-------|
| Phoenix | 1.8+ | Uses `Layouts.app` and scoped `live_session` |
| Elixir | 1.17+ | Pattern matching on binary IDs, new set-theoretic types |
| Ecto | 3.0+ | `has_many` with `on_delete: :delete_all` |
| phx.gen.auth | (included) | Provides `current_scope`, `live_session` scopes in router |

**Phoenix 1.8 changes relevant to this pattern:**

- Templates begin with `<Layouts.app flash={@flash} current_scope={@current_scope}>` which
  wraps all inner content. The `Layouts` module is aliased in `MyAppWeb`, so no import needed.
- The `<.flash_group>` component lives in `Layouts` — do **not** call it from other modules.
- `live_session` scopes in the router control authentication. Routes requiring login and
  routes that work without login must use separate `live_session` blocks (see below).
- App-wide template imports go in `my_app_web.ex`'s `html_helpers` block.

### 2.2. Router Configuration

Routes for this pattern must be placed in the correct `live_session` scope. The
`phx.gen.auth` generator creates these scopes:

**For routes that require authentication** (most common for this pattern):

```elixir
# lib/my_app_web/router.ex
scope "/", MyAppWeb do
  pipe_through [:browser, :require_authenticated_user]

  live_session :require_authenticated_user,
    on_mount: [{MyAppWeb.UserAuth, :require_authenticated}] do
    # Routes that require a logged-in user
    live "/polls/:id/questions", PollLive.Questions, :index
    live "/polls/:poll_id/questions/:id", PollLive.Questions, :show
  end
end
```

**For routes that work with or without authentication:**

```elixir
scope "/", MyAppWeb do
  pipe_through [:browser]

  live_session :current_user,
    on_mount: [{MyAppWeb.UserAuth, :mount_current_scope}] do
    # Routes that work either way
    live "/polls/:id", PollLive.Show, :show
  end
end
```

**Rules:**
- The `scope` provides an alias prefix. Do **not** duplicate it in route module names.
- A `live_session` name can only be defined **once**. All routes sharing the same scope
  must be in a single block.
- Controller routes must use the plug pipeline (`:require_authenticated_user`),
  not `live_session`.
- If you see `current_scope` errors, check the route is in the correct `live_session`
  and the correct pipeline.

### 2.3. Generating the Schema and Migration

Start with the Ecto schemas. Use `:binary_id` primary keys throughout:

```bash
mix phx.gen.schema Polling.Question questions \
  poll_id:references:polls \
  body:string \
  position:integer:default:0

mix phx.gen.schema Polling.Option options \
  question_id:references:questions \
  body:string \
  position:integer:default:0
```

Or generate migrations manually for more control:

```bash
mix ecto.gen.migration create_questions
mix ecto.gen.migration create_options
```

**Example migration for the child table:**

```elixir
# priv/repo/migrations/TIMESTAMP_create_questions.exs
defmodule MyApp.Repo.Migrations.CreateQuestions do
  use Ecto.Migration

  def change do
    create table(:questions, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :poll_id, references(:polls, type: :binary_id, on_delete: :delete_all),
        null: false
      add :body, :string, null: false
      add :position, :integer, null: false, default: 0

      timestamps(type: :utc_datetime_usec)
    end

    create index(:questions, [:poll_id])
    create index(:questions, [:position])
  end
end
```

**Key migration rules:**
- `primary_key: false` on the table, then `:binary_id, primary_key: true` on the id column
- `references(:parent, type: :binary_id, on_delete: :delete_all)` — database-level cascade
- Include `null: false` on foreign keys and required fields at the DB level
- Index both the foreign key and position for query performance

### 2.4. Application Setup Checklist

Before writing LiveView code, verify:

- [ ] `Layouts` module exists at `lib/my_app_web/components/layouts.ex` (generated by `phx.new`)
- [ ] `MyAppWeb` module's `html_helpers` block imports the components you need
- [ ] `mix ecto.create` and `mix ecto.migrate` succeed
- [ ] Router has the correct `live_session` scopes from `phx.gen.auth`
- [ ] `current_scope` assign flows through the socket for authenticated routes
- [ ] `~p` paths in templates resolve correctly

---

## 3. Architecture: The Golden Pattern

### Layer Responsibilities

| Layer | Owns | Never Does |
|-------|------|------------|
| **Parent LiveView** | The list data, DB operations, flash messages, PubSub subscriptions | Mutate child state directly; run per-item DB queries |
| **Child LiveComponent** | Transient UI state (editing, search results, form values), its own events via `phx-target={@myself}` | Call context modules directly (except for reads); mutate the parent's list |
| **Grandchild LiveComponent** | Same as child, one level deeper | Same as child |
| **Context Module** (e.g., `MyApp.Polling`) | All DB operations, authorization, reordering logic | LiveView state; template rendering |

### Data Flow Decision Tree

When designing a new list, answer these questions in order:

1. Is each item interactive (edit/delete/reorder)? → LiveComponent
2. Is there nesting (items within items)? → Each level gets its own LiveComponent
3. Does the list need live reordering? → Use a dedicated `Reorder` module
4. Do items need optimistic creation? → Use `temp_id` pattern
5. Do items need search/exclusion? → Pass as a callback assign

### File Structure Convention

```
lib/my_app_web/live/parent_live/
├── index.ex              # Parent LiveView (list owner)
├── form.ex               # Optional: parent create/edit form
├── show.ex               # Optional: parent detail
├── questions.ex          # OR: dedicated page for managing children
└── components/
    ├── child_live.ex     # Child LiveComponent
    └── grandchild_live.ex # Grandchild LiveComponent (if nested)
```

### Schema Pattern

```elixir
defmodule MyApp.Polling.Question do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "questions" do
    field :position, :integer, default: 0
    field :body, :string

    belongs_to :poll, MyApp.Campaigns.Poll
    has_many :options, MyApp.Polling.Option, on_delete: :delete_all

    timestamps(type: :utc_datetime_usec)
  end

  def changeset(question, attrs) do
    permitted = [:position, :body]
    required = [:body]

    question
    |> cast(attrs, permitted)
    |> validate_required(required)
    |> foreign_key_constraint(:poll_id)
    |> validate_length(:body, max: 500)
  end
end
```

**Rules:**
- Use `:binary_id` primary keys (UUIDv4) by default — URL-safe, no sequential guessing
- Programmatic fields (`position`, foreign keys) are set on the struct, **not** in `cast`
- The `position` field is an integer, default 0
- `on_delete: :delete_all` on the parent's `has_many` so deleting a parent cascades

### 3.5. The Preloader Strategy

Every time the parent LiveView needs the child list (on mount, after reorder, after
PubSub broadcast), it must fetch the parent WITH its children preloaded and ordered.
Centralize this logic in a dedicated `Preloader` module to avoid scattered Ecto queries:

```elixir
defmodule MyApp.Preloader do
  alias MyApp.{Campaigns, Repo}

  @doc """
  Eager-loads the full tree: parent → children → grandchildren, all ordered.
  """
  def with_preloads(%Ecto.Query{} = query) do
    query
    |> Repo.preload(children: {ordered_children(), [grandchildren: ordered_grandchildren()]})
  end

  def with_preloads(%struct_module{} = record) do
    Repo.preload(record, children: {ordered_children(), [grandchildren: ordered_grandchildren()]})
  end

  defp ordered_children do
    {from(c in Child, order_by: [asc: c.position, asc: c.inserted_at]), []}
  end

  defp ordered_grandchildren do
    from(g in Grandchild, order_by: [asc: g.position, asc: g.inserted_at])
  end
end
```

**Usage in the LiveView:**

```elixir
# On mount
parent =
  socket.assigns.current_scope
  |> Campaigns.get_parent!(parent_id)
  |> Preloader.with_preloads()

# After reorder (re-fetch from DB)
refreshed =
  socket.assigns.current_scope
  |> Campaigns.get_parent!(parent.id)
  |> Preloader.with_preloads()
```

**Why a Preloader module?**
- Single source of truth for the preload shape — one change propagates everywhere
- Guarantees consistent ordering (position, then inserted_at as tiebreaker)
- Handles both query and struct inputs transparently
- Avoids N+1 queries in templates — all data is loaded before rendering
- Easy to extend when new associations are added (e.g., `:attachments`)

**What gets preloaded:**
1. The parent record itself
2. All children, ordered by `position ASC, inserted_at ASC`
3. All grandchildren of each child, ordered by `position ASC, inserted_at ASC`
4. (Optional) Any additional associations the LiveComponents need for display

---

## 4. Parent LiveView: Owning the List

This is the LiveView that manages the collection. It fetches data, handles CRUD by calling the
context module, and renders child LiveComponents.

### Mount

```elixir
defmodule MyAppWeb.ParentLive.Questions do
  use MyAppWeb, :live_view

  alias MyApp.{Campaigns, Polling, Preloader}

  @impl true
  def mount(%{"id" => parent_id}, _session, socket) do
    parent =
      socket.assigns.current_scope
      |> Campaigns.get_parent!(parent_id)
      |> Preloader.with_preloads()  # Eager-loads children with ordering

    {:ok,
     socket
     |> assign(:parent, parent)
     |> assign(:children, parent.children)  # The list of child records
     |> assign(:page_title, "Manage Children")}
  end
end
```

**Key rule:** Always preload children with ordering on mount. The parent view should never
need to query per-child.

### Render

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  <.header>
    {@parent.title}
    <:actions>
      <.button phx-click="add_child">
        <.icon name="hero-plus" /> Add Child
      </.button>
    </:actions>
  </.header>

  <div class="space-y-3">
    <%= for {child, idx} <- Enum.with_index(@children) do %>
      <.live_component
        module={ChildLive}
        id={"child-#{child_id(child)}"}
        child={child}
        current_scope={@current_scope}
        parent={@parent}
        idx={idx}
        count={length(@children)}
      />
    <% end %>
  </div>
</Layouts.app>
```

**Critical details:**
- Each component gets a unique `id` based on the record's real or temporary ID
- Pass `idx` and `count` so the child can disable boundary reorder buttons
- Pass `current_scope` for authorization downstream
- The `child_id/1` helper must handle both real and temporary IDs:

```elixir
defp child_id(%{id: id}) when is_binary(id), do: id
defp child_id(%{temp_id: temp_id}), do: temp_id
defp child_id(_), do: Ecto.UUID.generate()
```

### Adding a Child (Optimistic)

```elixir
@impl true
def handle_event("add_child", _params, socket) do
  max_position = socket.assigns.children
    |> Enum.map(&Map.get(&1, :position, 0))
    |> Enum.max(fn -> 0 end)

  temp_child = %{
    temp_id: "temp_#{System.unique_integer([:positive])}",
    body: "",
    position: max_position + 1,
    editing: true          # <--- Transient flag, never persisted
  }

  children = List.insert_at(socket.assigns.children, -1, temp_child)
  {:noreply, assign(socket, :children, children)}
end
```

### Receiving Messages from Children

```elixir
# Child was persisted
@impl true
def handle_info({:child_created, saved_child, temp_id}, socket) do
  children = Enum.map(socket.assigns.children, fn c ->
    if Map.get(c, :temp_id) == temp_id, do: saved_child, else: c
  end)

  {:noreply,
   socket
   |> assign(:children, children)
   |> put_flash(:info, "Created")}
end

# Child was updated
def handle_info({:child_updated, updated_child}, socket) do
  children = Enum.map(socket.assigns.children, fn c ->
    if Map.get(c, :id) == updated_child.id, do: updated_child, else: c
  end)

  {:noreply,
   socket
   |> assign(:children, children)
   |> put_flash(:info, "Updated")}
end

# Child was deleted
def handle_info({:child_deleted, child_id}, socket) do
  children = Enum.reject(socket.assigns.children, fn c ->
    Map.get(c, :id) == child_id or Map.get(c, :temp_id) == child_id
  end)

  should_flash = not String.starts_with?(to_string(child_id), "temp_")

  {:noreply,
   socket
   |> (fn s -> if should_flash, do: put_flash(s, :info, "Deleted"), else: s end).()
   |> assign(:children, children)}
end

# Children were reordered
def handle_info({:children_reordered, parent}, socket) do
  refreshed =
    socket.assigns.current_scope
    |> Campaigns.get_parent!(parent.id)

  {:noreply,
   socket
   |> assign(:parent, refreshed)
   |> assign(:children, refreshed.children)}
end
```

**Message naming convention:** Use `:child_verb` tuples. For nested messages from
grandchildren, include the intermediate scope to target the right parent:

```elixir
# From grandchild, received by parent LiveView
def handle_info({:grandchild_created, new_grandchild, parent_child_id: parent_child_id, temp_id: temp_id}, socket) do
  # Find the child in the list by parent_child_id, update its grandchildren
  ...
end
```

### send_update/2: Targeted Parent-to-Child Updates

Sometimes the parent LiveView needs to push a change to a specific child LiveComponent
without re-rendering the entire list. `send_update/2` sends a message that triggers the
target component's `update/2` callback with new assigns:

```elixir
# In the parent LiveView — push a highlight to a specific child
def handle_info({:child_highlight, child_id}, socket) do
  send_update(ChildLive,
    id: "child-#{child_id}",
    highlighted: true
  )

  {:noreply, socket}
end
```

The child LiveComponent's `update/2` receives the new `highlighted` assign:

```elixir
def update(assigns, socket) do
  socket = assign(socket, assigns)

  socket =
    if assigns[:highlighted] do
      assign(socket, :highlight_class, "ring-2 ring-blue-500")
    else
      assign(socket, :highlight_class, "")
    end

  {:ok, socket}
end
```

**Rules for send_update/2:**
- Only works for components that are **direct children** of the calling LiveView's render tree
- The `id` must match the component's `id` in the template exactly
- Cannot reach into a grandchild from a LiveView if the grandchild is inside a child LC
  (see Pitfall 7). Instead, target the child LC, which then passes the update down
- It is NOT for child→parent communication — use `send(self(), msg)` for that

**send_update/2 is the right tool when:**
- You need to highlight one item after an external event (PubSub, async task)
- You want to toggle a single component's state without re-rendering siblings
- You're responding to a timer, animation trigger, or non-CRUD event

**send_update/2 is the WRONG tool when:**
- The child's data has changed in the database — update the parent's list assign instead
- You need to communicate upward — use `send(self(), msg)`
- You need to update a grandchild across component boundaries — use the callback pattern

### Phoenix 1.8 Layouts Template Structure

The render template for the parent LiveView uses `<Layouts.app>` as the root element,
which is a Phoenix 1.8 requirement:

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  ...
</Layouts.app>
```

The `Layouts` module is automatically aliased in `MyAppWeb`'s `html_helpers` block
(generated by `phx.new`). The `current_scope` assign comes from `phx.gen.auth`'s
`on_mount` hooks. If you generated your app with an older Phoenix version, ensure
your layouts module follows Phoenix 1.8 conventions.

---

## 5. Child LiveComponent: Self-Contained Item

Each item in the list is a LiveComponent. It manages its own transient state (editing mode,
form values, search results) and sends messages upward when it needs the parent to persist
something.

### The Component

```elixir
defmodule MyAppWeb.ParentLive.Components.ChildLive do
  use MyAppWeb, :live_component

  alias MyApp.{Polling, Search}

  @impl true
  def mount(socket) do
    {:ok,
     socket
     |> assign(:editing, false)
     |> assign(:body, "")
     |> assign(:results, [])
     |> assign(:show_results, false)}
  end

  @impl true
  def update(assigns, socket) do
    child = assigns.child
    is_temporary = Map.has_key?(child, :temp_id)
    body = child.body || ""
    editing = assigns[:editing] || is_temporary || body == ""

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:is_temporary, is_temporary)
     |> assign(:editing, editing)
     |> assign(:body, body)}
  end
end
```

### Update Logic

The `update/2` callback is called every time the parent re-renders. This is where you
synchronize the component's local state with the parent's assigns.

**Critical rule:** `update/2` is **not** only for initialization. It fires on every parent
re-render. Your `update/2` must be idempotent — calling it with the same assigns must
produce the same result.

```elixir
def update(assigns, socket) do
  # Always merge fresh parent assigns
  socket = assign(socket, assigns)

  # Only overwrite local state if the component isn't currently being edited
  # (otherwise the user loses their unsaved work)
  socket =
    if socket.assigns.editing do
      socket  # Preserve local edit state
    else
      socket
      |> assign(:body, assigns.child.body || "")
      |> assign(:editing, Map.has_key?(assigns.child, :temp_id))
    end

  {:ok, socket}
end
```

#### Preserving State with assign_new/3

`assign_new/3` is an alternative to the manual editing-guard pattern. It sets an assign
only if it is NOT already set on the socket. This is useful for values that should survive
across parent re-renders but be initialized on mount:

```elixir
def update(assigns, socket) do
  socket = assign(socket, assigns)

  # Only set :body if it hasn't been set yet (e.g., on first render)
  socket = assign_new(socket, :body, fn -> assigns.child.body || "" end)

  # :editing starts false, then changes via user interaction
  socket = assign_new(socket, :editing, fn ->
    Map.has_key?(assigns.child, :temp_id)
  end)

  {:ok, socket}
end
```

`assign_new/3` is useful when the LiveComponent renders child LiveComponents of its own
and you want those grandchildren to keep their state across update cycles. However, for
the basic editing-guard pattern, the explicit `if socket.assigns.editing` check is more
reliable because it handles the case where the parent intentionally resets a child's
state (e.g., after a "cancel edit" action).

**Rule of thumb:** Use `assign_new/3` for initialization-only assigns (default values,
derived data). Use the `editing` guard pattern for user-edit state that must survive
parent re-renders.

### Handling Events

All component events use `phx-target={@myself}` so events reach the component, not the
parent LiveView.

```heex
<.button
  type="button"
  phx-click="edit"
  phx-target={@myself}
>
  Edit
</.button>

<.button
  type="button"
  phx-click="delete"
  phx-target={@myself}
>
  Delete
</.button>
```

### Save (Create or Update)

```elixir
@impl true
def handle_event("save", _params, socket) do
  body = String.trim(socket.assigns.body || "")

  cond do
    body == "" ->
      {:noreply, put_flash(socket, :error, "Body cannot be empty")}

    socket.assigns.is_temporary ->
      # Creating a new persisted record
      case Polling.create_child(socket.assigns.current_scope, socket.assigns.parent, %{body: body}) do
        {:ok, saved} ->
          temp_id = Map.get(socket.assigns.child, :temp_id)
          send(self(), {:child_created, saved, temp_id})  # <--- message to parent LV
          {:noreply, clear_edit(socket)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not save")}
      end

    true ->
      # Updating an existing record
      case Polling.update_child(socket.assigns.current_scope, socket.assigns.child, %{body: body}) do
        {:ok, updated} ->
          send(self(), {:child_updated, updated})  # <--- message to parent LV
          {:noreply, clear_edit(socket)}

        {:error, _changeset} ->
          {:noreply, put_flash(socket, :error, "Could not update")}
      end
  end
end
```

### Delete

```elixir
@impl true
def handle_event("delete", _params, socket) do
  if socket.assigns.is_temporary do
    send(self(), {:child_deleted, socket.assigns.child.temp_id})
  else
    Polling.delete_child(socket.assigns.current_scope, socket.assigns.child)
    send(self(), {:child_deleted, socket.assigns.child.id})
  end

  {:noreply, socket}
end
```

### Reorder

```elixir
@impl true
def handle_event("reorder", %{"direction" => direction}, socket) do
  direction = String.to_existing_atom(direction)

  Polling.reorder(socket.assigns.current_scope, socket.assigns.child, direction)
  send(self(), {:children_reordered, socket.assigns.parent})

  {:noreply, socket}
end
```

---

## 6. Grandchild LiveComponent: Two Levels Deep

This is where the pattern extends: a LiveComponent that renders its own list of child
LiveComponents. The same principles apply, but now the communication has a direct path:

```
Grandchild LC ──send(self(), ...)──► Parent LiveView (direct, one hop)
```

### Key Insight: Direct-to-Parent Communication

A grandchild LiveComponent's `self()` returns the **parent LiveView PID** (not a component PID).
This means `send(self(), ...)` from ANY depth reaches the LiveView directly:

```
Grandchild LC ──send(self(), {:grandchild_created, ...})──► Parent LiveView
                                                            (direct, not via Child LC)
```

This is critical to understand: messages from grandchildren do NOT route through the
intermediate child LiveComponent. They arrive at the LiveView in one hop. The LiveView
then uses the foreign key in the message to determine which child's sub-list to update.

### Communication Approaches

There are two approaches for handling grandchild communication. Choose based on your
nesting depth and component reuse needs:

### Approach A: Scoped Message with Foreign Key Routing

The grandchild sends a message to the parent LiveView (via `send(self(), ...)`), including
enough context for the parent to identify which child's sub-list to update:

```elixir
# In GrandchildLive — uses generic naming; substitute your domain names
def handle_event("save", _params, socket) do
  scope = socket.assigns.current_scope
  parent_child = socket.assigns.parent_child  # the child LC's record

  case Polling.create_grandchild(scope, parent_child, attrs) do
    {:ok, persisted_grandchild} ->
      send(self(), {:grandchild_created, persisted_grandchild,
                    parent_child_id: parent_child.id,
                    temp_id: socket.assigns.grandchild.temp_id})
      # ^ reaches the parent LiveView directly, NOT the child LC

    {:error, _changeset} ->
      {:noreply, put_flash(socket, :error, "Could not save")}
  end
end
```

The parent LiveView (not the child LiveComponent) handles the message and uses the
foreign key (`parent_child_id`) to find which child's sub-list to update:

```elixir
# In the parent LiveView
def handle_info({:grandchild_created, new_grandchild, opts}, socket) do
  parent_child_id = opts[:parent_child_id]
  temp_id = opts[:temp_id]

  children = Enum.map(socket.assigns.children, fn child ->
    if child.id == parent_child_id do
      grandkids = child.grandchildren || []
      updated_grandkids =
        grandkids
        |> Enum.reject(fn g -> Map.get(g, :temp_id) == temp_id end)
        |> Kernel.++([new_grandchild])

      %{child | grandchildren: updated_grandkids}
    else
      child
    end
  end)

  {:noreply, assign(socket, :children, children)}
end
```

This works because the parent LiveView owns the entire data tree. Messages from any depth
reach it, and it uses the foreign key included in the message to determine where they belong.

> **Domain naming note:** In your application, substitute your actual schema names.
> For example, if your domain is questions-with-options:
> - `parent_child` → `question`
> - `grandchild` → `option`
> - `parent_child_id` → `question_id`
> - `Polling.create_grandchild` → `Polling.create_option`
> - `:grandchild_created` → `:option_created`
>
> The pattern is identical; only the names change. Choose naming early in your
> design and use consistently throughout.

### Approach B: Callback Function (Unified Parent/Child)

As recommended by Phoenix core, pass a callback function that each level implements
differently:

```elixir
# In the grandchild LiveComponent
def handle_event("save", _params, socket) do
  socket.assigns.on_saved.(%{body: body, temp_id: temp_id})
  {:noreply, socket}
end
```

When rendered from a **LiveView**:
```heex
<.live_component
  module={GrandchildLive}
  id={...}
  on_saved={fn data -> send(self(), {:grandchild_saved, data}) end}
/>
```

When rendered from a **LiveComponent**:
```heex
<.live_component
  module={GrandchildLive}
  id={...}
  on_saved={fn data -> send_update(@myself, grandchild_saved: data) end}
/>
```

**Recommendation:** For 2-level nesting (LiveView → Child LC → Grandchild LC),
Approach A (scoped messages) is simpler and more explicit. For reusable components
that might be mounted anywhere (varying parent context), use Approach B. For 3+ levels
of nesting (LiveView → LC → LC → LC), Approach B scales better because each level
doesn't need to know its parent's parent's structure.

### Grandchild Render Pattern

```elixir
<%= for {grandchild, idx} <- Enum.with_index(@options) do %>
  <.live_component
    module={GrandchildLive}
    id={"grandchild-#{grandchild_id(grandchild)}"}
    grandchild={grandchild}
    current_scope={@current_scope}
    parent_child={@child}        # <--- so grandchild knows its parent
    idx={idx}
    count={length(@options)}
  />
<% end %>
```

---

## 7. LiveView Streams for Dynamic Lists

LiveView streams are the preferred mechanism for managing dynamic lists in Phoenix 1.7+.
They avoid full-list re-renders by sending targeted DOM patches for insert, update, delete,
and reorder operations. This section explains how to integrate streams with the
LiveComponent pattern.

### 7.1. Why Streams

When you store the list in a regular assign (`@children`) and re-render the entire list on
every change, the LiveView sends the full HTML for every child component over the WebSocket.
For small lists (< 20 items) this is fine. For larger lists, or lists that change frequently,
streams are drastically more efficient:

- **Insert:** Only the new item's HTML is sent
- **Delete:** Only the removed item is removed from the DOM
- **Reorder:** Items are moved in the DOM without re-rendering
- **Update:** Only the changed item is patched

### 7.2. Stream Operations

```elixir
# ── On mount: initialize the stream ──
{:ok,
 socket
 |> assign(:parent, parent)
 |> stream(:children, parent.children)}  # Same as stream(socket, :children, parent.children)

# ── Add a temp record ──
temp_child = %{
  temp_id: "temp_#{System.unique_integer([:positive])}",
  body: "",
  position: next_position,
  editing: true
}

{:noreply, stream_insert(socket, :children, temp_child, at: -1)}  # at: -1 = prepend

# ── Replace temp with persisted ──
# 1. Delete the temp record from the stream
socket = stream_delete(socket, :children, fn
  {_id, %{temp_id: tid}} -> tid == temp_id
  _ -> false
end)
# 2. Insert the persisted record at its correct position
{:noreply, stream_insert(socket, :children, saved_child)}

# ── Delete a record ──
{:noreply, stream_delete(socket, :children, child_to_delete)}

# ── Reset the stream (e.g., after filter or re-fetch) ──
{:noreply, stream(socket, :children, fresh_children, reset: true)}
```

### 7.3. Streams with LiveComponents

The template uses the `@streams.children` collection and requires `phx-update="stream"`:

```heex
<div id="children" phx-update="stream">
  <div :for={{stream_id, child} <- @streams.children} id={stream_id}>
    <.live_component
      module={ChildLive}
      id={stream_id}
      child={child}
      current_scope={@current_scope}
      parent={@parent}
    />
  </div>
</div>
```

**Critical rule:** The LiveComponent `id` MUST match the stream's DOM `id`. Since the
stream assigns `stream_id` (which is the DOM id), you pass it directly as the
LiveComponent's `id`. This ensures the component is updated in place rather than remounted.

Because the `id` is now the stream's opaque identifier (not the database ID), you need
a way to look up the child record by stream id inside message handlers. There are two
strategies:

**Strategy A — Store a stream_id map in the socket:**

```elixir
def mount(%{"id" => parent_id}, _session, socket) do
  parent = Campaigns.get_parent!(current_scope, parent_id) |> Preloader.with_preloads()

  # Build a reverse map: stream_id → child record
  stream_id_map = Map.new(parent.children, fn child ->
    {Phoenix.LiveView.stream_id(:children, child), child.id}
  end)

  {:ok,
   socket
   |> assign(:parent, parent)
   |> assign(:stream_id_map, stream_id_map)
   |> stream(:children, parent.children)}
end
```

**Strategy B — Include the database id in the message from the child component:**

```elixir
# In ChildLive
def handle_event("save", _params, socket) do
  # ... persist ...
  send(self(), {:child_updated, updated_child, socket.assigns.child.id})
end

# In parent LiveView
def handle_info({:child_updated, updated_child, child_id}, socket) do
  # Update the stream in place
  {:noreply, stream_insert(socket, :children, updated_child, at: find_position(socket, child_id))}
end
```

**Recommendation:** Strategy B is simpler for most cases. Strategy A is useful when you
need to batch-operate on the stream from the LiveView side.

### 7.4. Stream-Based CRUD Flow

```elixir
# ── Add ──
def handle_event("add_child", _params, socket) do
  max_pos = socket.assigns.children
    |> Enum.map(&Map.get(&1, :position, 0))
    |> Enum.max(fn -> 0 end)

  temp_child = %{
    temp_id: "temp_#{System.unique_integer([:positive])}",
    body: "",
    position: max_pos + 1,
    editing: true
  }

  {:noreply, stream_insert(socket, :children, temp_child, at: -1)}
end

# ── Replace temp with saved ──
def handle_info({:child_created, saved, temp_id}, socket) do
  socket =
    socket
    |> stream_delete(:children, fn
      {_id, %{temp_id: tid}} -> tid == temp_id
      _ -> false
    end)
    |> stream_insert(:children, saved)

  {:noreply, put_flash(socket, :info, "Created")}
end

# ── Delete ──
def handle_info({:child_deleted, child_id}, socket) do
  socket = stream_delete(socket, :children, fn
    {_id, %{id: id}} -> id == child_id
    {_id, %{temp_id: tid}} -> tid == child_id
    _ -> false
  end)

  should_flash? = not String.starts_with?(to_string(child_id), "temp_")
  {:noreply, if(should_flash?, do: put_flash(socket, :info, "Deleted"), else: socket)}
end
```

**The `stream_delete/3` with filter function** is essential: it lets you delete by
matching on the record's content (id or temp_id) rather than requiring the exact
stream_id value.

### 7.5. Streams and Reordering

With streams, reordering can be done client-side by moving the DOM element, or server-side
by resetting the stream. The simplest approach after a DB reorder:

```elixir
def handle_info({:children_reordered, parent}, socket) do
  refreshed =
    socket.assigns.current_scope
    |> Campaigns.get_parent!(parent.id)
    |> Preloader.with_preloads()

  {:noreply,
   socket
   |> assign(:parent, refreshed)
   |> stream(:children, refreshed.children, reset: true)}
end
```

When you call `stream(..., reset: true)`, the LiveView sends the minimal set of DOM
operations (move existing elements, insert new, delete removed) rather than re-rendering
everything. This is still far more efficient than re-rendering the full list as assigns.

### 7.6. Streams and the idx / count Pattern

When using streams, `Enum.with_index` is not available on the stream collection directly.
Instead, pass `idx` and `count` as explicit assigns on mount and update them alongside
stream operations:

```elixir
# On mount
{:ok,
 socket
 |> assign(:children_count, length(parent.children))
 |> stream(:children, parent.children)}

# On insert
{:noreply,
 socket
 |> assign(:children_count, socket.assigns.children_count + 1)
 |> stream_insert(socket, :children, new_child)}

# On delete
{:noreply,
 socket
 |> assign(:children_count, socket.assigns.children_count - 1)
 |> stream_delete(socket, :children, child)}
```

For the child component, render with a separate `idx` assign computed from the stream
enumerate:

```heex
<div id="children" phx-update="stream">
  <div :for={{stream_id, child} <- @streams.children} id={stream_id}>
    {child.position}
    <.live_component
      module={ChildLive}
      id={stream_id}
      child={child}
      idx={child.position}
      count={@children_count}
      ...
    />
  </div>
</div>
```

### 7.7. Streams vs Direct Assigns: Trade-off Analysis

| Aspect | Direct Assigns | Streams |
|--------|---------------|---------|
| **List size limit** | Up to ~50 items before perf degrades | Hundreds of items |
| **Re-render cost** | Full list re-render on every change | Targeted DOM patches only |
| **Code complexity** | Lower — simpler pattern | Higher — stream_id tracking needed |
| **idx/count access** | `Enum.with_index(@children)` | Manual count assign |
| **reorder_ui** | Full re-render | DOM element moves |
| **Error handling** | Direct Enum access | Filter function on stream_delete |
| **Templating** | Standard for-comprehension | Stream-comprehension with phx-update |
| **Backward compat** | Works since Phoenix 1.0 | Requires Phoenix 1.7+ |

**Recommendation:** Use **direct assigns** for prototyping, short-lived forms, or when
you know the list will stay small (< 20 items). Use **streams** for production lists
that users will grow, reorder frequently, or work with on mobile connections.

You can also start with direct assigns during development and refactor to streams
later — the data flow is identical, only the socket operations change.

---

This is the complete specification of how messages flow. Every message is documented with
its direction, trigger, and handler.

## 8. Communication Contract

### Event Flow Diagram

```
User clicks "Add" in LV
  → handle_event("add_child", _, socket) in Parent LV
  → Creates temp record in @children assign
  → Re-render shows new ChildLC in edit mode

User types in ChildLC form
  → handle_event("search", %{"body" => val}, socket) in ChildLC
  → Updates local assigns (body, results)
  → No message to parent (transient UI state)

User clicks "Save" in ChildLC
  → handle_event("save", _, socket) in ChildLC
  → Calls Polling.create_child/3
  → send(self(), {:child_created, saved, temp_id})
  → Parent LV's handle_info({:child_created, ...})
  → Replaces temp record with persisted record in @children
  → Re-render pushes updated child to ChildLC

User clicks "Delete" in ChildLC
  → handle_event("delete", _, socket) in ChildLC
  → If temp: send(self(), {:child_deleted, temp_id})
  → If persisted: Polling.delete_child/2, send({:child_deleted, id})
  → Parent LV removes from @children

User clicks reorder ▲/▼ in ChildLC
  → handle_event("reorder", %{"direction" => dir}, socket) in ChildLC
  → Polling.reorder/3 (atomic DB operation)
  → send(self(), {:children_reordered, parent})
  → Parent LV re-fetches list from DB
```

### Complete Message Table

| Message | Sender | Receiver | When |
|---------|--------|----------|------|
| `{:child_created, saved_record, temp_id}` | ChildLC | Parent LV (via `send`) | Temp record persisted to DB |
| `{:child_updated, updated_record}` | ChildLC | Parent LV (via `send`) | Existing record updated |
| `{:child_deleted, child_id}` | ChildLC | Parent LV (via `send`) | Record or temp removed |
| `{:children_reordered, parent_record}` | ChildLC | Parent LV (via `send`) | Reorder completed |
| `{:grandchild_created, record, opts}` | GrandchildLC | Parent LV (via `send`) | Grandchild persisted |
| `{:grandchild_updated, record}` | GrandchildLC | Parent LV (via `send`) | Grandchild updated |
| `{:grandchild_deleted, id}` | GrandchildLC | Parent LV (via `send`) | Grandchild removed |
| `{:grandchildren_reordered, parent_child}` | GrandchildLC | Parent LV (via `send`) | Grandchild reordered |

For all grandchild messages, the parent LiveView must include the foreign key in the message
payload (e.g., `question_id`) to know which child's list to update.

### What Never Gets Sent

- **Temp records never reach the DB.** They exist only in the LiveView assign.
- **UI state (editing, show_results) never leaves the component.** It is local transient state.
- **Flash messages are never sent by components.** The parent LiveView sets flash when it
  receives the message.

---

## 9. The Reordering Pattern

Reordering is one of the hardest parts to get right. Here is the pattern that works.

> ⚠️ **Common mistake:** The parent LiveView receives a stale struct from the child message
> and tries to preload new data from it. Always re-fetch from the database instead.
> See Pitfall 8 in section 15.

### Context Module (Pure Logic)

```elixir
defmodule MyApp.Polling.Reorder do
  import Ecto.Query
  alias MyApp.{Accounts, Authorization, Repo}

  @doc """
  Moves a record one step higher or lower within its parent scope.
  Re-normalizes positions afterward for stability.
  """
  def move(%Accounts.Scope{} = scope, record, direction)
      when direction in [:higher, :lower] do
    :ok = Authorization.authorize(scope, record)
    siblings = siblings(record)
    current_index = Enum.find_index(siblings, &(&1.id == record.id))
    new_index = new_index(current_index, direction, length(siblings))

    if is_nil(new_index) do
      {:ok, :unchanged}
    else
      swap(current_index, new_index, siblings)
    end
  end

  defp siblings(record) do
    record
    |> by_parent_id()
    |> order_by([r], asc: r.position, asc: r.inserted_at)
    |> Repo.all()
  end

  defp by_parent_id(%MyApp.Polling.Question{} = q),
    do: where(MyApp.Polling.Question, [r], r.poll_id == ^q.poll_id)

  defp by_parent_id(%MyApp.Polling.Option{} = o),
    do: where(MyApp.Polling.Option, [r], r.question_id == ^o.question_id)

  defp new_index(nil, _direction, _len), do: nil
  defp new_index(0, :higher, _len), do: nil
  defp new_index(i, :higher, _len), do: i - 1
  defp new_index(i, :lower, len) when i == len - 1, do: nil
  defp new_index(i, :lower, _len), do: i + 1

  defp swap(current, new, siblings) do
    {moved, rest} = List.pop_at(siblings, current)
    reordered = List.insert_at(rest, new, moved)

    Repo.transaction(fn ->
      reordered
      |> Enum.with_index()
      |> Enum.each(fn {record, index} ->
        if record.position != index do
          record
          |> Ecto.Changeset.change(position: index)
          |> Repo.update!()
        end
      end)
    end)

    {:ok, :reordered}
  end
end
```

**Key design decisions:**
- Atomic transaction: positions are always clean (0, 1, 2, ...) after every operation
- Authorization checked before any DB work
- Edge cases handled: first item can't go higher, last item can't go lower
- Fallback ordering by `inserted_at` as tiebreaker for siblings with same position

### How the Context Exposes It

```elixir
defmodule MyApp.Polling do
  defdelegate reorder(scope, record, direction),
    to: Reorder,
    as: :move
end
```

### How the LiveComponent Triggers It

```elixir
@impl true
def handle_event("reorder", %{"direction" => direction}, socket) do
  direction = String.to_existing_atom(direction)
  Polling.reorder(socket.assigns.current_scope, socket.assigns.child, direction)
  send(self(), {:children_reordered, socket.assigns.parent})
  {:noreply, socket}
end
```

### How the Parent LiveView Handles It (Always Re-fetch from DB)

```elixir
@impl true
def handle_info({:children_reordered, parent}, socket) do
  refreshed =
    socket.assigns.current_scope
    |> Campaigns.get_parent!(parent.id)
    |> Preloader.with_preloads()

  {:noreply,
   socket
   |> assign(:parent, refreshed)
   |> assign(:children, refreshed.children)}
end
```

> ⚠️ **Critical rule: Always re-fetch from the database. Never use the struct passed in the message for anything beyond identity lookup.**

The parent re-fetches the entire parent record with preloaded, sorted children. This is
the safest approach — it guarantees the order matches the database. The `parent` value
in the message is only used to get the parent's ID, not the parent's data.

**Why the struct in the message is stale:** The LiveComponent called `Reorder.move/3`
which committed a DB transaction. The `parent` struct the component had in its assigns
was loaded **before** the transaction. Using it directly would show the old order.
Even running a preloader on the stale struct is wrong — the struct's
associations are stale too. Only a fresh DB query reveals the new state.

**Performance note:** For small lists (< 100 items) this is fine. For larger lists, you
could optimize by only re-fetching the children list instead of the whole parent. The
principle is the same: re-query, don't reuse.

---

## 10. Optimistic UI with Temporary Records

### The Temp ID Pattern

When a user adds a new item, we don't want to show a loading spinner. Instead, we:

1. Create a temporary map (not an Ecto struct) with a `temp_id`
2. Insert it into the list in the LiveView assign
3. The LiveComponent sees it, enters edit mode automatically
4. On save, the component calls the context to persist
5. The parent replaces the temp record with the persisted one

```elixir
# Creating a temp record
temp_child = %{
  temp_id: "temp_#{System.unique_integer([:positive])}",
  body: "",
  position: max_position + 1,
  editing: true   # <--- Transient UI state, never persisted
}
```

**Rules for temp IDs:**
- Use a distinguishable prefix: `"temp_"`, `"temp_child_"`, etc.
- Use `System.unique_integer([:positive])` for uniqueness — it is process-local and fast
- Never persist a temp ID to the database
- The child LiveComponent checks `Map.has_key?(assigns.child, :temp_id)` to detect temp records
- **Always set `position` on the temp record** from the start. Deferring position assignment
  to save-time causes ordering corruption when multiple items are added before any save.
  Temp records created without position will sort to the wrong place in the list.

### Detecting Temp Records

```elixir
# In the component
is_temporary = Map.has_key?(assigns.child, :temp_id)
```

### The Identity Helper

Every component needs a stable identity function that works for both real and temp IDs:

```elixir
defp child_id(%{id: id}) when is_binary(id), do: id
defp child_id(%{temp_id: temp_id}), do: temp_id
defp child_id(_), do: Ecto.UUID.generate()
```

This is used for:
- The component's `id` attribute (e.g., `"child-#{child_id(child)}"`)
- Matching messages from children (both `:id` and `:temp_id` can appear in messages)

### Reconciliation on Save

```elixir
# In the parent LiveView
def handle_info({:child_created, saved, temp_id}, socket) do
  # Replace temp entry with persisted entry
  children = Enum.map(socket.assigns.children, fn c ->
    if Map.get(c, :temp_id) == temp_id, do: saved, else: c
  end)

  {:noreply, assign(socket, :children, children)}
end

def handle_info({:child_deleted, child_id}, socket) do
  # Remove by either real ID or temp_id
  children = Enum.reject(socket.assigns.children, fn c ->
    Map.get(c, :id) == child_id or Map.get(c, :temp_id) == child_id
  end)

  {:noreply, assign(socket, :children, children)}
end
```

### Flash Message Discipline

- Temporary operations (creating a temp record, deleting a temp) → no flash
- Persisted operations (record created, updated, deleted in DB) → flash
- This is controlled by checking if the `child_id` starts with `"temp_"`:

```elixir
should_flash? = not String.starts_with?(to_string(child_id), "temp_")
```

---

## 11. PubSub and Multi-User Coordination

When multiple users interact with the same parent record (e.g., a collaborative poll editor,
a shared invoice), PubSub broadcasts from other sessions can trigger LiveView re-renders
while a user is editing. This section explains how to handle those conflicts.

### 11.1. When PubSub Is Needed

Subscribe the parent LiveView to a topic when:

- Other users can modify the same parent record or its children
- The same user has the parent open in multiple browser tabs
- Background processes (jobs, webhooks) update the record
- You need real-time synchronization between presenter and participant views

### 11.2. Subscribing and Handling Broadcasts

```elixir
# In the parent LiveView mount
def mount(%{"id" => parent_id}, _session, socket) do
  parent = Campaigns.get_parent!(current_scope, parent_id) |> Preloader.with_preloads()

  if socket.assigns.live_action in [:edit, :manage_children] do
    Phoenix.PubSub.subscribe(MyApp.PubSub, "parent:#{parent.id}")
  end

  {:ok,
   socket
   |> assign(:parent, parent)
   |> assign(:children, parent.children)
   |> assign(:subscribed?, true)}
end

# Handle broadcast from another session
@impl true
def handle_info({:parent_updated, updated_parent_id}, socket) do
  # Only re-fetch if we're not in the middle of editing
  if socket.assigns.editing_in_progress do
    # Queue the update for later
    {:noreply, assign(socket, :pending_refresh, true)}
  else
    refreshed =
      socket.assigns.current_scope
      |> Campaigns.get_parent!(updated_parent_id)
      |> Preloader.with_preloads()

    {:noreply,
     socket
     |> assign(:parent, refreshed)
     |> assign(:children, refreshed.children)}
  end
end
```

### 11.3. Protecting Edit State During Broadcasts

The `update/2` callback in LiveComponents fires on every parent re-render — including
re-renders triggered by PubSub broadcasts from other users. If the user is in the middle
of editing a form, this can overwrite their unsaved input.

```elixir
# In the child LiveComponent
@impl true
def update(assigns, socket) do
  socket = assign(socket, assigns)

  # CRITICAL: preserve local edit state across PubSub-triggered re-renders
  socket =
    if socket.assigns.editing do
      socket  # Keep the user's unsaved input
    else
      socket
      |> assign(:body, assigns.child.body || "")
      |> assign(:editing, Map.has_key?(assigns.child, :temp_id))
    end

  {:ok, socket}
end
```

### 11.4. Temp Record Isolation

Temp records are process-local — they exist only in one LiveView's assign/stream. When a
PubSub broadcast arrives:

1. The LiveView re-fetches the parent and children from the DB
2. The new children list **does not include** temp records from this session
3. But temp records are still in the LiveView's assign/stream
4. The `update/2` callback fires for each child component, including temp ones

**This is fine** because:
- Temp records are maps, not Ecto structs, so `Map.has_key?(child, :temp_id)` still works
- The temp record's `update/2` preserves the editing state
- The temp record stays in the list until explicitly replaced or deleted

```elixir
# Safe approach: merge broadcast data with current temp records
def handle_info({:parent_updated, _id}, socket) do
  refreshed = fetch_parent(socket.assigns.current_scope, socket.assigns.parent.id)

  # Preserve temp records that are still being edited
  temp_records = Enum.filter(socket.assigns.children, fn c ->
    Map.has_key?(c, :temp_id)
  end)

  merged = temp_records ++ (refreshed.children -- temp_records)

  {:noreply,
   socket
   |> assign(:parent, refreshed)
   |> assign(:children, merged)}
end
```

### 11.5. Conflict Resolution Strategies

| Scenario | Strategy |
|----------|----------|
| Two users edit same child | Last-writer-wins (server timestamp). Display "refreshed" flash |
| User is editing while broadcast arrives | Defer refresh via `:pending_refresh` flag. Apply on next user event |
| Temp record conflicts with broadcast delete | Temp delete wins (user's intent). The broadcast data is stale anyway |
| Reorder conflict between users | DB transaction wins. Both see the result after reorder completes |
| User saves after stale broadcast | Context module's authorization and optimistic locking catch conflicts |

**Optimistic locking with Ecto:**

```elixir
defmodule MyApp.Polling.Child do
  use Ecto.Schema

  schema "children" do
    field :body, :string
    field :position, :integer
    field :lock_version, :integer, default: 1  # For optimistic locking

    belongs_to :parent, MyApp.Parents.Parent
    timestamps()
  end

  def changeset(child, attrs) do
    child
    |> cast(attrs, [:body, :lock_version])
    |> optimistic_lock(:lock_version)
    |> validate_required([:body])
  end
end
```

Add the `lock_version` column to your migration:

```elixir
alter table(:children) do
  add :lock_version, :integer, null: false, default: 1
end
```

---

## 12. Error Recovery and Resilience

A robust nested list UI must handle failures gracefully — validation errors, authorization
denials, database constraint violations, and network interruptions should never leave the
user confused or lose their input.

### 12.1. Validation Error Recovery

When a `changeset` validation fails, the component should keep the form open, display
field-level errors, and let the user correct them — NOT collapse the form or flash a
generic message.

**In the component — preserve changeset state:**

```elixir
@impl true
def handle_event("save", _params, socket) do
  body = String.trim(socket.assigns.body || "")

  cond do
    body == "" ->
      {:noreply,
       socket
       |> assign(:validation_error, "Body cannot be empty")
       |> assign(:editing, true)}  # Keep form open

    socket.assigns.is_temporary ->
      case Polling.create_child(socket.assigns.current_scope,
                                socket.assigns.parent, %{body: body}) do
        {:ok, saved} ->
          send(self(), {:child_created, saved, Map.get(socket.assigns.child, :temp_id)})
          {:noreply, clear_edit(socket)}

        {:error, changeset} ->
          # Keep form open and show validation errors
          {:noreply,
           socket
           |> assign(:changeset, changeset)
           |> assign(:validation_error, error_message(changeset))
           |> assign(:editing, true)}
      end

    true ->
      case Polling.update_child(socket.assigns.current_scope,
                                 socket.assigns.child, %{body: body}) do
        {:ok, updated} ->
          send(self(), {:child_updated, updated})
          {:noreply, clear_edit(socket)}

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign(:changeset, changeset)
           |> assign(:validation_error, error_message(changeset))
           |> assign(:editing, true)}
      end
  end
end

defp error_message(%Ecto.Changeset{} = changeset) do
  changeset
  |> Ecto.Changeset.traverse_errors(fn {msg, _opts} -> msg end)
  |> Enum.map(fn {field, error} -> "#{field}: #{error}" end)
  |> Enum.join("; ")
end

defp error_message(_), do: "Could not save. Please check your input."
```

**In the template — show errors inline:**

```heex
<.form for={to_form(@changeset || %{}, as: :child)} id={"child-form-#{child_id(@child)}"}>
  <.input
    field={@form[:body]}
    type="text"
    value={@body}
    phx-change="update_body"
    phx-target={@myself}
  />
  <.error :if={@validation_error}>
    {Phoenix.HTML.raw(@validation_error)}
  </.error>
</.form>
```

### 12.2. Authorization Failure Recovery

When the context module returns `{:error, :forbidden}`, the component should:
1. Flash an error message
2. NOT change the local state (keep the form as-is)
3. Give the user a clear action (e.g., "You don't have permission")

```elixir
def handle_event("save", _params, socket) do
  case Polling.create_child(scope, parent, attrs) do
    {:ok, saved} ->
      # ... happy path ...
    {:error, :forbidden} ->
      {:noreply,
       socket
       |> put_flash(:error, "You don't have permission to modify this item")
       |> assign(:editing, true)}  # Keep form visible
    {:error, changeset} ->
      # ... validation error path ...
  end
end
```

### 12.3. Constraint Violation Recovery

Database constraint errors (unique index, foreign key, check constraint) surface as
`{:error, changeset}` with `:constraint` errors. The changeset will have the constraint
name in `changeset.errors`. The same error recovery pattern from 12.1 applies.

**Prevention is better than recovery:**
- Validate uniqueness at the changeset level with `unique_constraint/3`
- Use `foreign_key_constraint/3` for referential integrity
- Use `check_constraint/3` for business rules
- Use `unsafe_validate_unique/4` in the context module for user-friendly messages

```elixir
def changeset(child, attrs) do
  child
  |> cast(attrs, [:body, :position])
  |> validate_required([:body])
  |> unique_constraint(:body, name: :children_body_parent_id_index,
                       message: "already exists in this parent")
  |> foreign_key_constraint(:parent_id)
end
```

### 12.4. Network Disconnection and Reconnection

LiveView automatically handles WebSocket reconnection. When the connection drops:

1. The browser shows a "reconnecting" overlay (Phoenix's default behavior)
2. The LiveView state on the server is preserved (process not killed)
3. On reconnect, the LiveView re-mounts and re-fetches data

**What survives a reconnect:**
- Persisted data in the database (always fresh after re-mount)
- The LiveView process and its assigns (if not timed out)
- PubSub subscriptions (re-established on mount)

**What does NOT survive:**
- Unsaved form input in the browser (the user must re-enter)
- Temp records in the LiveView assign (re-mount clears them)

**Mitigation for temp record loss on reconnect:**

```elixir
# In the parent LiveView — detect reconnect
@impl true
def mount(%{"id" => parent_id}, _session, socket) do
  parent = Campaigns.get_parent!(current_scope, parent_id) |> Preloader.with_preloads()

  socket =
    if connected?(socket) do
      # Fresh mount — no temp records possible
      assign(socket, :children, parent.children)
    else
      # Initial render — LiveView is being pre-rendered on the server
      assign(socket, :children, parent.children)
    end

  {:ok, socket}
end
```

**The simplest mitigation:**
- Save early and often (implicit save via auto-save pattern)
- Use `phx-debounce` on form inputs to trigger saves without explicit "Save" clicks
- Accept that reconnection may lose the current form's unsaved state

### 12.5. Graceful Degradation

If the context module is unavailable (database down, deployment in progress), the LiveView
should not crash. Use `try/rescue` or pattern match on error tuples:

```elixir
# In the context module — never raise, always return tuples
def create_child(scope, parent, attrs) do
  :ok = authorize(scope, parent)

  %Child{parent_id: parent.id}
  |> Child.changeset(attrs)
  |> Repo.insert()
rescue
  e in DBConnection.ConnectionError ->
    {:error, :database_unavailable}
end

# In the LiveView — handle the error tuple
def handle_info({:child_created, {:error, :database_unavailable}, temp_id}, socket) do
  # Remove the optimistic temp record and show error
  children = Enum.reject(socket.assigns.children, fn c ->
    Map.get(c, :temp_id) == temp_id
  end)

  {:noreply,
   socket
   |> assign(:children, children)
   |> put_flash(:error, "Database is temporarily unavailable. Please try again.")}
end
```

---

All DB operations live in a context module. The LiveView never runs queries directly.

## 13. The Context Module in Depth

### Pattern for a Context Module

```elixir
defmodule MyApp.Polling do
  import Ecto.Query
  alias MyApp.Repo
  alias MyApp.Accounts.Scope
  alias MyApp.Campaigns.Poll
  alias __MODULE__.{Child, Grandchild, Reorder}

  # ── Queries ──

  def list_children(%Scope{} = scope, %Poll{} = poll) do
    :ok = authorize(scope, poll)

    Child
    |> where([c], c.poll_id == ^poll.id)
    |> order_by([c], asc: c.position, asc: c.inserted_at)
    |> Repo.all()
  end

  # ── Create ──

  def create_child(%Scope{} = scope, %Poll{} = poll, attrs) do
    :ok = authorize(scope, poll)

    %Child{poll_id: poll.id, position: next_position(Child, :poll_id, poll.id)}
    |> Child.changeset(attrs)
    |> Repo.insert()
  end

  # ── Position helper ──
  # Programmatic field: set on struct, not in cast/2

  defp next_position(schema, parent_field, parent_id) do
    schema
    |> where([r], field(r, ^parent_field) == ^parent_id)
    |> Repo.aggregate(:max, :position)
    |> case do
      nil -> 0
      max -> max + 1
    end
  end

  # ── Update, Delete ──

  def update_child(%Scope{} = scope, %Child{} = child, attrs) do
    :ok = authorize(scope, child)
    child |> Child.changeset(attrs) |> Repo.update()
  end

  def delete_child(%Scope{} = scope, %Child{} = child) do
    :ok = authorize(scope, child)
    Repo.delete(child)
  end

  # ── Reorder (delegate) ──

  defdelegate reorder(scope, record, direction), to: Reorder, as: :move
end
```

### Rules for the Context Module

1. **Every mutation takes `%Scope{}` first** — ownership/authorization is checked at the
   boundary
2. **Programmatic fields are set on the struct**, not in `cast/2` — this includes `position`,
   foreign keys (`poll_id`, `question_id`), `slug`, `token`, etc.
3. **Next position is computed via `aggregate(:max, :position)`** — handles the empty case
4. **Authorization is centralized** — each mutation calls `authorize(scope, record)` which
   follows the `belongs_to` chain to the top-level owner
5. **Return `{:ok, record}` or `{:error, changeset}`** — LiveViews pattern match on this

### Authorization Chain

```elixir
defmodule MyApp.Authorization do
  def authorize(%Scope{} = scope, %Poll{} = poll),
    do: ok_or_forbidden(poll.user_id == scope.user.id)

  def authorize(%Scope{} = scope, %Child{} = child) do
    child = Repo.preload(child, :poll)
    authorize(scope, child.poll)
  end

  def authorize(%Scope{} = scope, %Grandchild{} = grandchild) do
    grandchild = Repo.preload(grandchild, question: :poll)
    authorize(scope, grandchild.question.poll)
  end

  defp ok_or_forbidden(true), do: :ok
  defp ok_or_forbidden(false), do: {:error, :forbidden}
end
```

---

## 14. No-Negotiables and Guardrails

These rules are **not optional**. Violating any of them will produce bugs, data corruption,
or security holes.

### DO: LiveView is the source of truth

- The LiveView owns the list in its assigns
- Components never persist data — they send messages and the LiveView persists
- Components never modify the list — they tell the LiveView what changed

### DO: Use `phx-target={@myself}` for all component events

Without this, events go to the parent LiveView instead of the component:

```heex
<%-- CORRECT --%>
<.button phx-click="save" phx-target={@myself}>Save</.button>

<%-- WRONG --%>
<.button phx-click="save">Save</.button>
```

### DO: Set programmatic fields on the struct, not in cast

```elixir
# CORRECT
%Child{poll_id: poll.id, position: next_position(...)}
|> Child.changeset(attrs)
|> Repo.insert()

# WRONG
%Child{}
|> Child.changeset(Map.put(attrs, "poll_id", poll.id))
|> Repo.insert()
```

### DO: Use `:binary_id` primary keys and `@foreign_key_type :binary_id`

This is the standard for Phoenix apps with LiveView. UUIDv4 keys are URL-safe and prevent
sequential ID guessing.

### DO: Define a stable ID helper for components

The `child_id/1` function must handle both real IDs and temp IDs. Without this, components
will remount instead of updating in place when saved.

### DO: Guard against empty body in save handlers

```elixir
body == "" ->
  {:noreply, put_flash(socket, :error, "Body cannot be empty")}
```

### DO NOT: Nest modules in the same file

Each LiveView and LiveComponent gets its own file. Cyclic dependencies will crash compilation.

### DO NOT: Access changesets directly in templates

```heex
<%-- CORRECT --%>
<.form for={@form} id="my-form">
  <.input field={@form[:field]} type="text" />
</.form>

<%-- WRONG --%>
<.form for={@changeset} id="my-form">
```

### DO NOT: Use deprecated `live_redirect` or `live_patch`

Use `<.link navigate={...}>` and `<.link patch={...}>` instead.

### DO NOT: Put business logic in LiveViews or LiveComponents

Every function that does I/O or computation should be in a context module. The LiveView
should be a thin orchestration layer.

### DO NOT: Use `send_update/3` to communicate upward

`send_update/3` is for parent → child updates. For child → parent, use `send(self(), msg)`.
For cross-component, use callbacks.

### DO NOT: Render temp_id as DOM ID

Temp IDs like `"temp_12345"` are not valid for `send_update/3` targeting. Use the helper
function that generates a fallback UUID when neither `:id` nor `:temp_id` is present.

### DO: Understand flash message lifecycle

Flash messages set via `put_flash/3` in a LiveView `handle_info` callback survive for
exactly one render cycle. After the next user event (click, form submit, keydown), the
flash is cleared. This means:

- A flash set during `handle_info({:child_created, ...})` will be shown to the user
- If the user then clicks "Add Child", that click clears the flash
- Set flashes at the LAST possible moment — before the final `{:noreply, socket}`

```elixir
# CORRECT — flash set before the final noreply
{:noreply,
 socket
 |> put_flash(:info, "Created")
 |> assign(:children, children)}

# WRONG — flash set after a send() but before more work is fragile
send(self(), {:child_created, saved, temp_id})
put_flash(socket, :info, "Created")
# ... more work can clear the flash ...
```

### DO: Wrap templates in Layouts.app (Phoenix 1.8+)

Every LiveView template must be wrapped in `<Layouts.app>`:

```heex
<Layouts.app flash={@flash} current_scope={@current_scope}>
  ...your content...
</Layouts.app>
```

The `Layouts` module is aliased in `MyAppWeb`'s `html_helpers` block. Do not call
`<.flash_group>` outside of `layouts.ex`.

### DO: Use `mix precommit` before finishing

Run `mix precommit` (or the project's equivalent) before completing work. This runs
the compiler, linter (credo), security audit (mix_audit), formatter, and tests in one
pass. Fix any issues before committing.

### Phoenix v1.8 Framework Rules

These rules are specific to Phoenix 1.8+ and `phx.gen.auth` projects:

- **`<.icon>` over Heroicons modules**: Use `<.icon name="hero-x-mark" class="w-5 h-5"/>`
  from `core_components.ex` for icons. Never import `Heroicons` modules directly.
- **`<.input>` over raw HTML**: Use the imported `<.input>` component for all form inputs.
  If you override classes (e.g., `<.input class="myclass">`), you must provide full styling.
- **No inline `<script>` tags**: All custom JavaScript goes in `assets/js/` and integrates
  via `app.js`. Never write `<script>custom js</script>` in HEEx templates.
- **No external vendor scripts**: Do not add external `<script src>` or `<link href>`
  references in layouts. Import vendor dependencies through `app.js` and `app.css`.
- **Streams for dynamic collections**: Use `phx-update="stream"` and `@streams` for
  dynamic lists that users modify. Avoid `phx-update="append"` or `"prepend"` (deprecated).
- **One `live_session` name per scope**: A `live_session :current_user` can only be
  defined once. Group all routes sharing the same scope in one block. Do not duplicate
  the name.
- **`current_scope`, not `current_user`**: `phx.gen.auth` assigns `current_scope`,
  not `current_user`. Access the user via `@current_scope.user` in templates and
  `socket.assigns.current_scope` in LiveViews.

### Process Rules (From Real-World Failures)

These rules were learned from real failures. They govern how you build, not what you build.

#### DO: Write the design doc before writing code

A feature built without a design doc had a commit message that literally said "core
functionality remains broken." The fix was to write the spec first, then implement each
piece as a small, testable commit. The version with a design doc worked first time.

**Rule of thumb:** If you can't write a one-page spec for what you're building, you don't
understand it well enough to code it. Write the spec. Then implement.

#### DO: Ship in small, atomic commits

Each commit should add one thing you can describe without "and." A complex feature
(join page, presence, live results, presenter controls) shipped as 8 separate commits.
Each was independently testable and reviewable. Bugs were found in one commit without
blocking the others.

**Warning sign:** A commit message that starts with "lots of code" or contains "and"
is too big. Split it.

#### DO: Keep one responsibility per module

A LiveView that does two jobs (e.g., admin controls + user interaction) will grow past
the point where any agent or human can understand it. An 1100+ line module was deleted
entirely and replaced with two ~200-line focused modules. The replacement worked; the
monolith never did.

**Rule of thumb:** If a module name contains "and", split it. If a file exceeds 300 lines
for a LiveView or 200 lines for a LiveComponent, that is a signal it is doing too much.

#### DO NOT: Show UI for features that are not implemented

A form field was shown for an access code feature, but the code was never enforced.
Users expected it to work, creating confusion. The fix: remove the UI entirely, keep
only the model field for future use.

**Rule of thumb:** Every visible UI element should correspond to a working feature.
If a feature is deferred, hide the UI. Add it back when the feature actually works.

#### DO NOT: Trust structs from child messages

A struct received via `send(self(), {:message, struct})` is stale the moment the DB
transaction commits. Never use it for data you just mutated. Use it only for identity
(the ID), then re-query.

**Rule of thumb:** The struct in the message tells you *which* record changed. The DB
tells you *what* it looks like now. Always re-fetch.
---

## 15. Common Pitfalls

### Pitfall 1: Component remounts instead of updating

**Symptom:** Every parent re-render causes child components to flash/reset/refetch.

**Cause:** The component `id` changes on every render because it's based on an unstable
value (like an incrementing index instead of the database ID).

**Fix:** Always derive the component `id` from the record's stable identifier:

```elixir
# CORRECT
id={"child-#{child_id(child)}"}  # Uses DB id or temp_id

# WRONG — component remounts on every reorder
id={"child-#{idx}"}
```

### Pitfall 2: Components accumulate state

**Symptom:** After creating and saving multiple items, old items show stale data or duplicate.

**Cause:** The `update/2` callback doesn't properly reset component state when the parent
passes new data.

**Fix:** In `update/2`, always merge the new assigns from the parent, but preserve transient
UI state (like `:editing`) when appropriate:

```elixir
def update(assigns, socket) do
  socket = assign(socket, assigns)

  # Only reset local state if the component isn't being edited
  socket =
    if socket.assigns.editing do
      socket
    else
      assign(socket, :body, assigns.child.body || "")
    end

  {:ok, socket}
end
```

### Pitfall 3: Grandchild messages get lost

**Symptom:** Saving a grandchild (e.g., an option inside a question) doesn't update the UI.

**Cause:** The message goes to the LiveView but the handler doesn't know which child's list
to update.

**Fix:** Include the foreign key in the message and use it to find the correct child:

```elixir
# In the grandchild component
send(self(), {:option_created, saved_option, temp_id: temp_id})
#                                 ^ foreign key is in saved_option.question_id

# In the parent LiveView
def handle_info({:option_created, new_option, temp_id: temp_id}, socket) do
  questions = Enum.map(socket.assigns.questions, fn q ->
    if q.id == new_option.question_id do
      new_options = (q.options |> Enum.reject(fn o -> Map.get(o, :temp_id) == temp_id end)) ++ [new_option]
      %{q | options: new_options}
    else
      q
    end
  end)

  {:noreply, assign(socket, :questions, questions)}
end
```

### Pitfall 4: Reorder creates "jumping" or "duplicate" positions

**Symptom:** After several reorders, items start having duplicate positions or jumping
unexpectedly.

**Cause:** The reorder function doesn't use a transaction or doesn't re-normalize positions.

**Fix:** Always use the `Reorder.move/3` pattern that wraps the swap in a `Repo.transaction`
and re-assigns clean sequential positions after every operation.

### Pitfall 5: Flash messages on temp deletion

**Symptom:** Deleting a just-added (not yet saved) item shows "Successfully deleted" flash.

**Cause:** The delete handler doesn't distinguish between temp and persisted records.

**Fix:**
```elixir
should_flash? = not String.starts_with?(to_string(child_id), "temp_")
```

### Pitfall 6: `update/2` fires on every keystroke

**Symptom:** Form inputs lag or lose focus because the parent re-renders and `update/2`
resets the form.

**Cause:** The LiveView is re-rendering (e.g., due to a PubSub message), and `update/2` is
overwriting the component's local form state.

**Fix:** In `update/2`, only overwrite local state from assigns when the component is not
in edit mode, or use `assign_new/3` for values that should keep their current value:

```elixir
def update(assigns, socket) do
  socket = assign(socket, assigns)

  socket =
    if socket.assigns.editing do
      socket
    else
      assign(socket, :body, assigns.child.body || "")
    end

  {:ok, socket}
end
```

### Pitfall 7: `send_update/3` targeting across component boundaries

**Symptom:** `send_update(GrandchildLive, id: "option-...", ...)` doesn't reach the component.

**Cause:** `send_update/3` only works for components that are direct children of the
rendering LiveView, not arbitrary components in any tree.

**Fix:** For LiveView → grandchild communication, use `send_update/3` from the LiveView
(the LiveView owns the full render tree). For LiveComponent → sibling, use the callback
pattern or send up to the LiveView first.

### Pitfall 8: Stale parent data after mutation or reorder

**Symptom:** After reordering or creating a child, the UI shows the old order or missing data.

**Root cause:** The parent LiveView received a message with a struct from the child, then
tried to preload associations from that stale struct instead of re-fetching from the database.

```elixir
# BROKEN — uses stale struct from child message
def handle_info({:children_reordered, parent}, socket) do
  refreshed = preload_associations(parent)  # parent is STALE — shows old order
  {:noreply, assign(socket, :children, refreshed.children)}
end

# FIXED — re-fetches from database using the parent ID
def handle_info({:children_reordered, parent}, socket) do
  refreshed = get_parent_by_id(parent.id)  # fresh query from DB
  {:noreply, assign(socket, :children, refreshed.children)}
end
```

**Fix:** Never trust a struct received in a message for anything other than identity lookup.
Always re-query from the database. This applies to all handler types: reorder, create,
update, and any other mutation that changes persisted data.

### Pitfall 9: Monolithic LiveView trying to handle multiple roles

**Symptom:** A single LiveView file grows to 800+ lines, becomes hard to debug, and
core functionality stays broken for weeks.

**Root cause:** A single module tried to handle both the admin/presenter experience
and the end-user experience. The two roles have different state machines, different UI,
and different authorization rules — but they were crammed into one file with conditional
rendering. The fix was to delete the entire module and replace it with two focused
LiveViews, each around 200 lines. The replacement worked; the monolith never did.

**Warning signs:**
- The module name contains "and" (e.g., AdminAndUserPanel)
- There is `if @is_admin` / `if @is_user` branching throughout the render/1 function
- The file exceeds ~300 lines and mixes distinct user roles
- Development velocity slows because changes for one role break the other

**Fix:** Split by role or responsibility before the module grows unwieldy. A LiveView
should have one job. If the same page serves both admin and user, use polymorphic
render branches in separate function components, not in the LiveView itself. If that
still grows too large, split into separate routes.

**Good practice for sizing:** If you cannot describe what a module does in one sentence
without using "and", it is too large.

---

## 16. Testing the Pattern

### Testing Philosophy

Pure functions first, LiveView tests minimal.
Test the context module thoroughly. Test LiveViews only for basic rendering and interaction.

### Context Tests

```elixir
defmodule MyApp.PollingTest do
  use MyApp.DataCase

  describe "create_child/3" do
    test "creates child with next position" do
      scope = scope_fixture()
      poll = poll_fixture(scope)
      create_child(scope, poll, %{body: "first"})
      create_child(scope, poll, %{body: "second"})

      children = list_children(scope, poll)
      assert Enum.map(children, & &1.position) == [0, 1]
    end

    test "rejects unauthorized scope" do
      other_scope = scope_fixture()
      poll = poll_fixture(other_scope)
      wrong_scope = wrong_scope_fixture()

      assert {:error, :forbidden} =
        create_child(wrong_scope, poll, %{body: "nope"})
    end
  end

  describe "reorder/3" do
    test "moves child lower" do
      scope = scope_fixture()
      poll = poll_fixture(scope)
      c1 = child_fixture(scope, poll, %{body: "A", position: 0})
      c2 = child_fixture(scope, poll, %{body: "B", position: 1})
      c3 = child_fixture(scope, poll, %{body: "C", position: 2})

      assert {:ok, :reordered} = reorder(scope, c1, :lower)

      children = list_children(scope, poll)
      assert Enum.map(children, & &1.body) == ["B", "A", "C"]
      assert Enum.map(children, & &1.position) == [0, 1, 2]
    end

    test "does nothing when at boundary" do
      scope = scope_fixture()
      poll = poll_fixture(scope)
      c1 = child_fixture(scope, poll, %{body: "A", position: 0})
      c2 = child_fixture(scope, poll, %{body: "B", position: 1})

      assert {:ok, :unchanged} = reorder(scope, c1, :higher)
    end
  end
end
```

### LiveView Interaction Tests

```elixir
defmodule MyAppWeb.ParentLive.QuestionsTest do
  use MyAppWeb.ConnCase

  test "add button creates temp record", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/parents/#{parent.id}/questions")

    view |> element("#add-child-btn") |> render_click()

    assert has_element?(view, "#child-temp_")  # Temp record rendered
  end

  test "save persists child", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/parents/#{parent.id}/questions")

    view |> element("#add-child-btn") |> render_click()

    view
    |> form("#child-form", child: %{body: "New item"})
    |> render_submit()

    assert has_element?(view, "#child-#{saved_id}")
  end
end
```

---

## 17. Cheat Sheet: Messages Reference

### Communication Direction Summary

```
┌─────────────────┐
│                 │ ◄──── send(self(), {:child_created, record, temp_id})
│   Parent        │ ◄──── send(self(), {:child_updated, record})
│   LiveView      │ ◄──── send(self(), {:child_deleted, id})
│   (source       │ ◄──── send(self(), {:children_reordered, parent})
│    of truth)    │ ◄──── send(self(), {:grandchild_created, record, opts})
│                 │ ◄──── send(self(), {:grandchild_updated, record})
│                 │ ◄──── send(self(), {:grandchild_deleted, id})
│                 │ ◄──── send(self(), {:grandchildren_reordered, parent})
└────────┬────────┘
         │ renders with assigns (child, idx, count, etc.)
         ▼
┌─────────────────┐
│  Child LC       │
│  (owns transient │
│   UI state)     │
└────────┬────────┘
         │ renders with assigns (grandchild, idx, count, etc.)
         ▼
┌─────────────────┐
│  Grandchild LC  │
│  (owns transient │
│   UI state)     │
└─────────────────┘
```

> **Key:** ALL `send(self(), ...)` calls at every depth reach the **Parent LiveView** directly.
> The Child LC never intercepts grandchild messages. The foreign key in the message
> (e.g., `parent_child_id`) tells the LiveView which child's sub-list to update.

### Handler Signatures in LiveView

```elixir
# ── Child CRUD ──

@impl true
def handle_info({:child_created, saved_child :: struct(), temp_id :: String.t()}, socket)

def handle_info({:child_updated, updated_child :: struct()}, socket)

def handle_info({:child_deleted, child_id :: String.t()}, socket)

def handle_info({:children_reordered, parent :: struct()}, socket)

# ── Grandchild CRUD (includes foreign key for routing) ──

def handle_info({:grandchild_created, record :: struct(), opts :: Keyword.t()}, socket)

def handle_info({:grandchild_updated, record :: struct()}, socket)

def handle_info({:grandchild_deleted, id :: String.t()}, socket)

def handle_info({:grandchildren_reordered, parent_of_grandchild :: struct()}, socket)
```

### Component Update Guard Template

```elixir
@impl true
def update(assigns, socket) do
  socket = assign(socket, assigns)

  socket =
    if socket.assigns.editing do
      socket  # Preserve local edit state during user input
    else
      socket
      |> assign(:body, assigns.child.body || "")
      |> assign(:editing, Map.has_key?(assigns.child, :temp_id))
    end

  {:ok, socket}
end
```

---

## 18. Implementation Checklist

### Before You Write Code
- [ ] Design doc written and reviewed (one page, covers: data model, LiveView/component tree, message flow, reordering strategy)
- [ ] Implementation broken into small, independent commits (each describable without "and")

### Schema & Context
- [ ] Schema uses `:binary_id` primary key and `@foreign_key_type :binary_id`
- [ ] `position` field exists as integer with default 0
- [ ] Programmatic fields set on struct, not in `cast/2`
- [ ] Context module has `list_*`, `create_*`, `update_*`, `delete_*`, `reorder` functions
- [ ] Authorization checked in every mutation
- [ ] Reorder module is atomic with transaction and position normalization
- [ ] Context `get_*!` preloads children with correct ordering
- [ ] Next position computed via `aggregate(:max, :position)`

### Parent LiveView
- [ ] LiveView has a single responsibility (< 300 lines, no "and" in its purpose)
- [ ] All `handle_info` handlers re-fetch from DB after mutation (never use struct from message)
- [ ] Fetches parent with preloaded children on mount
- [ ] Renders children via `Enum.with_index` + `.live_component`
- [ ] Passes `idx`, `count`, `current_scope` to each child
- [ ] `child_id/1` handles real IDs, temp IDs, and fallback
- [ ] `handle_event("add_child", ...)` creates temp records with `temp_id` and correct `position`
- [ ] `handle_info({:child_created, ...})` replaces temp with persisted
- [ ] `handle_info({:child_updated, ...})` updates matching record
- [ ] `handle_info({:child_deleted, ...})` removes by id or temp_id
- [ ] `handle_info({:children_reordered, ...})` re-fetches from DB
- [ ] Flash messages only for persisted operations

### Child LiveComponent
- [ ] `use MyAppWeb, :live_component`
- [ ] `mount/1` initializes transient state (editing, body, results)
- [ ] `update/2` merges assigns, preserves edit state during editing
- [ ] Detects temp records via `Map.has_key?(assigns.child, :temp_id)`
- [ ] All event handlers use `phx-target={@myself}`
- [ ] Save handler distinguishes create vs update via `is_temporary`
- [ ] Delete handler sends `temp_id` or persisted `id` appropriately
- [ ] Reorder handler calls context, sends message to parent
- [ ] Empty body guarded with flash message

### Grandchild LiveComponent (if nested)
- [ ] Same structure as Child LiveComponent
- [ ] Message includes foreign key for parent routing
- [ ] Or uses callback pattern for flexibility

### Tests
- [ ] Each commit in the sequence has its own tests (don't defer all tests to a "tests" commit later)
- [ ] Context tests for create with position assignment
- [ ] Context tests for reorder (move higher, lower, boundary, normalization)
- [ ] Context tests for authorization (rejects wrong scope)
- [ ] LiveView test: add button creates temp record
- [ ] LiveView test: save persists record
- [ ] LiveView test: delete removes record
- [ ] LiveView test: reorder changes order

---

> **Reference implementation:** The [Slidex](https://github.com/greecex/slidex) codebase
> demonstrates this pattern in production. See `PollLive.Questions` (parent),
> `QuestionLive` (child), `OptionLive` (grandchild), `Polling.Reorder` (reordering),
> and `Polling` (context). The pattern has been extracted from studying how these modules
> interact — it is not speculative but distilled from a working application.
