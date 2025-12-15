defmodule RouterosCm.Accounts.Scope do
  @moduledoc """
  Defines the scope of the caller to be used throughout the app.

  The `RouterosCm.Accounts.Scope` allows public interfaces to receive
  information about the caller, such as if the call is initiated from an
  end-user, and if so, which user. Additionally, such a scope can carry fields
  such as "super user" or other privileges for use as authorization, or to
  ensure specific code paths can only be access for a given scope.

  It is useful for logging as well as for scoping pubsub subscriptions and
  broadcasts when a caller subscribes to an interface or performs a particular
  action.

  Feel free to extend the fields on this struct to fit the needs of
  growing application requirements.
  """

  alias RouterosCm.Accounts.User
  alias RouterosCm.Accounts.ApiToken

  defstruct user: nil, api_token: nil

  @doc """
  Creates a scope for the given user.

  Returns a scope with nil user if no user is given.
  """
  def for_user(%User{} = user) do
    %__MODULE__{user: user}
  end

  def for_user(nil), do: %__MODULE__{user: nil}

  @doc """
  Creates a scope for an API token.
  """
  def for_api_token(%ApiToken{} = token) do
    %__MODULE__{user: token.user, api_token: token}
  end
end
