defmodule RouterosCmWeb.API.V1.OpenApiController do
  @moduledoc """
  Controller for serving OpenAPI specification and Swagger UI.
  """
  use RouterosCmWeb, :controller

  alias RouterosCmWeb.ApiSpec

  @doc """
  Renders the OpenAPI specification as JSON.

  GET /api/v1/openapi
  """
  def spec(conn, _params) do
    json(conn, ApiSpec.spec())
  end

  @doc """
  Renders the Swagger UI HTML page.

  GET /api/v1/docs
  """
  def swaggerui(conn, _params) do
    html = """
    <!DOCTYPE html>
    <html lang="en">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0">
      <title>RouterOS Cluster Manager API</title>
      <link rel="stylesheet" type="text/css" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
      <style>
        body { margin: 0; padding: 0; }
        .swagger-ui .topbar { display: none; }
      </style>
    </head>
    <body>
      <div id="swagger-ui"></div>
      <script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
      <script>
        window.onload = function() {
          SwaggerUIBundle({
            url: "/api/v1/openapi",
            dom_id: '#swagger-ui',
            deepLinking: true,
            presets: [
              SwaggerUIBundle.presets.apis,
              SwaggerUIBundle.SwaggerUIStandalonePreset
            ],
            layout: "BaseLayout"
          });
        };
      </script>
    </body>
    </html>
    """

    conn
    |> put_resp_content_type("text/html")
    |> send_resp(200, html)
  end
end
