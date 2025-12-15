defmodule RouterosCmWeb.API.V1.RouterOSUserControllerTest do
  use RouterosCmWeb.ConnCase

  import RouterosCm.AccountsFixtures

  alias RouterosCm.ApiAuth

  setup %{conn: conn} do
    # Create a user and an API token associated with that user
    user = user_fixture()

    {:ok, token} =
      ApiAuth.create_token_for_user(user, %{
        name: "Test Token",
        scopes: ["users:read", "users:write"]
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
        |> get(~p"/api/v1/routeros-users")

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    end

    test "returns 403 without users:read scope for index" do
      {:ok, wrong_scope_token} =
        ApiAuth.create_token(%{
          name: "DNS Only Token",
          scopes: ["dns:read"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{wrong_scope_token.token}")
        |> get(~p"/api/v1/routeros-users")

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end

    test "returns 403 without users:write scope for create" do
      {:ok, read_only_token} =
        ApiAuth.create_token(%{
          name: "Read Only Token",
          scopes: ["users:read"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{read_only_token.token}")
        |> post(~p"/api/v1/routeros-users", %{name: "testuser", password: "secret"})

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end
  end

  describe "index" do
    test "returns list of RouterOS users (may be empty without nodes)", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/routeros-users")

      assert %{"data" => users} = json_response(conn, 200)
      assert is_list(users)
    end
  end

  describe "show" do
    test "returns 404 for non-existent user", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/routeros-users/nonexistent-user")

      assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end

  describe "create" do
    test "returns 400 when name is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/routeros-users", %{password: "secret"})

      assert %{"error" => _} = json_response(conn, 400)
    end

    test "returns 400 when password is missing", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/routeros-users", %{name: "testuser"})

      assert %{"error" => _} = json_response(conn, 400)
    end

    test "returns cluster operation result", %{conn: conn} do
      conn =
        post(conn, ~p"/api/v1/routeros-users", %{
          name: "api-testuser",
          password: "testpassword123",
          group: "full",
          comment: "Test user via API"
        })

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "create"
      assert response["data"]["resource"] == "routeros_user"
    end
  end

  describe "update" do
    test "returns cluster operation result", %{conn: conn} do
      conn =
        put(conn, ~p"/api/v1/routeros-users/testuser", %{
          group: "read",
          comment: "Updated via API"
        })

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "update"
    end
  end

  describe "delete" do
    test "returns cluster operation result", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/routeros-users/testuser")

      response = json_response(conn, 200)
      assert is_map(response["data"])
      assert response["data"]["operation"] == "delete"
    end
  end

  describe "groups" do
    test "returns list of user groups (may be empty)", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/routeros-users/groups")

      assert %{"data" => groups} = json_response(conn, 200)
      assert is_list(groups)
    end
  end

  describe "active_sessions" do
    test "returns list of active sessions (may be empty)", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/routeros-users/active")

      assert %{"data" => sessions} = json_response(conn, 200)
      assert is_list(sessions)
    end
  end
end
