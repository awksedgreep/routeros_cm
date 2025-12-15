defmodule RouterosCmWeb.API.V1.Integration.FullFlowTest do
  @moduledoc """
  Integration tests for full API provisioning flows.

  These tests verify that multiple API operations can be performed
  in sequence as they would be in a real provisioning scenario.
  """
  use RouterosCmWeb.ConnCase

  import RouterosCm.AccountsFixtures
  import RouterosCm.ClusterFixtures

  alias RouterosCm.ApiAuth

  setup %{conn: conn} do
    # Create a user with full access token
    user = user_fixture()

    {:ok, token} =
      ApiAuth.create_token_for_user(user, %{
        name: "Full Access Token",
        scopes: [
          "nodes:read",
          "nodes:write",
          "dns:read",
          "dns:write",
          "tunnels:read",
          "tunnels:write",
          "wireguard:read",
          "wireguard:write",
          "users:read",
          "users:write",
          "audit:read"
        ]
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token.token}")

    %{conn: conn, api_token: token, user: user}
  end

  describe "node management flow" do
    test "can create, list, update, and delete a node", %{conn: conn} do
      # Step 1: Create a node
      create_params = %{
        name: "integration-test-node",
        host: "192.168.100.1",
        port: 8728,
        username: "admin",
        password: "testpassword"
      }

      conn_create = post(conn, ~p"/api/v1/nodes", create_params)
      assert %{"data" => created_node} = json_response(conn_create, 201)
      assert created_node["name"] == "integration-test-node"
      node_id = created_node["id"]

      # Step 2: List nodes and verify our node is there
      conn_list = get(conn, ~p"/api/v1/nodes")
      assert %{"data" => nodes} = json_response(conn_list, 200)
      assert Enum.any?(nodes, &(&1["id"] == node_id))

      # Step 3: Get the specific node
      conn_show = get(conn, ~p"/api/v1/nodes/#{node_id}")
      assert %{"data" => shown_node} = json_response(conn_show, 200)
      assert shown_node["id"] == node_id
      assert shown_node["name"] == "integration-test-node"

      # Step 4: Update the node
      update_params = %{
        name: "updated-integration-node",
        username: "admin",
        password: "newpassword"
      }

      conn_update = put(conn, ~p"/api/v1/nodes/#{node_id}", update_params)
      assert %{"data" => updated_node} = json_response(conn_update, 200)
      assert updated_node["name"] == "updated-integration-node"

      # Step 5: Delete the node
      conn_delete = delete(conn, ~p"/api/v1/nodes/#{node_id}")
      assert conn_delete.status == 204

      # Step 6: Verify node is gone
      conn_verify = get(conn, ~p"/api/v1/nodes/#{node_id}")
      assert json_response(conn_verify, 404)
    end
  end

  describe "cluster health monitoring flow" do
    test "can check cluster health and stats", %{conn: conn} do
      # Create some test nodes first
      _node1 = node_fixture(%{name: "health-test-node-1"})
      _node2 = node_fixture(%{name: "health-test-node-2"})

      # Check cluster stats
      conn_stats = get(conn, ~p"/api/v1/cluster/stats")
      assert %{"data" => stats} = json_response(conn_stats, 200)
      assert is_integer(stats["total_nodes"])
      assert stats["total_nodes"] >= 2

      # Check cluster health
      conn_health = get(conn, ~p"/api/v1/cluster/health")
      assert %{"data" => health} = json_response(conn_health, 200)
      assert is_map(health["nodes"])
      assert is_map(health["summary"])
    end
  end

  describe "DNS management flow" do
    test "can list and filter DNS records", %{conn: conn} do
      # List all DNS records
      conn_list = get(conn, ~p"/api/v1/dns/records")
      assert %{"data" => records} = json_response(conn_list, 200)
      assert is_list(records)

      # Filter by type
      conn_filtered = get(conn, ~p"/api/v1/dns/records?type=A")
      assert %{"data" => filtered_records} = json_response(conn_filtered, 200)
      assert is_list(filtered_records)
    end

    test "can perform DNS CRUD operations", %{conn: conn} do
      # Create a DNS record
      create_params = %{
        name: "integration-test.local",
        address: "192.168.1.100",
        type: "A",
        ttl: "1d"
      }

      conn_create = post(conn, ~p"/api/v1/dns/records", create_params)
      assert %{"data" => result} = json_response(conn_create, 200)
      assert result["operation"] == "create"

      # Update the DNS record
      update_params = %{address: "192.168.1.200"}
      conn_update = put(conn, ~p"/api/v1/dns/records/integration-test.local", update_params)
      assert %{"data" => update_result} = json_response(conn_update, 200)
      assert update_result["operation"] == "update"

      # Delete the DNS record
      conn_delete = delete(conn, ~p"/api/v1/dns/records/integration-test.local")
      assert %{"data" => delete_result} = json_response(conn_delete, 200)
      assert delete_result["operation"] == "delete"
    end

    test "can flush DNS cache", %{conn: conn} do
      conn_flush = post(conn, ~p"/api/v1/dns/cache/flush")
      assert %{"data" => result} = json_response(conn_flush, 200)
      assert result["operation"] == "flush"
    end
  end

  describe "WireGuard management flow" do
    test "can generate keypair", %{conn: conn} do
      conn_keypair = post(conn, ~p"/api/v1/wireguard/generate-keypair")
      assert %{"data" => keypair} = json_response(conn_keypair, 200)
      assert is_binary(keypair["private_key"])
      assert is_binary(keypair["public_key"])
      # WireGuard keys are base64-encoded 32 bytes = 44 characters
      assert String.length(keypair["private_key"]) == 44
      assert String.length(keypair["public_key"]) == 44
    end

    test "can list WireGuard interfaces and peers", %{conn: conn} do
      # List interfaces
      conn_list = get(conn, ~p"/api/v1/wireguard")
      assert %{"data" => interfaces} = json_response(conn_list, 200)
      assert is_list(interfaces)

      # List peers for a hypothetical interface
      conn_peers = get(conn, ~p"/api/v1/wireguard/wg0/peers")
      assert %{"data" => peers} = json_response(conn_peers, 200)
      assert is_list(peers)
    end
  end

  describe "audit log flow" do
    test "can query audit logs with filtering and pagination", %{conn: conn} do
      # List all audit logs
      conn_list = get(conn, ~p"/api/v1/audit")
      assert %{"data" => logs, "meta" => meta} = json_response(conn_list, 200)
      assert is_list(logs)
      assert is_integer(meta["total"])

      # Paginated query
      conn_paginated = get(conn, ~p"/api/v1/audit?page=1&per_page=5")
      assert %{"data" => paginated_logs, "meta" => paginated_meta} = json_response(conn_paginated, 200)
      assert length(paginated_logs) <= 5
      assert paginated_meta["per_page"] == 5

      # Filter by success
      conn_success = get(conn, ~p"/api/v1/audit?success=true")
      assert %{"data" => success_logs} = json_response(conn_success, 200)
      assert Enum.all?(success_logs, &(&1["success"] == true))

      # Get audit stats
      conn_stats = get(conn, ~p"/api/v1/audit/stats")
      assert %{"data" => stats} = json_response(conn_stats, 200)
      assert is_integer(stats["total"])
      assert is_integer(stats["today"])
    end
  end

  describe "token scope enforcement" do
    test "read-only token cannot perform write operations" do
      user = user_fixture()

      {:ok, read_only_token} =
        ApiAuth.create_token_for_user(user, %{
          name: "Read Only Token",
          scopes: ["nodes:read", "dns:read"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{read_only_token.token}")

      # Can read nodes
      conn_read = get(conn, ~p"/api/v1/nodes")
      assert conn_read.status == 200

      # Cannot create nodes
      conn_create = post(conn, ~p"/api/v1/nodes", %{name: "test", host: "1.2.3.4", username: "a", password: "b"})
      assert conn_create.status == 403

      # Can read DNS
      conn_dns = get(conn, ~p"/api/v1/dns/records")
      assert conn_dns.status == 200

      # Cannot create DNS records
      conn_dns_create = post(conn, ~p"/api/v1/dns/records", %{name: "test.local", address: "1.2.3.4"})
      assert conn_dns_create.status == 403
    end

    test "scoped token can only access allowed resources" do
      user = user_fixture()

      {:ok, dns_only_token} =
        ApiAuth.create_token_for_user(user, %{
          name: "DNS Only Token",
          scopes: ["dns:read", "dns:write"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{dns_only_token.token}")

      # Can access DNS endpoints
      conn_dns = get(conn, ~p"/api/v1/dns/records")
      assert conn_dns.status == 200

      # Cannot access node endpoints
      conn_nodes = get(conn, ~p"/api/v1/nodes")
      assert conn_nodes.status == 403

      # Cannot access WireGuard endpoints
      conn_wg = get(conn, ~p"/api/v1/wireguard")
      assert conn_wg.status == 403

      # Cannot access audit endpoints
      conn_audit = get(conn, ~p"/api/v1/audit")
      assert conn_audit.status == 403
    end
  end
end
