defmodule SlidexWeb.Layouts do
  @moduledoc """
  This module holds layouts and related functionality
  used by your application.
  """
  use SlidexWeb, :html

  # Embed all files in layouts/* within this module.
  # The default root.html.heex file contains the HTML
  # skeleton of your application, namely HTML headers
  # and other static content.
  embed_templates "layouts/*"

  @doc """
  Renders your app layout.

  This function is typically invoked from every template,
  and it often contains your application menu, sidebar,
  or similar.

  ## Examples

      <Layouts.app flash={@flash}>
        <h1>Content</h1>
      </Layouts.app>

  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <header class="navbar px-4 sm:px-6 lg:px-8">
      <div class="flex-1">
        <a href="/" class="flex-1 flex w-fit items-center gap-2">
          <SlidexWeb.Icons.logo />
          <span class="text-2xl font-extrabold tracking-tight text-primary">
            {Slidex.application_name()}
          </span>
          <span class="badge badge-sm badge-soft badge-secondary font-semibold">
            v{Slidex.application_version()}
          </span>
        </a>
      </div>
      <div class="flex-none">
        <ul class="flex flex-column px-1 space-x-4 items-center">
          <li
            class="tooltip tooltip-bottom hidden md:block"
            data-tip="Building the Elixir community in Greece, one line of code at a time."
          >
            <a href="https://greecex.org/" class="btn btn-primary">
              <SlidexWeb.Icons.logo_alt width={10} /> Greece |> Elixir
            </a>
          </li>
          <li
            class="tooltip tooltip-bottom hidden md:block"
            data-tip="Source code"
          >
            <a href="https://github.com/greecex/slidex" class="btn btn-secondary">
              <SlidexWeb.Icons.github />GitHub
            </a>
          </li>
          <li>
            <.theme_toggle />
          </li>
          <li>
            <%= if @current_scope do %>
              <div class="dropdown dropdown-end">
                <div tabindex="0" role="button" class="btn btn-ghost m-1 p-0 hover:none">
                  {Phoenix.HTML.raw(
                    IdenticonSvg.generate(
                      @current_scope.user.username,
                      7,
                      :split2,
                      1.0,
                      2,
                      squircle_curvature: 0.8
                    )
                  )}
                </div>
                <ul
                  tabindex="-1"
                  class="dropdown-content menu bg-base-100 rounded-box z-1 w-52 p-2 shadow-sm"
                >
                  <li class="pointer-events-none cursor-none">
                    <div class="text-start flex flex-col items-start gap-0">
                      <div class="text-md font-semibold text-primary text-start">
                        {@current_scope.user.username}
                      </div>
                      <div class="text-xs text-start">{@current_scope.user.email}</div>
                    </div>
                  </li>
                  <div class="divider divider-y divider-neutral/50 py-0 px-2 my-0" />

                  <li>
                    <.link navigate={~p"/users/settings"}>
                      <.icon name="hero-cog-8-tooth" class="size-5" />Settings
                    </.link>
                  </li>
                  <li>
                    <.link
                      href={~p"/users/log-out"}
                      method="delete"
                      class="hover:bg-red-200 hover:text-red-700"
                    >
                      <.icon name="hero-arrow-left-start-on-rectangle" class="size-5" />Log out
                    </.link>
                  </li>
                </ul>
              </div>
            <% end %>
          </li>
        </ul>
      </div>
    </header>

    <main class="px-4 py-8 sm:px-6 lg:px-8">
      <div class="mx-auto max-w-2xl space-y-4">
        {render_slot(@inner_block)}
      </div>
      
    <!-- Global visitor identity hook (LocalStorage) for presence tracking across all LiveViews -->
      <div
        id="visitor-identity"
        phx-hook="VisitorIdentity"
        phx-update="ignore"
        class="hidden"
      >
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.

  ## Examples

      <.flash_group flash={@flash} />
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  Provides dark vs light theme toggle based on themes defined in app.css.

  See <head> in root.html.heex which applies the theme before page load.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="card relative flex flex-row items-center border-2 border-base-300 bg-base-300 rounded-full">
      <div class="absolute w-1/3 h-full rounded-full border-1 border-base-200 bg-base-100 brightness-200 left-0 [[data-theme=light]_&]:left-1/3 [[data-theme=dark]_&]:left-2/3 transition-[left]" />

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>

      <button
        class="flex p-2 cursor-pointer w-1/3"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4 opacity-75 hover:opacity-100" />
      </button>
    </div>
    """
  end
end
