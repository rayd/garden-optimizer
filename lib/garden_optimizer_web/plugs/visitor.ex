defmodule GardenOptimizerWeb.Plugs.Visitor do
  @moduledoc """
  Gives every browser a visitor token, minting one on first arrival.

  This runs on the ordinary HTTP request rather than in the LiveView, because the session is
  established during the dead render and the websocket then inherits it. Doing it here also means
  the first page a visitor ever loads already knows who they are, with no second render.

  A token is only written when one is missing or malformed, so a returning visitor keeps theirs
  and responses do not carry a pointless Set-Cookie.
  """

  import Plug.Conn

  alias GardenOptimizer.Visitors

  @session_key "visitor_token"

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_session(conn, @session_key) do
      token when is_binary(token) ->
        if Visitors.valid_token?(token), do: conn, else: put_new_token(conn)

      _ ->
        put_new_token(conn)
    end
  end

  @doc "Session key the visitor token is stored under."
  def session_key, do: @session_key

  defp put_new_token(conn) do
    put_session(conn, @session_key, Visitors.new_token())
  end
end
