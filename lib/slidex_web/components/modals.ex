defmodule SlidexWeb.Components.Modals do
  @moduledoc """
  Shared modal components.
  """
  use Phoenix.Component
  use Gettext, backend: SlidexWeb.Gettext
  alias Phoenix.LiveView.JS
  import SlidexWeb.CoreComponents

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}
  attr :closeable, :boolean, default: true
  attr :max_width, :string, default: "md:max-w-3xl"

  slot :inner_block, required: true
  slot :title

  def modal(assigns) do
    ~H"""
    <.portal id={"modal-portal-#{@id}"} target="#modal-root">
      <dialog
        :if={@show}
        id={@id}
        phx-hook="Modal"
        phx-mounted={
          JS.ignore_attributes("open")
          |> JS.dispatch("open-dialog", to: "##{@id}")
          |> JS.focus_first(to: "##{@id}-container")
        }
        phx-remove={
          JS.dispatch("close-dialog", to: "##{@id}")
          |> JS.pop_focus()
          |> JS.transition("dummy-class-to-delay-push-navigate",
            to: "##{@id}",
            time: 300
          )
        }
        data-cancel={@on_cancel}
        data-closeable={@closeable && "true"}
        class="modal"
      >
        <div class={["modal-box p-0 border bg-base-100 border-base-200 text-left", @max_width]}>
          <form :if={@closeable && @title in [nil, []]} method="dialog">
            <button class="btn btn-sm btn-circle btn-ghost absolute right-2 top-2">
              <.icon name="hero-x" />
            </button>
          </form>
          <header
            :if={@title != []}
            class="flex items-center justify-between px-6 pt-4 rounded-t"
          >
            <h3 class="text-left text-lg font-semibold text-base-content">
              {render_slot(@title)}
            </h3>
            <form :if={@closeable} method="dialog">
              <button class="btn btn-sm btn-circle btn-ghost"><.icon name="hero-x-mark" /></button>
            </form>
          </header>

          <.focus_wrap id={"#{@id}-container"} class="px-6 py-0 space-y-6">
            {render_slot(@inner_block)}
          </.focus_wrap>
        </div>

        <form method="dialog" class="modal-backdrop backdrop-blur-sm">
          <button :if={@closeable}>{gettext("close")}</button>
        </form>
      </dialog>
    </.portal>
    """
  end
end
