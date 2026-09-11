defmodule GardenOptimizer.Visitors do
  @moduledoc """
  Anonymous identity: a random token, held by the browser, that owns the gardens made with it.

  The token is minted server-side and stored in Phoenix's signed session cookie. Signed rather
  than encrypted is deliberate — the value is the visitor's own credential, and signing is what
  stops it being forged. The cookie is `http_only`, so page scripts cannot read it.

  Only `hash_token/1` output reaches the database. That way a leaked dump contains no usable
  credentials, and it costs one SHA-256 per request to look up.
  """

  # 32 bytes of `:crypto.strong_rand_bytes/1`. Far beyond guessing, and short enough for a cookie.
  @token_bytes 32

  @doc "Mint a new visitor token."
  @spec new_token() :: String.t()
  def new_token do
    @token_bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  @doc """
  The stored form of a token.

  Hex-encoded SHA-256: fixed width, safe in a `:string` column, and one-way.
  """
  @spec hash_token(String.t()) :: String.t()
  def hash_token(token) when is_binary(token) do
    :crypto.hash(:sha256, token) |> Base.encode16(case: :lower)
  end

  @doc "True when `token` looks like something we minted, before it is used for a lookup."
  @spec valid_token?(term()) :: boolean()
  def valid_token?(token) when is_binary(token) do
    case Base.url_decode64(token, padding: false) do
      {:ok, bytes} -> byte_size(bytes) == @token_bytes
      :error -> false
    end
  end

  def valid_token?(_token), do: false
end
