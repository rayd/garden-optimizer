defmodule GardenOptimizerWeb.Router do
  use GardenOptimizerWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {GardenOptimizerWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug :fetch_query_params
    plug GardenOptimizerWeb.Plugs.AccessCode
    plug GardenOptimizerWeb.Plugs.Visitor
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", GardenOptimizerWeb do
    pipe_through :browser

    live_session :visitor, on_mount: GardenOptimizerWeb.VisitorHook do
      live "/", GardenLive.Index, :index
      live "/gardens/new", GardenLive.New, :new
      live "/gardens/:id", GardenLive.Show, :show
      live "/gardens/:id/schedule", ScheduleLive.Show, :show
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", GardenOptimizerWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:garden_optimizer, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      # Lets `mix run priv/repo/seeds.exs` hand you the seeded garden's visitor token, which the
      # browser cannot set itself because the session cookie is http_only.
      get "/adopt/:token", GardenOptimizerWeb.DevController, :adopt

      live_dashboard "/dashboard", metrics: GardenOptimizerWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end
end
