defmodule RouterosCmWeb.API.V1.GREControllerTest do
  use RouterosCmWeb.ConnCase

  @moduletag :integration

  import RouterosCm.AccountsFixtures

  alias RouterosCm.ApiAuth

  setup %{conn: conn} do
    # Create a user and an API token associated with that user
    # (needed because Tunnels context audit logging requires user.id)
    user = user_fixture()

    {:ok, token} =
      ApiAuth.create_token_for_user(user, %{
        name: "Test Token",
        scopes: ["tunnels:read", "tunnels:write"]
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token.token}")

    %{conn: conn, api_token: token, user: user}
  end

  describe "authentication" do
    test "returns 401 without auth token", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> get(~p"/api/v1/gre")

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    end

    test "returns 403 without tunnels:read scope for index" do
      {:ok, wrong_scope_token} =
        ApiAuth.create_token(%{
          name: "DNS Only Token",
          scopes: ["dns:read"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{wrong_scope_token.token}")
        |> get(~p"/api/v1/gre")

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end

    test "returns 403 without tunnels:write scope for create" do
      {:ok, read_only_token} =
        ApiAuth.create_token(%{
          name: "Read Only Token",
          scopes: ["tunnels:read"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{read_only_token.token}")
        |> post(~p"/api/v1/gre", %{
          name: "test-gre",
          "local-address": "192.168.1.1",
          "remote-address": "10.0.0.1"
        })

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end
  end

  describe "index" do
    test "returns list of GRE interfaces (may be empty without nodes)", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/gre")

      assert %{"data" => interfaces} = json_response(conn, 200)
      assert is_list(interfaces)
    end
  end

  describe "show" do
    test "returns 404 for non-existent interface", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/gre/nonexistent-gre")

      assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end

  describe "create" do
    test "accepts valid GRE interface parameters", %{conn: conn} do
      # This will likely fail without actual nodes, but tests the parameter handling
      conn =
        post(conn, ~p"/api/v1/gre", %{
          "name" => "gre-test",
          "local-address" => "192.168.1.1",
          "remote-address" => "10.0.0.1",
          "mtu" => "1476"
        })

      # Will return 200 with successes/failures even if no nodes
      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "create"
      assert response["data"]["resource"] == "gre_interface"
    end
  end

  describe "delete" do
    test "returns cluster operation result", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/gre/test-gre")

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "delete"
    end
  end

  describe "assign_ip" do
    test "returns 400 when address is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/gre/test-gre/ip", %{})

      assert %{"error" => _} = json_response(conn, 400)
    end

    test "accepts valid IP assignment parameters", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/gre/test-gre/ip", %{address: "172.16.0.1/30"})

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "assign_ip"
    end
  end

  describe "remove_ip" do
    test "returns cluster operation result", %{conn: conn} do
      # URL-encode the address since it contains /
      conn = delete(conn, ~p"/api/v1/gre/test-gre/ip/#{URI.encode("172.16.0.1/30", &(&1 != ?/))}")

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "remove_ip"
    end
  end
end
