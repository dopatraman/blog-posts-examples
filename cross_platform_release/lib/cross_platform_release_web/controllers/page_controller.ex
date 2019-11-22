defmodule CrossPlatformReleaseWeb.PageController do
  use CrossPlatformReleaseWeb, :controller

  def index(conn, _params) do
    render(conn, "index.html")
  end
end
