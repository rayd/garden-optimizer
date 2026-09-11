defmodule GardenOptimizerWeb.VisitorHook do
  @moduledoc """
  Puts the visitor's scope on every LiveView as `current_scope`.

  `GardenOptimizerWeb.Plugs.Visitor` has already guaranteed a token in the session by the time any
  LiveView mounts, so this only has to read it. A session without one means the socket was
  established outside the browser pipeline, which should not happen — treated as no access rather
  than quietly minting a token a browser would never receive.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [redirect: 2]

  alias GardenOptimizer.Visitors
  alias GardenOptimizer.Visitors.Scope
  alias GardenOptimizerWeb.Plugs.AccessCode
  alias GardenOptimizerWeb.Plugs.Visitor

  def on_mount(:default, _params, session, socket) do
    # A websocket connect never runs the browser pipeline — it is handed the session and nothing
    # else — so the access gate has to be re-checked here or it is trivially routed around.
    if AccessCode.granted?(session) do
      assign_scope(session, socket)
    else
      {:halt, redirect(socket, to: "/")}
    end
  end

  defp assign_scope(session, socket) do
    case session[Visitor.session_key()] do
      token when is_binary(token) ->
        if Visitors.valid_token?(token) do
          {:cont, assign(socket, :current_scope, Scope.for_token(token))}
        else
          {:halt, redirect(socket, to: "/")}
        end

      _ ->
        {:halt, redirect(socket, to: "/")}
    end
  end
end
