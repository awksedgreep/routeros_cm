defmodule RouterosCmWeb.API.V1.NodeControllerTest do
  use RouterosCmWeb.ConnCase

  import RouterosCm.ClusterFixtures

  alias RouterosCm.ApiAuth

  setup %{conn: conn} do
    # Create an API token with nodes:read and nodes:write scopes
    {:ok, token} =
      ApiAuth.create_token(%{
        name: "Test Token",
        scopes: ["nodes:read", "nodes:write"]
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token.token}")

    %{conn: conn, api_token: token}
  end

  describe "index" do
    test "lists all nodes", %{conn: conn} do
      node = node_fixture()
      conn = get(conn, ~p"/api/v1/nodes")

      assert %{"data" => nodes} = json_response(conn, 200)
      assert length(nodes) >= 1
      assert Enum.any?(nodes, &(&1["id"] == node.id))
    end

    test "returns 401 without auth token", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> get(~p"/api/v1/nodes")

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    end
  end

  describe "show" do
    test "returns a specific node", %{conn: conn} do
      node = node_fixture()
      conn = get(conn, ~p"/api/v1/nodes/#{node.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == node.id
      assert data["name"] == node.name
      assert data["host"] == node.host
    end

    test "returns 404 for non-existent node", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/nodes/999999")

      assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end

  describe "create" do
    test "creates a node with valid params", %{conn: conn} do
      params = %{
        name: "test-node-api",
        host: "192.168.1.100",
        port: 8728,
        username: "admin",
        password: "secret"
      }

      conn = post(conn, ~p"/api/v1/nodes", params)

      assert %{"data" => data} = json_response(conn, 201)
      assert data["name"] == "test-node-api"
      assert data["host"] == "192.168.1.100"
      assert data["port"] == 8728
    end

    test "returns validation error for missing required fields", %{conn: conn} do
      conn = post(conn, ~p"/api/v1/nodes", %{name: "incomplete"})

      assert %{"error" => %{"code" => "validation_error"}} = json_response(conn, 422)
    end

    test "returns 403 without write scope" do
      {:ok, read_only_token} =
        ApiAuth.create_token(%{
          name: "Read Only Token",
          scopes: ["nodes:read"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{read_only_token.token}")
        |> post(~p"/api/v1/nodes", %{name: "test"})

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end
  end

  describe "update" do
    test "updates a node with valid params", %{conn: conn} do
      node = node_fixture()

      conn =
        put(conn, ~p"/api/v1/nodes/#{node.id}", %{
          name: "updated-name",
          username: "admin",
          password: "new-password"
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["name"] == "updated-name"
    end

    test "returns 404 for non-existent node", %{conn: conn} do
      conn = put(conn, ~p"/api/v1/nodes/999999", %{name: "updated"})

      assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end

  describe "delete" do
    test "deletes a node", %{conn: conn} do
      node = node_fixture()
      conn = delete(conn, ~p"/api/v1/nodes/#{node.id}")

      assert conn.status == 204

      # Verify node is deleted
      assert RouterosCm.Cluster.get_node(node.id) == nil
    end

    test "returns 404 for non-existent node", %{conn: conn} do
      conn = delete(conn, ~p"/api/v1/nodes/999999")

      assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end
end
