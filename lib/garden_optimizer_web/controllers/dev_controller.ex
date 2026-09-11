defmodule GardenOptimizerWeb.DevController do
  @moduledoc """
  Development conveniences. Routed only when `:dev_routes` is enabled, so this never exists in a
  released build.
  """
  use GardenOptimizerWeb, :controller

  alias GardenOptimizer.Visitors
  alias GardenOptimizerWeb.Plugs.{AccessCode, Visitor}

  @doc """
  Adopt a visitor token, so seeded gardens can actually be opened.

  The session cookie is `http_only` by design, which means nothing in the browser can write it —
  the right call for a credential, and the reason seeding needs a door like this rather than a
  line of console JavaScript.
  """
  def adopt(conn, %{"token" => token}) do
    if Visitors.valid_token?(token) do
      conn
      |> put_session(Visitor.session_key(), token)
      |> put_session(AccessCode.session_key(), true)
      |> put_flash(:info, "Adopted that visitor — seeded gardens should be visible now.")
      |> redirect(to: ~p"/")
    else
      conn
      |> put_flash(:error, "That doesn't look like a visitor token.")
      |> redirect(to: ~p"/")
    end
  end
end
