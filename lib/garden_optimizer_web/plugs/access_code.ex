defmodule GardenOptimizerWeb.Plugs.AccessCode do
  @moduledoc """
  Keeps a public deployment closed to everyone but invited testers.

  This exists because the app is anonymous *and* calls a paid model API: anyone who can reach the
  plant importer can spend money, and visitor tokens are no defence when minting one is free. A
  shared code handed to testers is the smallest thing that closes that door.

  A tester arrives once at `?access=CODE`. The code is recorded in the signed session and the
  request is redirected to the same page without it, so the secret does not linger in browser
  history, bookmarks, or `Referer` headers on the way to the frost and plant APIs.

  With no code configured the site is open, which is what dev and test want. Set one in production
  and configure nothing else.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [redirect: 2]

  @param "access"
  @session_key "access_granted"

  def init(opts), do: opts

  def call(conn, _opts) do
    case configured_code() do
      nil -> conn
      code -> gate(conn, code)
    end
  end

  @doc "Session key recording that a visitor has presented the code."
  def session_key, do: @session_key

  @doc "The code this deployment requires, or nil when the site is open."
  def configured_code do
    case Application.get_env(:garden_optimizer, :access_code) do
      code when is_binary(code) and code != "" -> code
      _ -> nil
    end
  end

  @doc """
  Whether a session has already presented the code.

  The LiveView socket does not run this pipeline — it only receives the session — so the mount
  hook calls this to close the websocket as a way around the gate.
  """
  def granted?(session) when is_map(session) do
    is_nil(configured_code()) or session[@session_key] == true
  end

  defp gate(conn, code) do
    cond do
      get_session(conn, @session_key) == true -> conn
      valid?(conn.params[@param], code) -> grant(conn)
      true -> deny(conn)
    end
  end

  # Constant-time, and only on values of equal length — secure_compare/2 raises otherwise.
  defp valid?(given, code) when is_binary(given) do
    byte_size(given) == byte_size(code) and Plug.Crypto.secure_compare(given, code)
  end

  defp valid?(_given, _code), do: false

  defp grant(conn) do
    conn
    |> put_session(@session_key, true)
    |> redirect(to: path_without_code(conn))
    |> halt()
  end

  defp path_without_code(conn) do
    case conn.query_params |> Map.delete(@param) |> URI.encode_query() do
      "" -> conn.request_path
      query -> conn.request_path <> "?" <> query
    end
  end

  defp deny(conn) do
    conn
    |> put_resp_content_type("text/html")
    |> send_resp(403, """
    <!doctype html>
    <html lang="en">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>Garden Optimizer</title>
        <style>
          body { margin: 0; min-height: 100vh; display: grid; place-items: center;
                 font: 16px/1.6 ui-sans-serif, system-ui, sans-serif; color: #1c2b21;
                 background: #f6f7f4; }
          main { max-width: 26rem; padding: 2rem; text-align: center; }
          h1 { font-size: 1.25rem; margin: 0 0 .5rem; }
          p { margin: 0; color: #5d6b62; }
        </style>
      </head>
      <body>
        <main>
          <h1>This preview is private</h1>
          <p>You need an access code to open it. If you were sent one, use the full link it came with.</p>
        </main>
      </body>
    </html>
    """)
    |> halt()
  end
end
