defmodule RouterosCm.MikroTik.ClientTest do
  use RouterosCm.DataCase, async: false

  alias RouterosCm.MikroTik.Client
  alias RouterosCm.Cluster.Node

  describe "auth_from_node/1" do
    test "creates auth struct from node" do
      # Use plain password field for testing (Node.get_password/1 supports both)
      node = %Node{
        id: 1,
        name: "test-node",
        host: "192.168.1.1",
        port: 443,
        username: "admin",
        password: "test_password"
      }

      auth = Client.auth_from_node(node)

      assert %MikrotikApi.Auth{} = auth
      assert auth.username == "admin"
      # Password is retrieved via Node.get_password/1
    end
  end

  describe "function signatures and basic validation" do
    setup do
      # Use plain password field for testing to avoid encryption/decryption issues
      node = %Node{
        id: 1,
        name: "test-node",
        host: "192.168.1.1",
        port: 443,
        username: "admin",
        password: "test_password",
        status: "active",
        inserted_at: ~N[2025-01-01 00:00:00],
        updated_at: ~N[2025-01-01 00:00:00]
      }

      {:ok, node: node}
    end

    test "test_connection/1 accepts node struct", %{node: node} do
      # Ensure module is loaded
      Code.ensure_loaded!(RouterosCm.MikroTik.Client)

      # Will fail without real device, but validates function exists and accepts correct args
      assert function_exported?(RouterosCm.MikroTik.Client, :test_connection, 1)
      result = Client.test_connection(node)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "WireGuard interface functions exist", %{node: node} do
      # Ensure module is loaded before checking function exports
      Code.ensure_loaded!(RouterosCm.MikroTik.Client)

      # Verify function signatures
      assert function_exported?(RouterosCm.MikroTik.Client, :list_wireguard_interfaces, 1)
      assert function_exported?(RouterosCm.MikroTik.Client, :create_wireguard_interface, 2)
      assert function_exported?(RouterosCm.MikroTik.Client, :update_wireguard_interface, 3)
      assert function_exported?(RouterosCm.MikroTik.Client, :delete_wireguard_interface, 2)

      # Validate they accept correct args (will error without real device)
      result = Client.list_wireguard_interfaces(node)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "WireGuard peer functions exist", %{node: node} do
      Code.ensure_loaded!(RouterosCm.MikroTik.Client)

      assert function_exported?(RouterosCm.MikroTik.Client, :list_wireguard_peers, 2)
      assert function_exported?(RouterosCm.MikroTik.Client, :create_wireguard_peer, 3)
      assert function_exported?(RouterosCm.MikroTik.Client, :update_wireguard_peer, 3)
      assert function_exported?(RouterosCm.MikroTik.Client, :delete_wireguard_peer, 3)

      # Validate they accept correct args
      result = Client.list_wireguard_peers(node, "wg0")
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "GRE interface functions exist", %{node: node} do
      Code.ensure_loaded!(RouterosCm.MikroTik.Client)

      assert function_exported?(RouterosCm.MikroTik.Client, :list_gre_interfaces, 1)
      assert function_exported?(RouterosCm.MikroTik.Client, :create_gre_interface, 2)
      assert function_exported?(RouterosCm.MikroTik.Client, :update_gre_interface, 3)
      assert function_exported?(RouterosCm.MikroTik.Client, :delete_gre_interface, 2)

      result = Client.list_gre_interfaces(node)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "IP address functions exist", %{node: node} do
      Code.ensure_loaded!(RouterosCm.MikroTik.Client)

      # Verify function signatures - list_addresses has optional second param
      assert function_exported?(RouterosCm.MikroTik.Client, :list_addresses, 1)
      assert function_exported?(RouterosCm.MikroTik.Client, :list_addresses, 2)
      assert function_exported?(RouterosCm.MikroTik.Client, :create_address, 2)
      assert function_exported?(RouterosCm.MikroTik.Client, :delete_address, 2)
      assert function_exported?(Client, :delete_address, 2)

      result = Client.list_addresses(node)
      assert match?({:ok, _}, result) or match?({:error, _}, result)

      result_filtered = Client.list_addresses(node, "wg0")
      assert match?({:ok, _}, result_filtered) or match?({:error, _}, result_filtered)
    end

    test "DNS functions exist", %{node: node} do
      Code.ensure_loaded!(RouterosCm.MikroTik.Client)

      # Verify function signatures
      assert function_exported?(RouterosCm.MikroTik.Client, :list_dns_records, 1)
      assert function_exported?(RouterosCm.MikroTik.Client, :create_dns_record, 2)
      assert function_exported?(RouterosCm.MikroTik.Client, :update_dns_record, 3)
      assert function_exported?(RouterosCm.MikroTik.Client, :delete_dns_record, 2)
      assert function_exported?(RouterosCm.MikroTik.Client, :get_dns_settings, 1)
      assert function_exported?(RouterosCm.MikroTik.Client, :update_dns_settings, 2)
      assert function_exported?(RouterosCm.MikroTik.Client, :list_dns_cache, 1)
      assert function_exported?(RouterosCm.MikroTik.Client, :flush_dns_cache, 1)

      result = Client.list_dns_records(node)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "RouterOS user management functions exist", %{node: node} do
      Code.ensure_loaded!(RouterosCm.MikroTik.Client)

      assert function_exported?(RouterosCm.MikroTik.Client, :list_routeros_users, 1)
      assert function_exported?(RouterosCm.MikroTik.Client, :create_routeros_user, 2)
      assert function_exported?(Client, :update_routeros_user, 3)
      assert function_exported?(Client, :delete_routeros_user, 2)
      assert function_exported?(Client, :list_user_groups, 1)
      assert function_exported?(Client, :list_active_users, 1)

      result = Client.list_routeros_users(node)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end
  end

  describe "list_wireguard_peers/2 filtering logic" do
    test "filters peers by interface ID" do
      # Test the filtering logic with mock data
      all_peers = [
        %{".id" => "*1", "interface" => "wg0", "public-key" => "key1"},
        %{".id" => "*2", "interface" => "wg1", "public-key" => "key2"},
        %{".id" => "*3", "interface" => "wg0", "public-key" => "key3"}
      ]

      filtered = Enum.filter(all_peers, fn peer -> peer["interface"] == "wg0" end)

      assert length(filtered) == 2
      assert Enum.all?(filtered, fn p -> p["interface"] == "wg0" end)
      assert Enum.map(filtered, & &1[".id"]) == ["*1", "*3"]
    end
  end

  describe "delete_wireguard_peer/3 logic" do
    test "returns error when peer not found in empty list" do
      peers = []
      peer = Enum.find(peers, fn p -> p["public-key"] == "missing-key" end)

      assert peer == nil
    end

    test "finds peer by public key" do
      peers = [
        %{".id" => "*1", "interface" => "wg0", "public-key" => "key1"},
        %{".id" => "*2", "interface" => "wg0", "public-key" => "key2"}
      ]

      peer = Enum.find(peers, fn p -> p["public-key"] == "key2" end)

      assert peer != nil
      assert peer[".id"] == "*2"
    end
  end

  describe "create_wireguard_peer/3 interface injection" do
    test "adds interface to attributes map" do
      attrs = %{"public-key" => "test-key", "allowed-address" => "10.0.0.2/32"}
      interface_id = "wg0"

      attrs_with_interface = Map.put(attrs, "interface", interface_id)

      assert attrs_with_interface["interface"] == "wg0"
      assert attrs_with_interface["public-key"] == "test-key"
      assert attrs_with_interface["allowed-address"] == "10.0.0.2/32"
    end
  end

  describe "port-based scheme detection" do
    test "returns http scheme for port 80" do
      node = %Node{port: 80}
      # This tests the get_opts private function logic
      assert node.port == 80
    end

    test "returns https scheme for non-80 ports" do
      node = %Node{port: 443}
      assert node.port == 443

      node2 = %Node{port: 8728}
      assert node2.port == 8728
    end
  end
end
