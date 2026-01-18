defmodule RouterosCmWeb.API.V1.WireGuardControllerTest do
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
        scopes: ["wireguard:read", "wireguard:write"]
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
        |> get(~p"/api/v1/wireguard")

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    end

    test "returns 403 without wireguard:read scope for index" do
      {:ok, wrong_scope_token} =
        ApiAuth.create_token(%{
          name: "DNS Only Token",
          scopes: ["dns:read"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{wrong_scope_token.token}")
        |> get(~p"/api/v1/wireguard")

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end

    test "returns 403 without wireguard:write scope for create" do
      {:ok, read_only_token} =
        ApiAuth.create_token(%{
          name: "Read Only Token",
          scopes: ["wireguard:read"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{read_only_token.token}")
        |> post(~p"/api/v1/wireguard", %{name: "wg-test", "listen-port": "51820"})

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end
  end

  describe "index" do
    test "returns list of WireGuard interfaces (may be empty without nodes)", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/wireguard")

      assert %{"data" => interfaces} = json_response(conn, 200)
      assert is_list(interfaces)
    end
  end

  describe "show" do
    test "returns 404 for non-existent interface", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/wireguard/nonexistent-wg")

      assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end

  describe "create" do
    test "returns error when no nodes available", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/wireguard", %{
          "name" => "wg-test",
          "listen-port" => "51820"
        })

      # Without active nodes, returns 422 with error
      assert %{"error" => error} = json_response(conn, 422)
      assert error["details"]["error"] == "No active nodes available"
    end
  end

  describe "delete" do
    test "returns cluster operation result", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/wireguard/test-wg")

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "delete"
    end
  end

  describe "assign_ip" do
    test "returns 400 when address is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/wireguard/test-wg/ip", %{})

      assert %{"error" => _} = json_response(conn, 400)
    end

    test "accepts valid IP assignment parameters", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/wireguard/test-wg/ip", %{address: "10.0.0.1/24"})

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "assign_ip"
    end
  end

  describe "remove_ip" do
    test "returns cluster operation result", %{conn: conn} do
      # URL-encode the address since it contains /
      conn =
        delete(conn, ~p"/api/v1/wireguard/test-wg/ip/#{URI.encode("10.0.0.1/24", &(&1 != ?/))}")

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "remove_ip"
    end
  end

  describe "list_peers" do
    test "returns list of peers (may be empty)", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/wireguard/test-wg/peers")

      assert %{"data" => peers} = json_response(conn, 200)
      assert is_list(peers)
    end
  end

  describe "create_peer" do
    test "returns 400 when public-key is missing", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/wireguard/test-wg/peers", %{"allowed-address" => "10.0.0.2/32"})

      assert %{"error" => _} = json_response(conn, 400)
    end

    test "returns error when no nodes available", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/wireguard/test-wg/peers", %{
          "public-key" => "dGVzdGtleQ==",
          "allowed-address" => "10.0.0.2/32"
        })

      # Without active nodes, returns 422 with error
      assert %{"error" => error} = json_response(conn, 422)
      assert error["details"]["error"] == "No active nodes available"
    end
  end

  describe "delete_peer" do
    test "returns cluster operation result", %{conn: conn} do
      # URL-encode the public key since it's base64
      conn = delete(conn, ~p"/api/v1/wireguard/test-wg/peers/#{URI.encode("dGVzdGtleQ==")}")

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "delete"
    end
  end

  describe "generate_keypair" do
    test "generates valid WireGuard keypair", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/wireguard/generate-keypair")

      assert %{"data" => data} = json_response(conn, 200)
      assert is_binary(data["private_key"])
      assert is_binary(data["public_key"])

      # Verify they are base64-encoded (44 chars for 32-byte key)
      assert String.length(data["private_key"]) == 44
      assert String.length(data["public_key"]) == 44
    end
  end
end
