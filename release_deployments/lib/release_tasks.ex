defmodule ReleaseTasks do
  def migrate do
    {:ok, _} = Application.ensure_all_started(:api)

    Ecto.Migrator.run(
      Api.Repo,
      path("priv/repo/migrations"),
      :up,
      all: true
    )

    # Close process
    :init.stop()
  end

  def seed_database() do
    Code.require_file(path("priv/repo/seeds.exs"))
  end

  defp path(path_string) do
    Application.app_dir(:api, path_string)
  end
end
