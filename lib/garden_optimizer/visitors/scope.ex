defmodule GardenOptimizer.Visitors.Scope do
  @moduledoc """
  Who is acting, for a tool that asks nobody to register.

  A visitor is a random token their browser holds in a signed session cookie. There is no account,
  no email, and no password — the token *is* the identity, and holding it is what grants access to
  the gardens created with it.

  The struct carries both the token and its hash so callers never have to remember which one the
  database stores. Only the hash is ever written down.

  This follows Phoenix's `current_scope` convention, so if real accounts ever arrive they slot in
  here rather than rippling through every context call.
  """

  alias GardenOptimizer.Visitors

  @enforce_keys [:token, :hash]
  defstruct [:token, :hash]

  @type t :: %__MODULE__{token: String.t(), hash: String.t()}

  @doc "Build a scope for an existing token."
  @spec for_token(String.t()) :: t()
  def for_token(token) when is_binary(token) do
    %__MODULE__{token: token, hash: Visitors.hash_token(token)}
  end
end
