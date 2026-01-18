defmodule RouterosCm.DopplerConfigProvider do
  @moduledoc """
  A custom config provider for Doppler secrets management.

  This provider fetches configuration from Doppler at runtime when a DOPPLER_TOKEN
  environment variable is present. It's designed to be modern, efficient, and
  free from deprecated function warnings.
  """

  @behaviour Config.Provider
  require Logger

  @impl Config.Provider
  def init(opts), do: opts

  @impl Config.Provider
  def load(config, _opts) do
    case System.get_env("DOPPLER_TOKEN") do
      nil ->
        Logger.info(
          "[DopplerConfigProvider] DOPPLER_TOKEN not found, skipping Doppler configuration"
        )

        config

      token ->
        Logger.info("[DopplerConfigProvider] Loading configuration from Doppler")
        fetch_and_merge_config(config, token)
    end
  end

  defp fetch_and_merge_config(config, token) do
    case fetch_doppler_secrets(token) do
      {:ok, secrets} ->
        Logger.info(
          "[DopplerConfigProvider] Successfully loaded #{map_size(secrets)} secrets from Doppler"
        )

        merge_doppler_config(config, secrets)

      {:error, reason} ->
        Logger.error(
          "[DopplerConfigProvider] Failed to fetch secrets from Doppler: #{inspect(reason)}"
        )

        config
    end
  end

  defp fetch_doppler_secrets(token) do
    url = "https://api.doppler.com/v3/configs/config/secrets/download?format=json"

    headers = [
      {"Authorization", "Bearer #{token}"},
      {"Accept", "application/json"},
      {"User-Agent", "RouterosCm/1.0"}
    ]

    case :httpc.request(:get, {String.to_charlist(url), headers}, [], []) do
      {:ok, {{_, 200, _}, _headers, body}} ->
        case Jason.decode(List.to_string(body)) do
          {:ok, secrets} -> {:ok, secrets}
          {:error, reason} -> {:error, {:json_decode_error, reason}}
        end

      {:ok, {{_, status_code, _}, _headers, body}} ->
        {:error, {:http_error, status_code, List.to_string(body)}}

      {:error, reason} ->
        {:error, {:request_error, reason}}
    end
  end

  defp merge_doppler_config(config, secrets) do
    doppler_config = build_config_from_secrets(secrets)
    Config.Reader.merge(config, doppler_config)
  end

  defp build_config_from_secrets(secrets) do
    [
      routeros_cm: build_app_config(secrets),
      logger: build_logger_config(secrets)
    ]
  end

  defp build_app_config(secrets) do
    []
    |> maybe_add_repo_config(secrets)
    |> maybe_add_endpoint_config(secrets)
    |> maybe_add_credential_config(secrets)
    |> maybe_add_container_config(secrets)
    |> maybe_add_mailer_config(secrets)
    |> maybe_add_feature_config(secrets)
    |> maybe_add_rate_limit_config(secrets)
    |> maybe_add_monitoring_config(secrets)
    |> maybe_add_dns_cluster_config(secrets)
  end

  defp maybe_add_repo_config(config, secrets) do
    base_config =
      []
      |> maybe_put(:url, get_secret(secrets, "DATABASE_URL"))
      |> maybe_put(:pool_size, get_integer_secret(secrets, "POOL_SIZE") || 10)

    # Add IPv6 support if enabled
    repo_config =
      case get_boolean_secret(secrets, "ECTO_IPV6") do
        true -> Keyword.put(base_config, :socket_options, [:inet6])
        _ -> base_config
      end

    if get_secret(secrets, "DATABASE_URL") != nil do
      Keyword.put(config, RouterosCm.Repo, repo_config)
    else
      config
    end
  end

  defp maybe_add_endpoint_config(config, secrets) do
    url_config =
      []
      |> maybe_put(:host, get_secret(secrets, "PHX_HOST"))
      |> maybe_put(:port, get_integer_secret(secrets, "URL_PORT"))
      |> maybe_put(:scheme, get_secret(secrets, "URL_SCHEME"))

    http_config =
      []
      |> maybe_put(:port, get_integer_secret(secrets, "PORT"))
      |> maybe_put(:ip, {0, 0, 0, 0, 0, 0, 0, 0})

    endpoint_config =
      []
      |> maybe_put(:secret_key_base, get_secret(secrets, "SECRET_KEY_BASE"))
      |> maybe_put(:server, get_boolean_secret(secrets, "PHX_SERVER"))
      |> maybe_put_if_not_empty(:url, url_config)
      |> maybe_put_if_not_empty(:http, http_config)

    if endpoint_config != [] do
      Keyword.put(config, RouterosCmWeb.Endpoint, endpoint_config)
    else
      config
    end
  end

  defp maybe_add_credential_config(config, secrets) do
    case get_secret(secrets, "CREDENTIAL_KEY") do
      nil -> config
      key -> Keyword.put(config, :credential_encryption_key, key)
    end
  end

  defp maybe_add_container_config(config, secrets) do
    container_config =
      []
      |> maybe_put(:registry, get_secret(secrets, "CONTAINER_REGISTRY"))
      |> maybe_put(:namespace, get_secret(secrets, "CONTAINER_NAMESPACE"))
      |> maybe_put(:image_name, get_secret(secrets, "CONTAINER_IMAGE_NAME"))

    if container_config != [] do
      Keyword.put(config, :container, container_config)
    else
      config
    end
  end

  defp maybe_add_mailer_config(config, secrets) do
    mailer_config =
      []
      |> maybe_put(:adapter, Swoosh.Adapters.SMTP)
      |> maybe_put(:relay, get_secret(secrets, "SMTP_HOST"))
      |> maybe_put(:port, get_integer_secret(secrets, "SMTP_PORT"))
      |> maybe_put(:username, get_secret(secrets, "SMTP_USERNAME"))
      |> maybe_put(:password, get_secret(secrets, "SMTP_PASSWORD"))
      |> maybe_put(:ssl, get_boolean_secret(secrets, "SMTP_SSL"))
      |> maybe_put(:tls, :if_available)
      |> maybe_put(:auth, :if_available)

    if has_smtp_config?(secrets) do
      Keyword.put(config, RouterosCm.Mailer, mailer_config)
    else
      config
    end
  end

  defp maybe_add_feature_config(config, secrets) do
    feature_config =
      []
      |> maybe_put(:enable_registration, get_boolean_secret(secrets, "ENABLE_REGISTRATION"))
      |> maybe_put(:enable_password_reset, get_boolean_secret(secrets, "ENABLE_PASSWORD_RESET"))
      |> maybe_put(
        :enable_email_verification,
        get_boolean_secret(secrets, "ENABLE_EMAIL_VERIFICATION")
      )

    if feature_config != [] do
      Keyword.put(config, :features, feature_config)
    else
      config
    end
  end

  defp maybe_add_rate_limit_config(config, secrets) do
    rate_limit_config =
      []
      |> maybe_put(:login_attempts, get_integer_secret(secrets, "RATE_LIMIT_LOGIN_ATTEMPTS"))
      |> maybe_put(:api_requests, get_integer_secret(secrets, "RATE_LIMIT_API_REQUESTS"))

    if rate_limit_config != [] do
      Keyword.put(config, :rate_limiting, rate_limit_config)
    else
      config
    end
  end

  defp maybe_add_monitoring_config(config, secrets) do
    case get_secret(secrets, "SENTRY_DSN") do
      nil -> config
      dsn -> Keyword.put(config, :sentry_dsn, dsn)
    end
  end

  defp maybe_add_dns_cluster_config(config, secrets) do
    case get_secret(secrets, "DNS_CLUSTER_QUERY") do
      nil -> config
      query -> Keyword.put(config, :dns_cluster_query, query)
    end
  end

  defp build_logger_config(secrets) do
    case get_atom_secret(secrets, "LOG_LEVEL") do
      nil -> []
      level -> [level: level]
    end
  end

  # Helper functions for secret extraction and type conversion
  defp get_secret(secrets, key) do
    case Map.get(secrets, key) do
      nil -> nil
      "" -> nil
      value when is_binary(value) -> String.trim(value)
      value -> value
    end
  end

  defp get_integer_secret(secrets, key) do
    case get_secret(secrets, key) do
      nil ->
        nil

      value when is_binary(value) ->
        case Integer.parse(value) do
          {int, ""} ->
            int

          _ ->
            Logger.warning(
              "[DopplerConfigProvider] Invalid integer value for #{key}: #{inspect(value)}"
            )

            nil
        end

      value when is_integer(value) ->
        value

      _ ->
        nil
    end
  end

  defp get_boolean_secret(secrets, key) do
    case get_secret(secrets, key) do
      nil -> nil
      value when value in ~w[true TRUE True 1 yes YES Yes on ON On] -> true
      value when value in ~w[false FALSE False 0 no NO No off OFF Off] -> false
      _ -> nil
    end
  end

  defp get_atom_secret(secrets, key) do
    case get_secret(secrets, key) do
      nil ->
        nil

      value when is_binary(value) ->
        try do
          String.to_existing_atom(value)
        rescue
          ArgumentError ->
            Logger.warning(
              "[DopplerConfigProvider] Invalid atom value for #{key}: #{inspect(value)}"
            )

            nil
        end

      _ ->
        nil
    end
  end

  defp maybe_put(config, _key, nil), do: config
  defp maybe_put(config, key, value), do: Keyword.put(config, key, value)

  defp maybe_put_if_not_empty(config, _key, []), do: config

  defp maybe_put_if_not_empty(config, key, value) when is_list(value) and length(value) > 0,
    do: Keyword.put(config, key, value)

  defp maybe_put_if_not_empty(config, _key, _value), do: config

  defp has_smtp_config?(secrets) do
    get_secret(secrets, "SMTP_HOST") != nil
  end
end
