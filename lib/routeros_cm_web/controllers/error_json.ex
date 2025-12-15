defmodule RouterosCmWeb.ErrorJSON do
  @moduledoc """
  This module is invoked by your endpoint in case of errors on JSON requests.

  See config/config.exs.
  """

  @doc """
  Renders JSON error responses for various HTTP status codes.

  Supported templates:
  - `400.json` - Bad Request (accepts optional `:reason` assign)
  - `401.json` - Unauthorized (accepts optional `:message` assign)
  - `403.json` - Forbidden (accepts optional `:scope` assign)
  - `404.json` - Not Found (accepts optional `:resource` assign)
  - `422.json` - Validation Error (accepts `:changeset` or `:errors` assign)
  - `500.json` - Internal Server Error
  """
  def render(template, assigns \\ %{})

  def render("400.json", %{reason: reason}) do
    %{error: %{code: "bad_request", message: reason}}
  end

  def render("400.json", _assigns) do
    %{error: %{code: "bad_request", message: "Bad request"}}
  end

  def render("401.json", %{message: message}) do
    %{error: %{code: "unauthorized", message: message}}
  end

  def render("401.json", _assigns) do
    %{error: %{code: "unauthorized", message: "Invalid or missing API token"}}
  end

  def render("403.json", %{scope: scope}) do
    %{error: %{code: "forbidden", message: "Token lacks required scope: #{scope}"}}
  end

  def render("403.json", _assigns) do
    %{error: %{code: "forbidden", message: "Access denied"}}
  end

  def render("404.json", %{resource: resource}) do
    %{error: %{code: "not_found", message: "#{resource} not found"}}
  end

  def render("404.json", _assigns) do
    %{error: %{code: "not_found", message: "Resource not found"}}
  end

  def render("422.json", %{changeset: changeset}) do
    %{error: %{code: "validation_error", details: format_changeset_errors(changeset)}}
  end

  def render("422.json", %{errors: errors}) do
    %{error: %{code: "validation_error", details: errors}}
  end

  def render("422.json", _assigns) do
    %{error: %{code: "validation_error", message: "Invalid request parameters"}}
  end

  def render("500.json", _assigns) do
    %{error: %{code: "internal_error", message: "An unexpected error occurred"}}
  end

  # Default fallback - renders based on template name
  def render(template, _assigns) do
    %{error: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end

  # Helper to format changeset errors into a friendly map
  defp format_changeset_errors(changeset) do
    Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
      Regex.replace(~r"%{(\w+)}", msg, fn _, key ->
        opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
      end)
    end)
  end
end
