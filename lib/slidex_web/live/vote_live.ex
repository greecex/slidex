defmodule SlidexWeb.VoteLive do
  @moduledoc """
  The single LiveView for participant (and MC) experience at /vote/:slug.

  - Public or private (is_public on the Session)
  - Optional access_code gate (bypassed for the MC)
  - Real-time: current question chosen by MC, live results when enabled,
    participant count + identicons (Presence), votes streaming in.
  - MC sees admin controls when current_scope.user.id == session.poll.user_id
  - All business logic lives in Slidex.Voting (pure functions + doctests first).
  """

  use SlidexWeb, :live_view

  import Ecto.Query

  alias Slidex.{Polling, Repo, Voting}
  alias Slidex.Polling.Option
  alias Slidex.Voting.{Result, Session}
  alias SlidexWeb.Presence

  @identicon_params [7, :split2, 1.0, 2, [squircle_curvature: 0.8]]

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} current_scope={@current_scope}>
      <div class="max-w-3xl mx-auto">
        <!-- Header -->
        <div class="flex items-start justify-between mb-6">
          <div>
            <div class="flex items-center gap-x-3">
              <h1 class="text-2xl font-semibold tracking-tight">{@session.title}</h1>
              <div :if={@session.state == :active} class="badge badge-success badge-soft">LIVE</div>
              <div :if={@session.state != :active} class="badge badge-soft">
                {String.capitalize(to_string(@session.state))}
              </div>
            </div>
            <div
              :if={@session.description && @session.show_description}
              class="text-sm text-base-content/70 mt-1"
            >
              {@session.description}
            </div>
          </div>

          <div class="text-right">
            <div class="text-sm text-base-content/60">Participants</div>
            <div class="text-2xl font-semibold tabular-nums">{@participant_count}</div>
          </div>
        </div>
        
    <!-- Participant identicon strip (multiplayer demo) -->
        <div class="mb-6">
          <div class="flex flex-wrap gap-2">
            <div
              :if={@participant_count == 0}
              class="text-xs text-base-content/50 italic"
            >
              No one here yet. You will be the first!
            </div>
            <div id="participants" class="contents" phx-update="stream">
              <div
                :for={{dom_id, p} <- @streams.participants}
                id={dom_id}
                class="tooltip"
                data-tip={p.label || "Participant"}
              >
                <div class="w-8 h-8 rounded-full overflow-hidden ring-1 ring-base-300 bg-base-200">
                  {Phoenix.HTML.raw(identicon_svg(p.seed))}
                </div>
              </div>
            </div>
          </div>
        </div>

        <%= if not @show_voting_ui and not (@session.state == :ended and @session.show_results == true) do %>
          <.session_not_open session={@session} poll={@poll} />
        <% else %>
          <!-- Main voting surface -->
          <%= if @session.state == :ended do %>
            <div class="text-center mb-2">
              <span class="badge badge-neutral badge-soft">Final results</span>
            </div>
          <% end %>
          <div id={@question_surface_id} phx-update="replace">
            <%= if is_nil(@current_question) do %>
              <%= if @is_mc do %>
                <div class="rounded-lg border border-dashed border-primary/40 bg-primary/5 p-8 text-center">
                  <p class="font-medium text-primary">
                    <%= if @session.state == :ended do %>
                      Session ended.
                    <% else %>
                      Ready to start.
                    <% end %>
                  </p>
                  <p class="text-sm text-base-content/70 mt-1">
                    <%= if @session.state == :ended do %>
                      Use the controls below to review or restart the session.
                    <% else %>
                      Click "Start voting" below to begin (the first question will be selected automatically). Once the session is active, the prev/next controls will appear so you can step through questions.
                    <% end %>
                  </p>
                </div>
              <% else %>
                <div class="rounded-lg border border-dashed border-base-300 p-8 text-center">
                  <p class="font-medium">The host has not started the first question yet.</p>
                  <p class="text-sm text-base-content/60 mt-1">Please wait...</p>
                </div>
              <% end %>
            <% else %>
              <div class="space-y-6">
                <!-- Question -->
                <div class="rounded-xl border border-base-300 bg-base-100 p-6">
                  <div class="uppercase tracking-[2px] text-xs font-semibold text-base-content/50 mb-2">
                    Question
                  </div>
                  <div class="text-xl font-medium leading-tight">
                    {@current_question.body}
                  </div>
                </div>
                
    <!-- Options -->
                <div class="grid gap-3">
                  <%= for option <- @options do %>
                    <button
                      type="button"
                      phx-click="vote"
                      phx-value-option_id={option.id}
                      disabled={not @can_vote or @is_mc}
                      class={[
                        "group flex items-center justify-between rounded-xl border px-5 py-4 text-left transition-all",
                        "hover:border-primary focus:outline-none focus:ring-2 focus:ring-primary/30",
                        if(@my_vote_id == option.id,
                          do: "border-primary bg-primary/5",
                          else: "border-base-300"
                        ),
                        if(not @can_vote, do: "opacity-60 cursor-not-allowed")
                      ]}
                    >
                      <div class="font-medium pr-4">{option.body}</div>

                      <div class="flex items-center gap-x-3 text-sm tabular-nums">
                        <%= if @show_results_for_me do %>
                          <div class="flex items-center gap-x-2 text-base-content/70">
                            <div class="w-24 h-2 rounded-full bg-base-200 overflow-hidden">
                              <div
                                class="h-2 bg-primary transition-all"
                                style={"width: #{percent(@tallies[option.id] || 0, @total_votes)}%"}
                              >
                              </div>
                            </div>
                            <span>{@tallies[option.id] || 0}</span>
                          </div>
                        <% end %>

                        <%= if @show_voter_choices_for_me && @voter_choices[option.id] do %>
                          <div class="flex flex-wrap gap-1 mt-1">
                            <%= for v <- (@voter_choices[option.id] || []) do %>
                              <div
                                class="w-5 h-5 rounded-full overflow-hidden ring-1 ring-base-300 bg-base-200"
                                title={v.label}
                              >
                                {Phoenix.HTML.raw(identicon_svg(v.seed))}
                              </div>
                            <% end %>
                          </div>
                        <% end %>

                        <%= if @is_mc and option.is_correct do %>
                          <span class="badge badge-success badge-sm">Correct</span>
                        <% end %>
                      </div>
                    </button>
                  <% end %>
                </div>
                
    <!-- Your status -->
                <div
                  :if={@my_vote_id != nil and not @is_mc}
                  class="text-sm text-success flex items-center gap-x-2"
                >
                  <.icon name="hero-check-circle" class="size-4" /> Your vote has been recorded.
                  <span :if={not @show_results} class="text-base-content/60">
                    Results are currently hidden by the host.
                  </span>
                </div>
                
    <!-- Leaderboard (shown to everyone when the MC enables live results and the poll has any is_correct options) -->
                <%= if @has_correct == true and @show_results_for_me and length(@leaderboard) > 0 do %>
                  <div class="mt-8">
                    <div class="flex items-center gap-x-2 mb-3">
                      <div class="font-semibold">Leaderboard</div>
                      <div class="text-xs text-base-content/50">(correct answers)</div>
                    </div>
                    <div class="space-y-2">
                      <%= for entry <- @leaderboard do %>
                        <div class="flex items-center gap-x-3 rounded-lg border border-base-300 px-4 py-2">
                          <div class="w-7 h-7 rounded-full overflow-hidden ring-1 ring-base-300 shrink-0">
                            {Phoenix.HTML.raw(identicon_svg(entry.seed))}
                          </div>
                          <div class="flex-1 text-sm font-medium truncate">
                            {entry.label || "Participant"}
                          </div>
                          <div class="font-mono text-sm tabular-nums text-base-content/80">
                            {entry.correct} / {entry.voted}
                          </div>
                        </div>
                      <% end %>
                    </div>
                  </div>
                <% end %>
              </div>
            <% end %>
          </div>
        <% end %>

        <%= if @requires_code and not @access_granted do %>
          <div
            id="access-code-gate"
            class="fixed inset-0 z-[100] flex items-center justify-center bg-black/40 p-4"
          >
            <.access_code_gate session={@session} form={@code_form} />
          </div>
        <% end %>
        
    <!-- MC Controls (only visible to the poll owner) -->
        <%= if @is_mc do %>
          <div class="mt-10 rounded-2xl border-2 border-primary/40 bg-primary/5 p-5">
            <div class="flex items-center gap-x-2 mb-4">
              <.icon name="hero-user-circle" class="size-5 text-primary" />
              <span class="font-semibold text-primary">Master of Ceremonies</span>
            </div>

            <%= if @session.access_code do %>
              <div class="mb-4 flex items-center gap-x-2 rounded-lg bg-base-100 px-3 py-2 text-sm ring-1 ring-inset ring-base-300">
                <span class="font-medium text-base-content/80">Access code:</span>
                <code class="font-mono text-base font-semibold tracking-[2px] text-primary">
                  {@session.access_code}
                </code>
                <span class="text-xs text-base-content/60">(share with participants)</span>
              </div>
            <% end %>

            <div class="flex flex-wrap items-center gap-3">
              <!-- State -->
              <%= if @session.state == :pending do %>
                <.button phx-click="mc_start" variant="primary">
                  <.icon name="hero-play" class="size-4" /> Start voting
                </.button>
              <% end %>

              <%= if @session.state == :active do %>
                <.button phx-click="mc_end" class="btn btn-soft">
                  <.icon name="hero-stop" class="size-4" /> End voting
                </.button>
              <% end %>

              <%= if @session.state == :ended do %>
                <.button phx-click="mc_restart" class="btn btn-soft btn-success">
                  <.icon name="hero-arrow-path" class="size-4" /> Restart voting
                </.button>
                <.button
                  phx-click="mc_reset_votes"
                  data-confirm="Clear ALL votes and results for this session? This cannot be undone."
                  class="btn btn-soft btn-error"
                >
                  <.icon name="hero-trash" class="size-4" /> Reset votes
                </.button>
              <% end %>
              
    <!-- Question navigation (for active and ended, so MC can review) -->
              <%= if @session.state in [:active, :ended] do %>
                <div class="flex items-center gap-x-1 ml-2">
                  <.button
                    phx-click="mc_prev"
                    disabled={@prev_question_id == nil}
                    class="btn btn-sm btn-ghost"
                  >
                    <.icon name="hero-chevron-left" class="size-4" /> Prev
                  </.button>

                  <span class="px-3 text-sm tabular-nums text-base-content/70">
                    Question {@current_index + 1} / {@question_count}
                  </span>

                  <.button
                    phx-click="mc_next"
                    disabled={@next_question_id == nil}
                    class="btn btn-sm btn-ghost"
                  >
                    Next <.icon name="hero-chevron-right" class="size-4" />
                  </.button>
                </div>
              <% end %>
              
    <!-- Results toggle -->
              <div class="flex items-center gap-x-2 ml-auto">
                <span class="text-sm">Show live results</span>
                <input
                  type="checkbox"
                  class="toggle toggle-primary"
                  checked={@session.show_results}
                  phx-click="mc_toggle_results"
                />
              </div>

              <%= if @has_correct do %>
                <div class="text-[10px] text-base-content/50 ml-2">+ leaderboard</div>
              <% end %>
              
    <!-- Voter choices toggle (MC always sees them) -->
              <div class="flex items-center gap-x-2">
                <span class="text-sm">Show voter choices</span>
                <input
                  type="checkbox"
                  class="toggle toggle-primary"
                  checked={@session.show_voter_choices}
                  phx-click="mc_toggle_voter_choices"
                />
              </div>
              
    <!-- Close -->
              <div class="divider divider-horizontal mx-1" />
              <.button
                phx-click="mc_close"
                data-confirm="Close this session for everyone? (You can reopen later)"
                class="btn btn-sm btn-error btn-soft"
              >
                <.icon name="hero-x-mark" class="size-4" /> Close session
              </.button>
            </div>

            <p class="mt-3 text-[10px] text-base-content/50">
              You can reuse this session for multiple cohorts without ending it.
            </p>
          </div>
        <% end %>
      </div>
      
    <!-- Access code remember hook (LocalStorage) for "Remember me" on access code gate -->
      <div
        id="access-code-remember"
        phx-hook="AccessCodeRemember"
        phx-update="ignore"
        class="hidden"
        data-slug={@session && @session.slug}
      >
      </div>
    </Layouts.app>
    """
  end

  # --- Small UI components (colocated style, no separate LCs needed) ---

  attr :session, :map, required: true
  attr :poll, :map, required: true

  def session_not_open(assigns) do
    ~H"""
    <div class="rounded-2xl border border-base-300 bg-base-100 p-8 text-center">
      <div class="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-base-200">
        <%= cond do %>
          <% @session.state == :ended -> %>
            <.icon name="hero-flag" class="size-6 text-base-content/70" />
          <% not is_nil(@session.closed_at) or @session.state == :ended -> %>
            <.icon name="hero-stop-circle" class="size-6 text-warning" />
          <% true -> %>
            <.icon name="hero-exclamation-triangle" class="size-6 text-warning" />
        <% end %>
      </div>

      <h2 class="text-lg font-semibold">
        <%= cond do %>
          <% @session.state == :ended -> %>
            The voting session has ended
          <% true -> %>
            This session is not open for voting
        <% end %>
      </h2>

      <div class="mt-2 space-y-1 text-sm text-base-content/70">
        <%= cond do %>
          <% @session.state == :pending -> %>
            <p>The host has not started the session yet. Please wait for the MC to begin.</p>
          <% @session.state == :ended -> %>
            <p>
              Thank you for participating. The host has chosen not to share final results for this session.
            </p>
          <% @session.closed_at -> %>
            <p>This session has been closed by the host.</p>
          <% @session.expires_at && DateTime.compare(@session.expires_at, DateTime.utc_now()) == :lt -> %>
            <p>This session has expired.</p>
          <% @poll.archived_at -> %>
            <p>The parent poll has been archived.</p>
          <% true -> %>
            <p>Voting is currently unavailable.</p>
        <% end %>
      </div>
    </div>
    """
  end

  attr :session, :map, required: true
  attr :form, Phoenix.HTML.Form, required: true

  def access_code_gate(assigns) do
    ~H"""
    <div class="mx-auto max-w-sm">
      <div class="card bg-base-100 shadow border border-base-300">
        <div class="card-body">
          <div class="flex justify-center">
            <div class="w-14 h-14 rounded-full bg-primary/10 flex items-center justify-center">
              <.icon name="hero-lock-closed" class="size-7 text-primary" />
            </div>
          </div>

          <div class="text-center">
            <h2 class="card-title justify-center text-2xl">Access code required</h2>
            <p class="text-sm text-base-content/70 mt-1">
              Enter the code provided by the host to join this voting session.
            </p>
          </div>

          <.form for={@form} id="access-code-form" phx-submit="submit_access_code" class="mt-4">
            <.input
              field={@form[:code]}
              type="text"
              placeholder="ABC-DEF"
              class="w-full text-center tracking-[6px] font-mono text-2xl input input-bordered"
              autofocus
            />

            <label class="flex items-center gap-x-2 mt-3 cursor-pointer text-sm">
              <input
                type="checkbox"
                name="remember_me"
                value="true"
                class="checkbox checkbox-sm"
              />
              <span>Remember me on this device</span>
            </label>

            <div class="card-actions justify-center mt-4">
              <.button variant="primary" class="w-full sm:w-auto px-8">
                <.icon name="hero-arrow-right-on-rectangle" class="size-4 mr-1" /> Join session
              </.button>
            </div>
          </.form>

          <p class="text-center text-xs text-base-content/60 mt-3">
            The code is case-insensitive.
          </p>
        </div>
      </div>
    </div>
    """
  end

  # --- Lifecycle ---

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    # Normalize incoming slug (ULIDs are case-insensitive) so that
    # /vote/01H... and /vote/01h... both work, and internal links stay lower.
    slug = String.downcase(slug)
    session = Voting.get_session_by_slug(slug)

    if is_nil(session) do
      {:ok,
       socket
       |> put_flash(:error, "Session not found.")
       |> push_navigate(to: ~p"/")}
    else
      poll = session.poll
      current_scope = socket.assigns.current_scope

      current_user = current_scope && current_scope.user
      authenticated? = not is_nil(current_user)
      is_mc = authenticated? and current_user.id == poll.user_id

      # For non-public sessions, unauthenticated users must log in first.
      # current_scope can be nil for guests (see Scope.for_user(nil)).
      if not session.is_public and not authenticated? do
        {:ok,
         socket
         |> put_flash(:error, "Please log in to join this session.")
         |> push_navigate(to: ~p"/users/log-in?return_to=#{URI.encode_www_form("/vote/#{slug}")}")}
      else
        # Initial assigns - we resolve identity + presence after connect
        socket =
          socket
          |> assign(:page_title, session.title)
          |> assign(:session, session)
          |> assign(:poll, poll)
          |> assign(:is_mc, is_mc)
          |> assign(:session_open, Voting.voting_open?(session))
          |> assign(:show_voting_ui, Voting.voting_open?(session) or is_mc)
          |> assign(:requires_code, not is_nil(session.access_code))
          |> assign(:requires_code, not is_nil(session.access_code))
          |> assign(:access_granted, is_mc or is_nil(session.access_code))
          |> assign(:current_question, session.current_question)
          |> assign(
            :options,
            if(session.current_question, do: session.current_question.options, else: [])
          )
          |> assign(
            :my_vote_id,
            if is_mc do
              nil
            else
              if current_scope && current_scope.user do
                Voting.current_vote_for_identity(session, %{user_id: current_scope.user.id})
              else
                nil
              end
            end
          )
          |> assign(:show_results, session.show_results)
          |> assign(:tallies, %{})
          |> assign(:total_votes, 0)
          |> assign(:voter_choices, Voting.current_voter_choices(session))
          |> assign(:show_results_for_me, is_mc or session.show_results == true)
          |> assign(
            :show_voter_choices_for_me,
            is_mc or (session.show_results == true and session.show_voter_choices == true)
          )
          |> assign(:has_correct, Voting.has_correct_answers?(poll))
          |> assign(:leaderboard, [])
          |> assign(:participant_count, 0)
          |> stream(:participants, [])
          |> assign(:code_form, to_form(%{"code" => ""}))
          |> assign(:can_vote, false)
          # MC navigation support
          |> assign_mc_navigation(session, current_scope)
          |> assign_question_surface_id()
          |> maybe_subscribe_and_track(slug, is_mc, current_scope)

        {:ok, socket}
      end
    end
  end

  defp assign_mc_navigation(socket, session, current_scope) do
    if socket.assigns.is_mc do
      # Safe to call Polling.list_questions because we are the owner
      questions =
        if current_scope do
          Polling.list_questions(current_scope, session.poll)
        else
          []
        end

      current_id = session.current_question_id
      idx = Enum.find_index(questions, &(&1.id == current_id)) || 0
      prev_q = if idx > 0, do: Enum.at(questions, idx - 1), else: nil
      next_q = Enum.at(questions, idx + 1)

      socket
      |> assign(:questions, questions)
      |> assign(:current_index, idx)
      |> assign(:question_count, length(questions))
      |> assign(:prev_question_id, if(prev_q, do: prev_q.id, else: nil))
      |> assign(:next_question_id, if(next_q, do: next_q.id, else: nil))
    else
      socket
      |> assign(:questions, [])
      |> assign(:current_index, 0)
      |> assign(:question_count, 1)
      |> assign(:prev_question_id, nil)
      |> assign(:next_question_id, nil)
    end
  end

  defp assign_question_surface_id(socket) do
    q = socket.assigns[:current_question]
    sess = socket.assigns[:session] || %{}

    id =
      if q do
        r = if sess.show_results, do: "1", else: "0"
        v = if sess.show_voter_choices, do: "1", else: "0"
        "current-question-#{q.id}-r#{r}-v#{v}"
      else
        "no-current-question"
      end

    assign(socket, :question_surface_id, id)
  end

  defp maybe_subscribe_and_track(socket, _slug, _is_mc, _current_scope) do
    # We do the real work after the JS hook (or for logged-in users) has given us an identity
    # and after connect. See handle_event "visitor-identified" and handle_info for presence.
    if connected?(socket) do
      Voting.subscribe_to_session(socket.assigns.session.slug)
    end

    socket
  end

  @impl true
  def handle_event("submit_access_code", params, socket) do
    session = socket.assigns.session
    raw = params["code"] || ""
    normalized = normalize_code(raw)
    expected = normalize_code(session.access_code || "")
    remember_me = params["remember_me"] == "true"

    if normalized == expected and expected != "" do
      socket =
        socket
        |> assign(:access_granted, true)
        |> put_flash(:info, "Welcome! You can now vote.")
        |> refresh_after_identity()

      if remember_me do
        socket =
          Phoenix.LiveView.push_event(socket, "slidex:remember-access-code", %{
            slug: session.slug,
            code: normalized
          })
      end

      {:noreply, socket}
    else
      {:noreply, put_flash(socket, :error, "Incorrect access code.")}
    end
  end

  def handle_event("vote", %{"option_id" => option_id}, socket) do
    if socket.assigns.is_mc do
      {:noreply, put_flash(socket, :error, "The MC cannot vote in this session.")}
    else
      if socket.assigns.can_vote do
        option = Enum.find(socket.assigns.options, &(&1.id == option_id))

        if option do
          identity = current_identity(socket)
          current = socket.assigns.my_vote_id

          if option.id == current do
            # Undo the vote by clicking the already chosen option
            case Voting.remove_vote(socket.assigns.session, identity) do
              {:ok, _} ->
                {:noreply,
                 socket
                 |> assign(:my_vote_id, nil)
                 |> maybe_refresh_tallies()}

              {:error, _reason} ->
                {:noreply, put_flash(socket, :error, "Could not remove your vote right now.")}
            end
          else
            case Voting.cast_vote(socket.assigns.session, option, identity) do
              {:ok, _result} ->
                # Optimistic: mark our vote immediately
                {:noreply,
                 socket
                 |> assign(:my_vote_id, option.id)
                 |> maybe_refresh_tallies()}

              {:error, _reason} ->
                {:noreply, put_flash(socket, :error, "Could not record your vote right now.")}
            end
          end
        else
          {:noreply, socket}
        end
      else
        {:noreply, socket}
      end
    end
  end

  # MC controls
  def handle_event("mc_start", _params, socket) do
    if socket.assigns.is_mc do
      session = socket.assigns.session
      scope = socket.assigns.current_scope

      # Auto-select the first question if none is set when starting
      if session.state == :pending and is_nil(session.current_question_id) do
        first_question =
          Polling.list_questions(scope, session.poll)
          |> List.first()

        if first_question do
          Voting.set_current_question(scope, session, first_question)
        end
      end

      {:ok, updated} = Voting.start_session(scope, socket.assigns.session)
      {:noreply, apply_session_update(socket, updated)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mc_end", _params, socket) do
    if socket.assigns.is_mc do
      {:ok, updated} = Voting.end_session(socket.assigns.current_scope, socket.assigns.session)
      {:noreply, apply_session_update(socket, updated)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mc_restart", _params, socket) do
    if socket.assigns.is_mc and socket.assigns.session.state == :ended do
      {:ok, updated} = Voting.restart_voting(socket.assigns.current_scope, socket.assigns.session)
      {:noreply, apply_session_update(socket, updated)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mc_reset_votes", _params, socket) do
    if socket.assigns.is_mc do
      {:ok, _} = Voting.reset_votes(socket.assigns.current_scope, socket.assigns.session)
      # Refresh the current tallies/choices for the UI
      {:noreply, apply_session_update(socket, socket.assigns.session)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mc_prev", _params, socket) do
    if socket.assigns.is_mc && socket.assigns.prev_question_id do
      prev_q = Enum.find(socket.assigns.questions, &(&1.id == socket.assigns.prev_question_id))
      do_set_question(socket, prev_q)
    else
      {:noreply, socket}
    end
  end

  def handle_event("mc_next", _params, socket) do
    if socket.assigns.is_mc && socket.assigns.next_question_id do
      next_q = Enum.find(socket.assigns.questions, &(&1.id == socket.assigns.next_question_id))
      do_set_question(socket, next_q)
    else
      {:noreply, socket}
    end
  end

  def handle_event("mc_toggle_results", _params, socket) do
    if socket.assigns.is_mc do
      {:ok, updated} =
        Voting.toggle_show_results(socket.assigns.current_scope, socket.assigns.session)

      {:noreply, apply_session_update(socket, updated)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mc_toggle_voter_choices", _params, socket) do
    if socket.assigns.is_mc do
      {:ok, updated} =
        Voting.toggle_voter_choices(socket.assigns.current_scope, socket.assigns.session)

      {:noreply, apply_session_update(socket, updated)}
    else
      {:noreply, socket}
    end
  end

  def handle_event("mc_close", _params, socket) do
    if socket.assigns.is_mc do
      {:ok, _closed} = Voting.close_session(socket.assigns.current_scope, socket.assigns.session)
      # Re-fetch to get latest preloads
      session = Voting.get_session_by_slug!(socket.assigns.session.slug)
      {:noreply, apply_session_update(socket, session)}
    else
      {:noreply, socket}
    end
  end

  # Called by the VisitorIdentity JS hook for guests (and also usable for users)
  def handle_event("visitor-identified", %{"visitor_id" => visitor_id}, socket)
      when is_binary(visitor_id) do
    if socket.assigns.access_granted or not socket.assigns.requires_code do
      socket =
        socket
        |> assign(:visitor_id, visitor_id)
        |> refresh_after_identity()

      {:noreply, socket}
    else
      # Still behind code gate; store it anyway so we can use it the moment they succeed
      {:noreply, assign(socket, :visitor_id, visitor_id)}
    end
  end

  # Called by the AccessCodeRemember hook when it finds a previously remembered
  # (and still valid) access code in localStorage for this slug.
  def handle_event("access_code_remembered", %{"slug" => slug, "code" => code}, socket) do
    if slug == socket.assigns.session.slug and
         socket.assigns.requires_code and
         not socket.assigns.access_granted do
      normalized = normalize_code(code)
      expected = normalize_code(socket.assigns.session.access_code || "")

      if normalized == expected and expected != "" do
        socket =
          socket
          |> assign(:access_granted, true)
          |> put_flash(:info, "Welcome back — access code remembered from this device.")
          |> refresh_after_identity()

        {:noreply, socket}
      else
        # Stored code is no longer valid (e.g. host changed it). Clear it on the client.
        socket =
          Phoenix.LiveView.push_event(socket, "slidex:clear-access-code", %{slug: slug})

        {:noreply, socket}
      end
    else
      {:noreply, socket}
    end
  end

  defp do_set_question(socket, %Polling.Question{} = question) do
    {:ok, updated} =
      Voting.set_current_question(socket.assigns.current_scope, socket.assigns.session, question)

    {:noreply, apply_session_update(socket, updated)}
  end

  # --- Info handlers (PubSub + Presence) ---

  @impl true
  def handle_info({:current_question_changed, _session}, socket) do
    # Re-fetch from DB (via get_session_by_slug which does Preloader) so that
    # the voter view always gets a fully preloaded current_question + options.
    # This ensures MC question switching (prev/next/start in the admin pane)
    # reliably updates what voters see, instead of relying solely on the
    # struct sent in the PubSub payload.
    fresh = Voting.get_session_by_slug(socket.assigns.session.slug)
    {:noreply, apply_session_update(socket, fresh)}
  end

  @impl true
  def handle_info({:show_results_toggled, _session}, socket) do
    fresh = Voting.get_session_by_slug(socket.assigns.session.slug)
    {:noreply, apply_session_update(socket, fresh)}
  end

  @impl true
  def handle_info({:voter_choices_toggled, _session}, socket) do
    fresh = Voting.get_session_by_slug(socket.assigns.session.slug)
    {:noreply, apply_session_update(socket, fresh)}
  end

  def handle_info({:votes_reset, _session_id}, socket) do
    {:noreply, apply_session_update(socket, socket.assigns.session)}
  end

  def handle_info({:state_changed, %Session{} = session}, socket) do
    {:noreply, apply_session_update(socket, session)}
  end

  def handle_info({:vote_cast, _session_id, question_id}, socket) do
    # Only refresh if it affects what we are looking at
    if socket.assigns.current_question && socket.assigns.current_question.id == question_id do
      {:noreply, maybe_refresh_tallies(socket)}
    else
      {:noreply, socket}
    end
  end

  def handle_info({:closed, %Session{} = session}, socket) do
    {:noreply, apply_session_update(socket, session)}
  end

  def handle_info({:reopened, %Session{} = session}, socket) do
    {:noreply, apply_session_update(socket, session)}
  end

  @impl true
  # Ignore global visitor presence (app:visitors topic). VoteLive only cares
  # about its per-session participants Presence (local topic).
  def handle_info(%{topic: "app:visitors", event: "presence_diff"}, socket) do
    {:noreply, socket}
  end

  # Presence diff - refresh the participant list (local per-slug Presence)
  def handle_info(%{event: "presence_diff"}, socket) do
    {:noreply, assign_participants(socket)}
  end

  # Catch-all for owner broadcasts we don't care about here
  def handle_info({action, %Session{}}, socket) when action in [:updated, :created, :deleted] do
    {:noreply, socket}
  end

  # --- Helpers ---

  defp refresh_after_identity(socket) do
    slug = socket.assigns.session.slug

    if connected?(socket) do
      # Ensure we are subscribed to the per-session PubSub for MC-driven updates
      # (current question, show toggles etc.). This is also done in the initial
      # connected mount, but subscribing here (on identity/code grant) makes
      # propagation robust for all viewer flows.
      Voting.subscribe_to_session(slug)

      # Subscribe to presence for this session (if not already)
      topic = Presence.topic(slug)
      SlidexWeb.Endpoint.subscribe(topic)

      key = participant_key(socket)
      meta = participant_meta(socket)

      # Do not track the MC (host) in the participants Presence.
      # Participants list/count should only reflect actual voters.
      if not socket.assigns.is_mc do
        Presence.track_participant(self(), slug, key, meta)
      end
    end

    my_vote_id =
      if socket.assigns.is_mc do
        nil
      else
        Voting.current_vote_for_identity(socket.assigns.session, current_identity(socket))
      end

    socket
    |> assign(:my_vote_id, my_vote_id)
    |> assign_participants()
    |> assign(:can_vote, can_vote_now?(socket))
    |> assign(:voter_choices, Voting.current_voter_choices(socket.assigns.session))
    |> assign(
      :show_results_for_me,
      socket.assigns.is_mc or socket.assigns.session.show_results == true
    )
    |> assign(
      :show_voter_choices_for_me,
      socket.assigns.is_mc or
        (socket.assigns.session.show_results == true and
           socket.assigns.session.show_voter_choices == true)
    )
    |> maybe_refresh_tallies()
    |> maybe_load_leaderboard()
  end

  defp assign_participants(socket) do
    slug = socket.assigns.session.slug
    presences = Presence.list_participants(slug)

    # Do not count the MC (poll owner) in the participants list or count.
    # The MC is the controller/host, not a voter/participant.
    owner_id = socket.assigns.poll.user_id

    participants =
      presences
      |> Enum.reject(fn {key, _} -> key == "user:#{owner_id}" end)
      |> Enum.map(fn {key, %{metas: [meta | _]}} ->
        %{
          id: key,
          seed: meta[:seed] || key,
          label: meta[:label]
        }
      end)
      |> Enum.sort_by(& &1.seed)

    socket
    |> stream(:participants, participants, reset: true)
    |> assign(:participant_count, length(participants))
  end

  defp participant_key(socket) do
    cond do
      user = socket.assigns.current_scope && socket.assigns.current_scope.user ->
        "user:#{user.id}"

      visitor = socket.assigns[:visitor_id] ->
        "visitor:#{visitor}"

      true ->
        # Temporary until hook fires; will be replaced on "visitor-identified"
        "visitor:pending-#{System.unique_integer([:positive])}"
    end
  end

  defp participant_meta(socket) do
    cond do
      user = socket.assigns.current_scope && socket.assigns.current_scope.user ->
        %{seed: user.username || user.email, label: user.username || "Host"}

      visitor = socket.assigns[:visitor_id] ->
        %{seed: visitor, label: "Guest"}

      true ->
        %{seed: "pending", label: "Connecting..."}
    end
  end

  defp current_identity(socket) do
    cond do
      user = socket.assigns.current_scope && socket.assigns.current_scope.user ->
        %{user_id: user.id}

      vid = socket.assigns[:visitor_id] ->
        %{visitor_id: vid}

      true ->
        # Should not happen for voting actions because of guards
        %{visitor_id: "unknown"}
    end
  end

  defp can_vote_now?(socket) do
    socket.assigns.session_open and
      socket.assigns.access_granted and
      not is_nil(socket.assigns.current_question) and
      socket.assigns.session.state == :active and
      not socket.assigns.is_mc
  end

  defp maybe_refresh_tallies(socket) do
    voter_choices = Voting.current_voter_choices(socket.assigns.session)

    if socket.assigns.show_results or socket.assigns.is_mc do
      tallies = Voting.current_tallies(socket.assigns.session)
      total = Enum.reduce(tallies, 0, fn {_k, c}, acc -> acc + c end)

      # We keep the optimistic my_vote_id set by the "vote" event handler.
      # A more complete version could query the latest Result for this identity.
      socket
      |> assign(:tallies, tallies)
      |> assign(:total_votes, total)
      |> assign(:voter_choices, voter_choices)
    else
      socket
      |> assign(:voter_choices, voter_choices)
    end
  end

  defp maybe_load_leaderboard(socket) do
    if socket.assigns.has_correct and socket.assigns.show_results == true do
      # We need all historical results + all questions with options.
      # For a real implementation we would have a dedicated query, but this is fine
      # for the size of demos this app targets.
      session_id = socket.assigns.session.id

      results =
        Result
        |> where([r], r.session_id == ^session_id)
        |> Repo.all()

      # Reload poll questions with options for correctness calculation
      poll =
        Repo.preload(socket.assigns.poll,
          questions: [options: from(o in Option, order_by: o.position)]
        )

      board = Voting.leaderboard(results, poll.questions)

      # Enrich with seeds/labels for the UI (simple: use the key itself as seed)
      enriched =
        Enum.map(board, fn entry ->
          Map.put(entry, :seed, String.replace(entry.key, ~r/^(user|visitor):/, ""))
          |> Map.put(:label, if(entry.kind == :user, do: "Participant", else: "Guest"))
        end)

      assign(socket, :leaderboard, enriched)
    else
      assign(socket, :leaderboard, [])
    end
  end

  defp apply_session_update(socket, %Session{} = session) do
    # Recompute derived state when the session row changes (question, results flag, state, closed, etc)
    poll = session.poll || socket.assigns.poll

    socket =
      socket
      |> assign(:session, session)
      |> assign(:poll, poll)
      |> assign(:session_open, Voting.voting_open?(session))
      |> assign(:show_voting_ui, Voting.voting_open?(session) or socket.assigns.is_mc)
      |> assign(:current_question, session.current_question)
      |> assign(
        :options,
        if(session.current_question, do: session.current_question.options || [], else: [])
      )
      |> assign(:show_results, session.show_results)
      |> assign(:requires_code, not is_nil(session.access_code))
      |> assign(:access_granted, socket.assigns.is_mc or is_nil(session.access_code))
      |> assign(:can_vote, can_vote_now?(socket))
      |> assign_mc_navigation(session, socket.assigns.current_scope)
      |> assign(:voter_choices, Voting.current_voter_choices(session))
      |> assign(:show_results_for_me, socket.assigns.is_mc or session.show_results == true)
      |> assign(
        :show_voter_choices_for_me,
        socket.assigns.is_mc or
          (session.show_results == true and session.show_voter_choices == true)
      )
      |> maybe_refresh_tallies()
      |> maybe_load_leaderboard()
      |> assign_question_surface_id()

    # If MC just advanced the question, clear "my vote" highlight (different question)
    if socket.assigns.current_question && socket.assigns.my_vote_id do
      still_valid? = Enum.any?(socket.assigns.options, &(&1.id == socket.assigns.my_vote_id))

      if still_valid? do
        socket
      else
        assign(socket, :my_vote_id, nil)
      end
    else
      socket
    end
  end

  defp normalize_code(nil), do: ""

  defp normalize_code(code),
    do: code |> to_string() |> String.replace(~r/[^A-Z0-9]/i, "") |> String.upcase()

  defp percent(0, _total), do: 0
  defp percent(_count, 0), do: 0
  defp percent(count, total), do: round(count * 100 / total)

  defp identicon_svg(seed) do
    # Match the style used in the main layout for consistency
    apply(IdenticonSvg, :generate, [seed | @identicon_params])
  end

  @impl true
  def terminate(_reason, socket) do
    # Untrack from Presence. Wrapped to avoid crashes if the tracker
    # is not available during shutdown or if the process is terminating
    # for other reasons (e.g. during development).
    try do
      if slug = socket.assigns[:session] && socket.assigns.session.slug do
        key = participant_key(socket)
        Presence.untrack_participant(self(), slug, key)
      end
    rescue
      _ -> :ok
    end

    :ok
  end
end
