# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :garden_optimizer,
  ecto_repos: [GardenOptimizer.Repo],
  generators: [timestamp_type: :utc_datetime, binary_id: true]

# Configure the endpoint
config :garden_optimizer, GardenOptimizerWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: GardenOptimizerWeb.ErrorHTML, json: GardenOptimizerWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: GardenOptimizer.PubSub,
  live_view: [signing_salt: "DSPf2UOV"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :garden_optimizer, GardenOptimizer.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  garden_optimizer: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  garden_optimizer: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# External service defaults. Overridden per-environment; secrets come from runtime.exs.
config :garden_optimizer, :frost_api,
  base_url: "https://apis.joelgrant.dev/api/v1",
  req_options: []

config :garden_optimizer, :anthropic,
  base_url: "https://api.anthropic.com",
  model: "claude-haiku-4-5",
  api_key: nil,
  req_options: []

config :garden_optimizer, :page_fetch, req_options: []

# Set in production to close the deployment to invited testers. Unset means the site is open,
# which is what dev and test want.
config :garden_optimizer, :access_code, nil

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
