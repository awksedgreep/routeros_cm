defmodule RouterosCmWeb.ApiSpec do
  @moduledoc """
  OpenAPI specification for the RouterOS Cluster Manager API.
  """
  alias OpenApiSpex.{Info, OpenApi, Paths, Server, Components, SecurityScheme}

  @behaviour OpenApi

  @impl OpenApi
  def spec do
    %OpenApi{
      info: %Info{
        title: "RouterOS Cluster Manager API",
        version: "1.0.0",
        description: """
        REST API for managing MikroTik RouterOS clusters.

        ## Authentication

        All API endpoints require Bearer token authentication. Include your API token
        in the Authorization header:

        ```
        Authorization: Bearer <your-api-token>
        ```

        ## Scopes

        API tokens have specific scopes that control access:

        - `nodes:read` - View nodes and cluster information
        - `nodes:write` - Create, update, delete nodes
        - `dns:read` - View DNS records and settings
        - `dns:write` - Manage DNS records and settings
        - `tunnels:read` - View GRE tunnels
        - `tunnels:write` - Manage GRE tunnels
        - `wireguard:read` - View WireGuard interfaces and peers
        - `wireguard:write` - Manage WireGuard interfaces and peers
        - `users:read` - View RouterOS users
        - `users:write` - Manage RouterOS users
        - `audit:read` - View audit logs

        ## Cluster Operations

        Most write operations are performed across all active nodes in the cluster.
        Responses include success/failure information for each node.
        """
      },
      servers: [
        %Server{url: "/api/v1", description: "API v1"}
      ],
      paths: Paths.from_router(RouterosCmWeb.Router),
      components: %Components{
        securitySchemes: %{
          "bearer" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "API Token"
          }
        }
      },
      security: [%{"bearer" => []}]
    }
    |> OpenApiSpex.resolve_schema_modules()
  end
end
