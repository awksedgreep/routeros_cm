<?php
/**
 * RouterOS Cluster Manager - GRE Tunnel Management API
 *
 * This file provides functions for managing GRE (Generic Routing Encapsulation)
 * tunnel interfaces across the RouterOS cluster.
 *
 * @package RouterOSCM
 * @version 1.0.0
 *
 * REQUIRED SCOPES:
 * ================
 * - tunnels:read  - Required for listing GRE interfaces
 * - tunnels:write - Required for creating/deleting interfaces and IP assignments
 *
 * GRE OVERVIEW:
 * =============
 * GRE is a tunneling protocol that encapsulates packets inside IP packets.
 * It's commonly used for:
 * - Site-to-site connectivity
 * - Connecting networks over the internet
 * - Routing protocols over tunnels (OSPF, etc.)
 *
 * GRE tunnels require:
 * - Local address: The router's source IP
 * - Remote address: The other end of the tunnel
 * - Optional IPsec for encryption
 *
 * USAGE:
 * ======
 * ```php
 * require_once 'RouterOSClient.php';
 * require_once 'gre_api.php';
 *
 * $client = new RouterOSClient('https://your-server.com', 'your-token');
 * $greApi = new GreApi($client);
 *
 * // Create a GRE tunnel
 * $result = $greApi->createInterface('gre-site2', '192.168.1.1', '10.0.0.1');
 * ```
 */

require_once __DIR__ . '/RouterOSClient.php';

/**
 * GRE Tunnel Management API
 *
 * Provides methods for:
 * - Creating, listing, and deleting GRE tunnel interfaces
 * - Assigning IP addresses to GRE interfaces
 * - Configuring IPsec encryption for GRE tunnels
 */
class GreApi
{
    /** @var RouterOSClient API client instance */
    private RouterOSClient $client;

    /**
     * Create a new GreApi instance
     *
     * @param RouterOSClient $client Configured API client
     */
    public function __construct(RouterOSClient $client)
    {
        $this->client = $client;
    }

    // =========================================================================
    // GRE INTERFACE MANAGEMENT
    // =========================================================================

    /**
     * List all GRE interfaces across the cluster
     *
     * Returns GRE tunnel interfaces from all active nodes, grouped by interface name.
     *
     * @return array List of GRE interfaces
     * @throws RouterOSApiException On API errors
     *
     * Required scope: tunnels:read
     *
     * @example
     * ```php
     * $interfaces = $greApi->listInterfaces();
     *
     * foreach ($interfaces['data'] as $iface) {
     *     echo sprintf(
     *         "GRE: %s (%s -> %s)\n",
     *         $iface['name'],
     *         $iface['local_address'] ?? 'auto',
     *         $iface['remote_address']
     *     );
     *
     *     echo "  Status: " . ($iface['running'] ? 'Up' : 'Down') . "\n";
     *     echo "  MTU: " . ($iface['mtu'] ?? 'auto') . "\n";
     *
     *     if (!empty($iface['ipsec_secret'])) {
     *         echo "  IPsec: Enabled\n";
     *     }
     * }
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": [
     *         {
     *             "name": "gre-tunnel1",
     *             "local_address": "192.168.1.1",
     *             "remote_address": "10.0.0.1",
     *             "mtu": "1476",
     *             "allow_fast_path": false,
     *             "ipsec_secret": "***",
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
        return $this->client->get('/api/v1/gre');
    }

    /**
     * Get a specific GRE interface by name
     *
     * @param string $name Interface name (e.g., 'gre-tunnel1')
     * @return array Interface details
     * @throws RouterOSApiException On API errors (404 if not found)
     *
     * Required scope: tunnels:read
     *
     * @example
     * ```php
     * $interface = $greApi->getInterface('gre-site2');
     *
     * echo "Name: " . $interface['data']['name'] . "\n";
     * echo "Local: " . $interface['data']['local_address'] . "\n";
     * echo "Remote: " . $interface['data']['remote_address'] . "\n";
     * echo "Running: " . ($interface['data']['running'] ? 'Yes' : 'No') . "\n";
     * ```
     */
    public function getInterface(string $name): array
    {
        return $this->client->get("/api/v1/gre/" . urlencode($name));
    }

    /**
     * Create a new GRE tunnel interface
     *
     * Creates a GRE tunnel on the specified nodes or all active nodes.
     *
     * @param string $name Interface name (e.g., 'gre-site2', 'gre-branch')
     * @param string $localAddress Local endpoint IP address
     * @param string $remoteAddress Remote endpoint IP address
     * @param string|null $ipsecSecret Optional IPsec pre-shared key for encryption
     * @param string|null $mtu MTU value (default: auto, typically 1476)
     * @param bool $allowFastPath Enable fast path (default: false)
     * @param array|null $nodeIds Specific node IDs, or null for all nodes
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: tunnels:write
     *
     * @example
     * ```php
     * // Simple GRE tunnel
     * $result = $greApi->createInterface(
     *     'gre-branch1',
     *     '192.168.1.1',      // Our public IP
     *     '203.0.113.50'      // Remote site's IP
     * );
     *
     * // GRE tunnel with IPsec encryption
     * $result = $greApi->createInterface(
     *     'gre-secure',
     *     '192.168.1.1',
     *     '203.0.113.60',
     *     'MySecretKey123!'   // IPsec pre-shared key
     * );
     *
     * // GRE tunnel with custom MTU
     * $result = $greApi->createInterface(
     *     'gre-custom',
     *     '192.168.1.1',
     *     '203.0.113.70',
     *     null,               // No IPsec
     *     '1400'              // Custom MTU
     * );
     *
     * echo "Created on " . count($result['data']['successes']) . " nodes\n";
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": {
     *         "operation": "create",
     *         "resource": "gre_interface",
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
        string $localAddress,
        string $remoteAddress,
        ?string $ipsecSecret = null,
        ?string $mtu = null,
        bool $allowFastPath = false,
        ?array $nodeIds = null
    ): array {
        $data = [
            'name' => $name,
            'local-address' => $localAddress,
            'remote-address' => $remoteAddress,
            'allow-fast-path' => $allowFastPath ? 'yes' : 'no'
        ];

        if ($ipsecSecret !== null) {
            $data['ipsec-secret'] = $ipsecSecret;
        }

        if ($mtu !== null) {
            $data['mtu'] = $mtu;
        }

        if ($nodeIds !== null) {
            $data['node_ids'] = $nodeIds;
        }

        return $this->client->post('/api/v1/gre', $data);
    }

    /**
     * Delete a GRE tunnel interface
     *
     * Deletes the interface from all nodes where it exists.
     *
     * @param string $name Interface name to delete
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: tunnels:write
     *
     * @example
     * ```php
     * // Delete a GRE tunnel
     * $result = $greApi->deleteInterface('gre-old');
     *
     * echo "Deleted from " . count($result['data']['successes']) . " nodes\n";
     * ```
     */
    public function deleteInterface(string $name): array
    {
        return $this->client->delete("/api/v1/gre/" . urlencode($name));
    }

    // =========================================================================
    // IP ADDRESS MANAGEMENT
    // =========================================================================

    /**
     * Assign an IP address to a GRE interface
     *
     * Adds an IP address to the tunnel interface for routing.
     * The tunnel needs an IP address to route traffic through it.
     *
     * @param string $interfaceName Interface name (e.g., 'gre-tunnel1')
     * @param string $address IP address with CIDR notation (e.g., '172.16.0.1/30')
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: tunnels:write
     *
     * @example
     * ```php
     * // Assign a point-to-point IP (typically /30 or /31)
     * $result = $greApi->assignIp('gre-branch1', '172.16.0.1/30');
     *
     * echo "IP assigned on " . count($result['data']['successes']) . " nodes\n";
     *
     * // The remote end would use 172.16.0.2/30
     * ```
     */
    public function assignIp(string $interfaceName, string $address): array
    {
        return $this->client->post("/api/v1/gre/" . urlencode($interfaceName) . "/ip", [
            'address' => $address
        ]);
    }

    /**
     * Remove an IP address from a GRE interface
     *
     * @param string $interfaceName Interface name
     * @param string $address IP address to remove (with or without CIDR)
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: tunnels:write
     *
     * @example
     * ```php
     * // Remove an IP address
     * $result = $greApi->removeIp('gre-branch1', '172.16.0.1/30');
     * ```
     */
    public function removeIp(string $interfaceName, string $address): array
    {
        $encodedAddress = urlencode($address);
        return $this->client->delete(
            "/api/v1/gre/" . urlencode($interfaceName) . "/ip/" . $encodedAddress
        );
    }

    // =========================================================================
    // UTILITY METHODS
    // =========================================================================

    /**
     * Check if a GRE interface exists
     *
     * @param string $name Interface name
     * @return bool True if interface exists on at least one node
     *
     * @example
     * ```php
     * if ($greApi->interfaceExists('gre-branch1')) {
     *     echo "Tunnel exists\n";
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
     * Create a GRE tunnel with IP address in one call
     *
     * Convenience method that creates the interface and assigns an IP.
     *
     * @param string $name Interface name
     * @param string $localAddress Local endpoint
     * @param string $remoteAddress Remote endpoint
     * @param string $tunnelIp Tunnel IP with CIDR (e.g., '172.16.0.1/30')
     * @param string|null $ipsecSecret Optional IPsec key
     * @return array Results of both operations
     *
     * @example
     * ```php
     * $result = $greApi->createTunnelWithIp(
     *     'gre-branch1',
     *     '192.168.1.1',      // Our IP
     *     '203.0.113.50',     // Remote IP
     *     '172.16.0.1/30'     // Tunnel IP
     * );
     *
     * if ($result['interface_created'] && $result['ip_assigned']) {
     *     echo "GRE tunnel fully configured\n";
     * }
     * ```
     */
    public function createTunnelWithIp(
        string $name,
        string $localAddress,
        string $remoteAddress,
        string $tunnelIp,
        ?string $ipsecSecret = null
    ): array {
        $result = [
            'interface_created' => false,
            'ip_assigned' => false,
            'interface_result' => null,
            'ip_result' => null
        ];

        // Create interface
        $result['interface_result'] = $this->createInterface(
            $name,
            $localAddress,
            $remoteAddress,
            $ipsecSecret
        );
        $result['interface_created'] = !empty($result['interface_result']['data']['successes']);

        // Assign IP if interface was created
        if ($result['interface_created']) {
            try {
                $result['ip_result'] = $this->assignIp($name, $tunnelIp);
                $result['ip_assigned'] = !empty($result['ip_result']['data']['successes']);
            } catch (RouterOSApiException $e) {
                $result['ip_result'] = ['error' => $e->getMessage()];
            }
        }

        return $result;
    }

    /**
     * Get all running GRE tunnels
     *
     * @return array List of running interfaces
     *
     * @example
     * ```php
     * $running = $greApi->getRunningTunnels();
     *
     * echo count($running) . " GRE tunnels are up\n";
     * foreach ($running as $tunnel) {
     *     echo "  - " . $tunnel['name'] . "\n";
     * }
     * ```
     */
    public function getRunningTunnels(): array
    {
        $interfaces = $this->listInterfaces();

        return array_filter($interfaces['data'], function ($iface) {
            return isset($iface['running']) && $iface['running'] === true;
        });
    }

    /**
     * Get all tunnels to a specific remote address
     *
     * @param string $remoteAddress Remote endpoint address
     * @return array List of matching interfaces
     *
     * @example
     * ```php
     * $tunnels = $greApi->getTunnelsToRemote('203.0.113.50');
     *
     * foreach ($tunnels as $tunnel) {
     *     echo "Tunnel to remote: " . $tunnel['name'] . "\n";
     * }
     * ```
     */
    public function getTunnelsToRemote(string $remoteAddress): array
    {
        $interfaces = $this->listInterfaces();

        return array_filter($interfaces['data'], function ($iface) use ($remoteAddress) {
            return isset($iface['remote_address']) && $iface['remote_address'] === $remoteAddress;
        });
    }
}

// =============================================================================
// STANDALONE USAGE EXAMPLE
// =============================================================================
/*
// Example: Complete GRE tunnel setup

require_once 'RouterOSClient.php';
require_once 'gre_api.php';

// Initialize client
$client = new RouterOSClient('https://routeros-cm.example.com', 'your-api-token');
$greApi = new GreApi($client);

try {
    // 1. List existing GRE tunnels
    echo "Current GRE tunnels:\n";
    $interfaces = $greApi->listInterfaces();
    foreach ($interfaces['data'] as $iface) {
        $status = $iface['running'] ? 'UP' : 'DOWN';
        echo "  {$iface['name']}: {$iface['local_address']} -> {$iface['remote_address']} [$status]\n";
    }

    // 2. Create a new GRE tunnel to a branch office
    echo "\nCreating GRE tunnel to branch office...\n";
    $result = $greApi->createInterface(
        'gre-branch1',          // Interface name
        '192.168.1.1',          // Our public IP
        '203.0.113.50'          // Branch office IP
    );
    echo "Created on " . count($result['data']['successes']) . " nodes\n";

    // 3. Assign IP address to the tunnel
    echo "Assigning tunnel IP...\n";
    $result = $greApi->assignIp('gre-branch1', '172.16.0.1/30');
    echo "IP assigned on " . count($result['data']['successes']) . " nodes\n";

    // 4. Create a secure GRE tunnel with IPsec (in one call)
    echo "\nCreating secure GRE tunnel...\n";
    $result = $greApi->createTunnelWithIp(
        'gre-secure',
        '192.168.1.1',
        '203.0.113.60',
        '172.16.1.1/30'
    );

    if ($result['interface_created'] && $result['ip_assigned']) {
        echo "Secure tunnel fully configured\n";
    }

    // 5. Check tunnel status
    echo "\nChecking tunnel status...\n";
    $running = $greApi->getRunningTunnels();
    echo count($running) . " tunnels are running\n";

    // 6. Delete a tunnel
    echo "\nDeleting old tunnel...\n";
    if ($greApi->interfaceExists('gre-old')) {
        $result = $greApi->deleteInterface('gre-old');
        echo "Deleted from " . count($result['data']['successes']) . " nodes\n";
    } else {
        echo "Tunnel 'gre-old' doesn't exist\n";
    }

} catch (RouterOSApiException $e) {
    echo "API Error: " . $e->getMessage() . "\n";
    echo "HTTP Status: " . $e->getHttpStatus() . "\n";
}
*/
