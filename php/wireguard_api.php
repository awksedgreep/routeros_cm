<?php
/**
 * RouterOS Cluster Manager - WireGuard VPN Management API
 *
 * This file provides functions for managing WireGuard VPN interfaces and peers
 * across the RouterOS cluster.
 *
 * @package RouterOSCM
 * @version 1.0.0
 *
 * REQUIRED SCOPES:
 * ================
 * - wireguard:read  - Required for listing interfaces and peers
 * - wireguard:write - Required for creating/deleting interfaces, peers, and IP assignments
 *
 * WIREGUARD OVERVIEW:
 * ===================
 * WireGuard is a modern VPN protocol. In RouterOS, WireGuard consists of:
 * - Interfaces: The WireGuard tunnel endpoint on the router
 * - Peers: Remote endpoints that can connect to the interface
 * - IP Addresses: Assigned to interfaces for routing
 *
 * USAGE:
 * ======
 * ```php
 * require_once 'RouterOSClient.php';
 * require_once 'wireguard_api.php';
 *
 * $client = new RouterOSClient('https://your-server.com', 'your-token');
 * $wgApi = new WireGuardApi($client);
 *
 * // Generate a keypair for a new peer
 * $keypair = $wgApi->generateKeypair();
 *
 * // List all WireGuard interfaces
 * $interfaces = $wgApi->listInterfaces();
 * ```
 */

require_once __DIR__ . '/RouterOSClient.php';

/**
 * WireGuard VPN Management API
 *
 * Provides methods for:
 * - Managing WireGuard interfaces
 * - Managing WireGuard peers
 * - Assigning IP addresses to interfaces
 * - Generating WireGuard keypairs
 */
class WireGuardApi
{
    /** @var RouterOSClient API client instance */
    private RouterOSClient $client;

    /**
     * Create a new WireGuardApi instance
     *
     * @param RouterOSClient $client Configured API client
     */
    public function __construct(RouterOSClient $client)
    {
        $this->client = $client;
    }

    // =========================================================================
    // KEYPAIR GENERATION
    // =========================================================================

    /**
     * Generate a new WireGuard keypair
     *
     * Generates a cryptographically secure WireGuard private/public key pair.
     * Use this when setting up new peers.
     *
     * @return array Keypair with 'private_key' and 'public_key'
     * @throws RouterOSApiException On API errors
     *
     * Required scope: wireguard:write
     *
     * @example
     * ```php
     * $keypair = $wgApi->generateKeypair();
     *
     * echo "Private Key: " . $keypair['data']['private_key'] . "\n";
     * echo "Public Key: " . $keypair['data']['public_key'] . "\n";
     *
     * // IMPORTANT: Store the private key securely!
     * // The private key is given to the peer device.
     * // The public key is used when adding the peer to RouterOS.
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": {
     *         "private_key": "WG_PRIVATE_KEY_BASE64...",
     *         "public_key": "WG_PUBLIC_KEY_BASE64..."
     *     }
     * }
     * ```
     */
    public function generateKeypair(): array
    {
        return $this->client->post('/api/v1/wireguard/generate-keypair');
    }

    // =========================================================================
    // INTERFACE MANAGEMENT
    // =========================================================================

    /**
     * List all WireGuard interfaces across the cluster
     *
     * Returns WireGuard interfaces from all active nodes, grouped by interface name.
     *
     * @return array List of WireGuard interfaces
     * @throws RouterOSApiException On API errors
     *
     * Required scope: wireguard:read
     *
     * @example
     * ```php
     * $interfaces = $wgApi->listInterfaces();
     *
     * foreach ($interfaces['data'] as $iface) {
     *     echo sprintf(
     *         "Interface: %s, Port: %s, Public Key: %s...\n",
     *         $iface['name'],
     *         $iface['listen_port'] ?? 'auto',
     *         substr($iface['public_key'] ?? '', 0, 20)
     *     );
     *
     *     // Show which nodes have this interface
     *     echo "  Nodes: ";
     *     foreach ($iface['nodes'] as $node) {
     *         echo $node['node_name'] . " ";
     *     }
     *     echo "\n";
     * }
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": [
     *         {
     *             "name": "wg0",
     *             "listen_port": "51820",
     *             "mtu": "1420",
     *             "public_key": "BASE64_PUBLIC_KEY...",
     *             "running": true,
     *             "disabled": false,
     *             "nodes": [
     *                 {"node_name": "router1", "node_id": 1, "interface_id": "*1"}
     *             ]
     *         }
     *     ]
     * }
     * ```
     */
    public function listInterfaces(): array
    {
        return $this->client->get('/api/v1/wireguard');
    }

    /**
     * Get a specific WireGuard interface by name
     *
     * @param string $name Interface name (e.g., 'wg0')
     * @return array Interface details
     * @throws RouterOSApiException On API errors (404 if not found)
     *
     * Required scope: wireguard:read
     *
     * @example
     * ```php
     * $interface = $wgApi->getInterface('wg0');
     *
     * echo "Name: " . $interface['data']['name'] . "\n";
     * echo "Listen Port: " . $interface['data']['listen_port'] . "\n";
     * echo "Public Key: " . $interface['data']['public_key'] . "\n";
     * echo "Status: " . ($interface['data']['running'] ? 'Running' : 'Stopped') . "\n";
     * ```
     */
    public function getInterface(string $name): array
    {
        return $this->client->get("/api/v1/wireguard/" . urlencode($name));
    }

    /**
     * Create a new WireGuard interface
     *
     * Creates a WireGuard interface on the specified nodes or all active nodes.
     *
     * @param string $name Interface name (e.g., 'wg0', 'wg-vpn')
     * @param int $listenPort UDP port to listen on (e.g., 51820)
     * @param string|null $privateKey Private key (auto-generated if not provided)
     * @param string|null $mtu MTU value (default: 1420)
     * @param array|null $nodeIds Specific node IDs, or null for all nodes
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: wireguard:write
     *
     * @example
     * ```php
     * // Create with auto-generated key on all nodes
     * $result = $wgApi->createInterface('wg0', 51820);
     *
     * // Create with specific private key
     * $keypair = $wgApi->generateKeypair();
     * $result = $wgApi->createInterface(
     *     'wg-site2site',
     *     51821,
     *     $keypair['data']['private_key']
     * );
     *
     * // Create on specific nodes only
     * $result = $wgApi->createInterface('wg-branch', 51822, null, '1400', [1, 2]);
     *
     * echo "Created on " . count($result['data']['successes']) . " nodes\n";
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": {
     *         "operation": "create",
     *         "resource": "wireguard_interface",
     *         "successes": [
     *             {"node": "router1", "node_id": 1, "id": "*1"}
     *         ],
     *         "failures": []
     *     }
     * }
     * ```
     */
    public function createInterface(
        string $name,
        int $listenPort,
        ?string $privateKey = null,
        ?string $mtu = null,
        ?array $nodeIds = null
    ): array {
        $data = [
            'name' => $name,
            'listen-port' => (string)$listenPort
        ];

        if ($privateKey !== null) {
            $data['private-key'] = $privateKey;
        }

        if ($mtu !== null) {
            $data['mtu'] = $mtu;
        }

        if ($nodeIds !== null) {
            $data['node_ids'] = $nodeIds;
        }

        return $this->client->post('/api/v1/wireguard', $data);
    }

    /**
     * Delete a WireGuard interface
     *
     * Deletes the interface from all nodes where it exists.
     *
     * WARNING: This will disconnect all peers using this interface!
     *
     * @param string $name Interface name to delete
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: wireguard:write
     *
     * @example
     * ```php
     * // Delete an interface
     * $result = $wgApi->deleteInterface('wg-old');
     *
     * echo "Deleted from " . count($result['data']['successes']) . " nodes\n";
     * ```
     */
    public function deleteInterface(string $name): array
    {
        return $this->client->delete("/api/v1/wireguard/" . urlencode($name));
    }

    // =========================================================================
    // IP ADDRESS MANAGEMENT
    // =========================================================================

    /**
     * Assign an IP address to a WireGuard interface
     *
     * Adds an IP address to the interface for routing traffic through the tunnel.
     *
     * @param string $interfaceName Interface name (e.g., 'wg0')
     * @param string $address IP address with CIDR notation (e.g., '10.0.0.1/24')
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: wireguard:write
     *
     * @example
     * ```php
     * // Assign IP to WireGuard interface
     * $result = $wgApi->assignIp('wg0', '10.0.0.1/24');
     *
     * echo "IP assigned on " . count($result['data']['successes']) . " nodes\n";
     *
     * // Assign a second IP (for dual-stack, etc.)
     * $result = $wgApi->assignIp('wg0', '10.0.1.1/24');
     * ```
     */
    public function assignIp(string $interfaceName, string $address): array
    {
        return $this->client->post("/api/v1/wireguard/" . urlencode($interfaceName) . "/ip", [
            'address' => $address
        ]);
    }

    /**
     * Remove an IP address from a WireGuard interface
     *
     * @param string $interfaceName Interface name
     * @param string $address IP address to remove (with or without CIDR)
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: wireguard:write
     *
     * @example
     * ```php
     * // Remove an IP address
     * $result = $wgApi->removeIp('wg0', '10.0.0.1/24');
     * ```
     */
    public function removeIp(string $interfaceName, string $address): array
    {
        // URL encode the address, replacing / with %2F
        $encodedAddress = urlencode($address);
        return $this->client->delete(
            "/api/v1/wireguard/" . urlencode($interfaceName) . "/ip/" . $encodedAddress
        );
    }

    // =========================================================================
    // PEER MANAGEMENT
    // =========================================================================

    /**
     * List peers for a WireGuard interface
     *
     * Returns all peers configured for the specified interface across all nodes.
     *
     * @param string $interfaceName Interface name (e.g., 'wg0')
     * @return array List of peers
     * @throws RouterOSApiException On API errors
     *
     * Required scope: wireguard:read
     *
     * @example
     * ```php
     * $peers = $wgApi->listPeers('wg0');
     *
     * foreach ($peers['data'] as $peer) {
     *     echo sprintf(
     *         "Peer: %s...\n",
     *         substr($peer['public_key'], 0, 20)
     *     );
     *     echo "  Allowed: " . ($peer['allowed_address'] ?? 'any') . "\n";
     *     echo "  Endpoint: " . ($peer['endpoint_address'] ?? 'dynamic') . "\n";
     *
     *     if (isset($peer['last_handshake'])) {
     *         echo "  Last handshake: " . $peer['last_handshake'] . "\n";
     *     }
     *
     *     if (isset($peer['rx']) && isset($peer['tx'])) {
     *         echo sprintf("  Traffic: RX %s, TX %s\n", $peer['rx'], $peer['tx']);
     *     }
     * }
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": [
     *         {
     *             "public_key": "BASE64_PUBLIC_KEY...",
     *             "interface": "wg0",
     *             "allowed_address": "10.0.0.2/32",
     *             "endpoint_address": "client.example.com",
     *             "endpoint_port": "51820",
     *             "persistent_keepalive": "25",
     *             "last_handshake": "2024-01-15T10:30:00Z",
     *             "rx": "1048576",
     *             "tx": "2097152",
     *             "nodes": [
     *                 {"node_name": "router1", "node_id": 1, "peer_id": "*1"}
     *             ]
     *         }
     *     ]
     * }
     * ```
     */
    public function listPeers(string $interfaceName): array
    {
        return $this->client->get("/api/v1/wireguard/" . urlencode($interfaceName) . "/peers");
    }

    /**
     * Add a peer to a WireGuard interface
     *
     * Configures a new peer on the WireGuard interface across all nodes.
     *
     * @param string $interfaceName Interface name (e.g., 'wg0')
     * @param string $publicKey Peer's public key
     * @param string $allowedAddress Allowed IP address/subnet (e.g., '10.0.0.2/32')
     * @param string|null $endpointAddress Peer's endpoint hostname/IP (for site-to-site)
     * @param int|null $endpointPort Peer's endpoint port
     * @param int|null $persistentKeepalive Keepalive interval in seconds (e.g., 25)
     * @param string|null $presharedKey Optional pre-shared key for additional security
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: wireguard:write
     *
     * @example
     * ```php
     * // Road warrior peer (no endpoint - peer initiates connection)
     * $result = $wgApi->createPeer(
     *     'wg0',
     *     'PEER_PUBLIC_KEY_BASE64...',
     *     '10.0.0.2/32'
     * );
     *
     * // Site-to-site peer with endpoint
     * $result = $wgApi->createPeer(
     *     'wg0',
     *     'PEER_PUBLIC_KEY_BASE64...',
     *     '10.0.0.0/24',           // Allow entire subnet
     *     'remote.example.com',    // Peer's address
     *     51820,                   // Peer's port
     *     25                       // Keepalive
     * );
     *
     * // Peer with pre-shared key
     * $result = $wgApi->createPeer(
     *     'wg0',
     *     'PEER_PUBLIC_KEY...',
     *     '10.0.0.3/32',
     *     null, null, null,
     *     'PRESHARED_KEY_BASE64...'
     * );
     *
     * echo "Peer added on " . count($result['data']['successes']) . " nodes\n";
     * ```
     */
    public function createPeer(
        string $interfaceName,
        string $publicKey,
        string $allowedAddress,
        ?string $endpointAddress = null,
        ?int $endpointPort = null,
        ?int $persistentKeepalive = null,
        ?string $presharedKey = null
    ): array {
        $data = [
            'public-key' => $publicKey,
            'allowed-address' => $allowedAddress
        ];

        if ($endpointAddress !== null) {
            $data['endpoint-address'] = $endpointAddress;
        }

        if ($endpointPort !== null) {
            $data['endpoint-port'] = (string)$endpointPort;
        }

        if ($persistentKeepalive !== null) {
            $data['persistent-keepalive'] = (string)$persistentKeepalive . 's';
        }

        if ($presharedKey !== null) {
            $data['preshared-key'] = $presharedKey;
        }

        return $this->client->post(
            "/api/v1/wireguard/" . urlencode($interfaceName) . "/peers",
            $data
        );
    }

    /**
     * Delete a peer from a WireGuard interface
     *
     * Removes a peer from all nodes.
     *
     * @param string $interfaceName Interface name
     * @param string $publicKey Peer's public key
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: wireguard:write
     *
     * @example
     * ```php
     * // Remove a peer
     * $result = $wgApi->deletePeer('wg0', 'PEER_PUBLIC_KEY_BASE64...');
     *
     * echo "Peer removed from " . count($result['data']['successes']) . " nodes\n";
     * ```
     */
    public function deletePeer(string $interfaceName, string $publicKey): array
    {
        return $this->client->delete(
            "/api/v1/wireguard/" . urlencode($interfaceName) . "/peers/" . urlencode($publicKey)
        );
    }

    // =========================================================================
    // UTILITY METHODS
    // =========================================================================

    /**
     * Check if an interface exists
     *
     * @param string $name Interface name
     * @return bool True if interface exists on at least one node
     *
     * @example
     * ```php
     * if ($wgApi->interfaceExists('wg0')) {
     *     echo "Interface wg0 exists\n";
     * }
     * ```
     */
    public function interfaceExists(string $name): bool
    {
        try {
            $this->getInterface($name);
            return true;
        } catch (RouterOSApiException $e) {
            if ($e->getHttpStatus() === 404) {
                return false;
            }
            throw $e;
        }
    }

    /**
     * Get peer count for an interface
     *
     * @param string $interfaceName Interface name
     * @return int Number of peers
     *
     * @example
     * ```php
     * $count = $wgApi->getPeerCount('wg0');
     * echo "Interface wg0 has $count peers\n";
     * ```
     */
    public function getPeerCount(string $interfaceName): int
    {
        $peers = $this->listPeers($interfaceName);
        return count($peers['data']);
    }

    /**
     * Create a complete WireGuard setup
     *
     * Creates an interface with IP address in one call.
     *
     * @param string $name Interface name
     * @param int $listenPort Listen port
     * @param string $address IP address with CIDR
     * @return array Results of both operations
     *
     * @example
     * ```php
     * $result = $wgApi->createInterfaceWithIp('wg0', 51820, '10.0.0.1/24');
     *
     * if ($result['interface_created'] && $result['ip_assigned']) {
     *     echo "WireGuard interface fully configured\n";
     * }
     * ```
     */
    public function createInterfaceWithIp(
        string $name,
        int $listenPort,
        string $address
    ): array {
        $result = [
            'interface_created' => false,
            'ip_assigned' => false,
            'interface_result' => null,
            'ip_result' => null
        ];

        // Create interface
        $result['interface_result'] = $this->createInterface($name, $listenPort);
        $result['interface_created'] = !empty($result['interface_result']['data']['successes']);

        // Assign IP if interface was created
        if ($result['interface_created']) {
            try {
                $result['ip_result'] = $this->assignIp($name, $address);
                $result['ip_assigned'] = !empty($result['ip_result']['data']['successes']);
            } catch (RouterOSApiException $e) {
                $result['ip_result'] = ['error' => $e->getMessage()];
            }
        }

        return $result;
    }

    /**
     * Generate client configuration
     *
     * Generates a WireGuard client configuration file content.
     * Note: This generates the config locally, it doesn't fetch from RouterOS.
     *
     * @param string $clientPrivateKey Client's private key
     * @param string $clientAddress Client's IP address
     * @param string $serverPublicKey Server's public key
     * @param string $serverEndpoint Server's endpoint (host:port)
     * @param string $allowedIps Allowed IPs (e.g., '0.0.0.0/0' for all traffic)
     * @param int|null $persistentKeepalive Keepalive interval
     * @param string|null $dns DNS server to use
     * @return string WireGuard configuration file content
     *
     * @example
     * ```php
     * // Generate keypair for client
     * $keypair = $wgApi->generateKeypair();
     *
     * // Get server's public key
     * $interface = $wgApi->getInterface('wg0');
     * $serverPubKey = $interface['data']['public_key'];
     *
     * // Generate client config
     * $config = $wgApi->generateClientConfig(
     *     $keypair['data']['private_key'],
     *     '10.0.0.2/32',
     *     $serverPubKey,
     *     'vpn.example.com:51820',
     *     '10.0.0.0/24',  // Only route VPN subnet
     *     25,             // Keepalive
     *     '10.0.0.1'      // Use WG server as DNS
     * );
     *
     * echo $config;
     * // Save to file: file_put_contents('client.conf', $config);
     * ```
     */
    public function generateClientConfig(
        string $clientPrivateKey,
        string $clientAddress,
        string $serverPublicKey,
        string $serverEndpoint,
        string $allowedIps = '0.0.0.0/0',
        ?int $persistentKeepalive = null,
        ?string $dns = null
    ): string {
        $config = "[Interface]\n";
        $config .= "PrivateKey = $clientPrivateKey\n";
        $config .= "Address = $clientAddress\n";

        if ($dns !== null) {
            $config .= "DNS = $dns\n";
        }

        $config .= "\n[Peer]\n";
        $config .= "PublicKey = $serverPublicKey\n";
        $config .= "Endpoint = $serverEndpoint\n";
        $config .= "AllowedIPs = $allowedIps\n";

        if ($persistentKeepalive !== null) {
            $config .= "PersistentKeepalive = $persistentKeepalive\n";
        }

        return $config;
    }
}

// =============================================================================
// STANDALONE USAGE EXAMPLE
// =============================================================================
/*
// Example: Complete WireGuard VPN setup

require_once 'RouterOSClient.php';
require_once 'wireguard_api.php';

// Initialize client
$client = new RouterOSClient('https://routeros-cm.example.com', 'your-api-token');
$wgApi = new WireGuardApi($client);

try {
    // 1. Create a WireGuard interface
    echo "Creating WireGuard interface...\n";
    $result = $wgApi->createInterface('wg0', 51820);
    echo "Created on " . count($result['data']['successes']) . " nodes\n";

    // 2. Assign IP address to the interface
    echo "Assigning IP address...\n";
    $result = $wgApi->assignIp('wg0', '10.0.0.1/24');
    echo "IP assigned on " . count($result['data']['successes']) . " nodes\n";

    // 3. Get the server's public key
    $interface = $wgApi->getInterface('wg0');
    $serverPublicKey = $interface['data']['public_key'];
    echo "Server public key: $serverPublicKey\n";

    // 4. Generate a keypair for a new client
    echo "\nGenerating client keypair...\n";
    $clientKeypair = $wgApi->generateKeypair();
    $clientPrivateKey = $clientKeypair['data']['private_key'];
    $clientPublicKey = $clientKeypair['data']['public_key'];
    echo "Client public key: $clientPublicKey\n";

    // 5. Add the client as a peer
    echo "\nAdding client as peer...\n";
    $result = $wgApi->createPeer(
        'wg0',
        $clientPublicKey,
        '10.0.0.2/32'  // Client's VPN IP
    );
    echo "Peer added on " . count($result['data']['successes']) . " nodes\n";

    // 6. Generate client configuration file
    echo "\nGenerating client configuration...\n";
    $clientConfig = $wgApi->generateClientConfig(
        $clientPrivateKey,
        '10.0.0.2/32',
        $serverPublicKey,
        'your-server.example.com:51820',
        '10.0.0.0/24',  // Route VPN subnet through tunnel
        25              // Keepalive for NAT traversal
    );

    echo "\n=== CLIENT CONFIGURATION ===\n";
    echo $clientConfig;
    echo "============================\n";

    // 7. List all peers
    echo "\nCurrent peers:\n";
    $peers = $wgApi->listPeers('wg0');
    foreach ($peers['data'] as $peer) {
        echo "  - " . substr($peer['public_key'], 0, 20) . "...\n";
        echo "    Allowed: " . $peer['allowed_address'] . "\n";
    }

} catch (RouterOSApiException $e) {
    echo "API Error: " . $e->getMessage() . "\n";
    echo "HTTP Status: " . $e->getHttpStatus() . "\n";
}
*/
