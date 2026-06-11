defmodule SlidexWeb.Components.Results do
  @moduledoc """
  Shared rendering for a question's vote tally.

  Used by the owner results view and the participant join page (after a session
  ends) so the result breakdown stays in one place. The presenter view keeps its
  own larger, single-question layout for the projector.
  """
  use SlidexWeb, :html

  alias Slidex.Voting.Tally

  @doc """
  Renders a question and its options as a result breakdown: each option with its
  count, percentage, and bar, the correct option flagged, and optionally the
  viewer's own choice.
  """
  attr :question, :map, required: true
  attr :tally, :map, required: true, doc: "a `%{option_id => count}` map for this question"
  attr :my_vote, :string, default: nil, doc: "option id the viewer chose, to flag \"Your vote\""

  def question_results(assigns) do
    ~H"""
    <div id={"result-#{@question.id}"} class="space-y-3">
      <h2 class="text-xl font-semibold">{@question.body}</h2>
      <ul class="space-y-2">
        <li
          :for={option <- @question.options}
          class="rounded-lg border border-base-300 bg-base-100 p-3"
        >
          <div class="flex items-center justify-between gap-2">
            <span class="font-medium">
              {option.body}
              <span :if={option.is_correct} class="badge badge-success badge-sm">
                Correct
              </span>
              <span :if={@my_vote == option.id} class="badge badge-primary badge-sm">
                Your vote
              </span>
            </span>
            <span class="text-sm text-base-content/70">
              {Tally.count(@tally, option.id)} ({Tally.percentage(@tally, option.id)}%)
            </span>
          </div>
          <progress
            class="progress progress-primary mt-2 w-full"
            value={Tally.percentage(@tally, option.id)}
            max="100"
          >
          </progress>
        </li>
      </ul>
    </div>
    """
  end
end
