defmodule RouterosCmWeb.API.V1.OpenApiControllerTest do
  use RouterosCmWeb.ConnCase

  describe "spec" do
    test "returns OpenAPI specification without authentication", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/openapi")

      assert %{"openapi" => version, "info" => info, "paths" => paths} = json_response(conn, 200)
      assert version =~ "3."
      assert info["title"] == "RouterOS Cluster Manager API"
      assert is_map(paths)
    end

    test "includes paths structure", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/openapi")

      assert %{"paths" => paths} = json_response(conn, 200)
      # Paths may be empty without full controller annotations,
      # but the structure should exist
      assert is_map(paths)
    end

    test "includes security scheme", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/openapi")

      assert %{"components" => components} = json_response(conn, 200)
      assert Map.has_key?(components["securitySchemes"], "bearer")
    end
  end

  describe "swaggerui" do
    test "returns Swagger UI HTML page", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/docs")

      assert response(conn, 200) =~ "swagger-ui"
      assert response(conn, 200) =~ "RouterOS Cluster Manager API"
      assert get_resp_header(conn, "content-type") |> hd() =~ "text/html"
    end
  end
end
