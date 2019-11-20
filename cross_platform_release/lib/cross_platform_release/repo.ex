defmodule CrossPlatformRelease.Repo do
  use Ecto.Repo,
    otp_app: :cross_platform_release,
    adapter: Ecto.Adapters.Postgres
end
