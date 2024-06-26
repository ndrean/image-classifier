# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

# DB configuration
config :app,
  ecto_repos: [App.Repo],
  generators: [timestamp_type: :utc_datetime]

# Tells `NX` to use `EXLA` as backend
# config :nx, default_backend: EXLA.Backend
# needed to run on `Fly.io`
config :nx, :default_backend, {EXLA.Backend, client: :host}

# Configures the endpoint
config :app, AppWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [
    formats: [html: AppWeb.ErrorHTML, json: AppWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: App.PubSub,
  live_view: [signing_salt: "euyclMQ2"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.18.6",
  default: [
    args:
      ~w(js/app.js --bundle --target=es2017 --outdir=../priv/static/assets --external:/fonts/* --external:/images/*),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "3.2.4",
  default: [
    args: ~w(
      --config=tailwind.config.js
      --input=css/app.css
      --output=../priv/static/assets/app.css
    ),
    cd: Path.expand("../assets", __DIR__)
  ]

# Configures Elixir's Logger
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# When deploying to `fly.io`, you can delete this or leave it in.
# It only makes sense to set it to `true` if you're changing models
# in deployment.
#
# So, you run `fly deploy` with this set to `true`.
# After deploying, you set it to `false` and deploy it again,
# so the application doesn't download the model again on every restart.
config :app,
  models_cache_dir: ".bumblebee"
