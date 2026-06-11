defmodule SlidexWeb.Router do
  use SlidexWeb, :router

  import SlidexWeb.UserAuth

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SlidexWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_current_scope_for_user
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :participant do
    plug :ensure_participant_token
  end

  scope "/", SlidexWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  # scope "/api", SlidexWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:slidex, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SlidexWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  ## Authenticated routes

  scope "/", SlidexWeb do
    pipe_through [:browser, :require_authenticated_user]

    live_session :require_authenticated_user,
      on_mount: [{SlidexWeb.UserAuth, :require_authenticated}] do
      live "/users/settings", UserLive.Settings, :edit
      live "/users/settings/confirm-email/:token", UserLive.Settings, :confirm_email

      live "/polls", PollLive.Index, :index
      live "/polls/new", PollLive.Form, :new
      live "/polls/:id", PollLive.Show, :show
      live "/polls/:id/questions", PollLive.Questions, :edit
      live "/polls/:id/edit", PollLive.Form, :edit

      live "/sessions/new", SessionLive.Form, :new
      live "/sessions/:id/edit", SessionLive.Form, :edit
      live "/sessions/:id/present", SessionLive.Present, :present
      live "/sessions/:id/results", SessionLive.Results, :results
    end

    post "/users/update-password", UserSessionController, :update_password
  end

  scope "/", SlidexWeb do
    pipe_through [:browser]

    live_session :current_user,
      on_mount: [{SlidexWeb.UserAuth, :mount_current_scope}] do
      live "/users/register", UserLive.Registration, :new
      live "/users/log-in", UserLive.Login, :new
      live "/users/log-in/:token", UserLive.Confirmation, :new
    end

    post "/users/log-in", UserSessionController, :create
    delete "/users/log-out", UserSessionController, :delete
  end

  ## Public participant routes
  # Mounts the current scope without requiring auth, so guests can join public
  # sessions. The :participant pipeline ensures a stable anonymous voter token.

  scope "/", SlidexWeb do
    pipe_through [:browser, :participant]

    live_session :participant,
      on_mount: [{SlidexWeb.UserAuth, :mount_current_scope}] do
      live "/join/:slug", SessionLive.Join, :join
    end
  end
end
