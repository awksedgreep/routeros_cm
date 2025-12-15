defmodule RouterosCmWeb.API.V1.DNSControllerTest do
  use RouterosCmWeb.ConnCase

  alias RouterosCm.ApiAuth

  setup %{conn: conn} do
    # Create an API token with dns:read and dns:write scopes
    {:ok, token} =
      ApiAuth.create_token(%{
        name: "Test Token",
        scopes: ["dns:read", "dns:write"]
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token.token}")

    %{conn: conn, api_token: token}
  end

  describe "authentication" do
    test "returns 401 without auth token", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> get(~p"/api/v1/dns/records")

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    end

    test "returns 403 without dns:read scope for index" do
      {:ok, wrong_scope_token} =
        ApiAuth.create_token(%{
          name: "Nodes Only Token",
          scopes: ["nodes:read"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{wrong_scope_token.token}")
        |> get(~p"/api/v1/dns/records")

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end

    test "returns 403 without dns:write scope for create" do
      {:ok, read_only_token} =
        ApiAuth.create_token(%{
          name: "Read Only Token",
          scopes: ["dns:read"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{read_only_token.token}")
        |> post(~p"/api/v1/dns/records", %{name: "test.local", address: "192.168.1.1"})

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end
  end

  describe "index" do
    test "returns list of DNS records (may be empty without nodes)", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/dns/records")

      assert %{"data" => records} = json_response(conn, 200)
      assert is_list(records)
    end

    test "accepts type filter parameter", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/dns/records?type=A")

      assert %{"data" => records} = json_response(conn, 200)
      assert is_list(records)
      # All returned records should be type A
      assert Enum.all?(records, &(&1["type"] == "A" or &1["type"] == nil))
    end
  end

  describe "show" do
    test "returns 404 for non-existent record", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/dns/records/nonexistent.local")

      assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end

  describe "create" do
    test "accepts valid DNS record parameters", %{conn: conn} do
      # This will likely fail without actual nodes, but tests the parameter handling
      conn =
        post(conn, ~p"/api/v1/dns/records", %{
          name: "test.local",
          address: "192.168.1.100",
          type: "A",
          ttl: "1d"
        })

      # Will return 200 with successes/failures even if no nodes
      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "create"
      assert response["data"]["resource"] == "dns_record"
    end
  end

  describe "update" do
    test "accepts valid update parameters", %{conn: conn} do
      conn =
        put(conn, ~p"/api/v1/dns/records/test.local", %{
          address: "192.168.1.200"
        })

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "update"
    end
  end

  describe "delete" do
    test "returns cluster operation result", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/dns/records/test.local")

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "delete"
    end
  end

  describe "settings" do
    test "returns error when no nodes available", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/dns/settings")

      # Without active nodes, returns 422 with error
      assert %{"error" => error} = json_response(conn, 422)
      assert error["details"]["error"] == "No active nodes available"
    end
  end

  describe "flush_cache" do
    test "returns cluster operation result", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/dns/cache/flush")

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "flush"
    end
  end
end
