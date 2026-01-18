defmodule RouterosCmWeb.API.V1.ClusterControllerTest do
  use RouterosCmWeb.ConnCase

  @moduletag :integration

  import RouterosCm.ClusterFixtures

  alias RouterosCm.ApiAuth

  setup %{conn: conn} do
    # Create an API token with nodes:read scope
    {:ok, token} =
      ApiAuth.create_token(%{
        name: "Test Token",
        scopes: ["nodes:read"]
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token.token}")

    %{conn: conn, api_token: token}
  end

  describe "stats" do
    test "returns cluster statistics", %{conn: conn} do
      # Create some test nodes
      _node1 = node_fixture()
      _node2 = node_fixture()

      conn = get(conn, ~p"/api/v1/cluster/stats")

      assert %{"data" => data} = json_response(conn, 200)
      assert is_integer(data["total_nodes"])
      assert is_integer(data["active_nodes"])
      assert is_integer(data["offline_nodes"])
      assert data["total_nodes"] >= 2
    end

    test "returns 401 without auth token", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> get(~p"/api/v1/cluster/stats")

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    end

    test "returns 403 without nodes:read scope" do
      {:ok, wrong_scope_token} =
        ApiAuth.create_token(%{
          name: "DNS Only Token",
          scopes: ["dns:read"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{wrong_scope_token.token}")
        |> get(~p"/api/v1/cluster/stats")

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end
  end

  describe "health" do
    test "returns cluster health information", %{conn: conn} do
      # Create a test node (won't be able to connect, but should handle gracefully)
      _node = node_fixture()

      conn = get(conn, ~p"/api/v1/cluster/health")

      assert %{"data" => data} = json_response(conn, 200)
      assert is_map(data["nodes"])
      assert is_map(data["summary"])
      assert is_integer(data["summary"]["total_nodes"])
      assert is_integer(data["summary"]["healthy_nodes"])
      assert is_integer(data["summary"]["unhealthy_nodes"])
    end
  end
end
