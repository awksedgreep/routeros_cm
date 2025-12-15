<?php
/**
 * RouterOS Cluster Manager - Cluster & Node Management API
 *
 * This file provides functions for managing the RouterOS cluster and its nodes.
 * Nodes are the individual MikroTik RouterOS devices that make up the cluster.
 *
 * @package RouterOSCM
 * @version 1.0.0
 *
 * REQUIRED SCOPES:
 * ================
 * - nodes:read  - Required for listing nodes, getting node details, health checks
 * - nodes:write - Required for creating, updating, deleting nodes
 *
 * USAGE:
 * ======
 * ```php
 * require_once 'RouterOSClient.php';
 * require_once 'cluster_api.php';
 *
 * $client = new RouterOSClient('https://your-server.com', 'your-token');
 * $clusterApi = new ClusterApi($client);
 *
 * // List all nodes
 * $nodes = $clusterApi->listNodes();
 *
 * // Get cluster health
 * $health = $clusterApi->getClusterHealth();
 * ```
 */

require_once __DIR__ . '/RouterOSClient.php';

/**
 * Cluster and Node Management API
 *
 * Provides methods for:
 * - Listing and managing cluster nodes
 * - Testing node connections
 * - Monitoring cluster health
 * - Viewing cluster statistics
 */
class ClusterApi
{
    /** @var RouterOSClient API client instance */
    private RouterOSClient $client;

    /**
     * Create a new ClusterApi instance
     *
     * @param RouterOSClient $client Configured API client
     */
    public function __construct(RouterOSClient $client)
    {
        $this->client = $client;
    }

    // =========================================================================
    // NODE MANAGEMENT
    // =========================================================================

    /**
     * List all nodes in the cluster
     *
     * Returns all registered RouterOS nodes with their connection status.
     *
     * @return array List of nodes with their details
     * @throws RouterOSApiException On API errors
     *
     * Required scope: nodes:read
     *
     * @example
     * ```php
     * $nodes = $clusterApi->listNodes();
     *
     * foreach ($nodes['data'] as $node) {
     *     echo sprintf(
     *         "Node: %s (%s) - Status: %s\n",
     *         $node['name'],
     *         $node['host'],
     *         $node['status']
     *     );
     * }
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": [
     *         {
     *             "id": 1,
     *             "name": "router1",
     *             "host": "192.168.1.1",
     *             "port": 8728,
     *             "use_ssl": false,
     *             "status": "online",
     *             "last_seen_at": "2024-01-15T10:30:00Z",
     *             "inserted_at": "2024-01-01T00:00:00Z",
     *             "updated_at": "2024-01-15T10:30:00Z"
     *         }
     *     ]
     * }
     * ```
     */
    public function listNodes(): array
    {
        return $this->client->get('/api/v1/nodes');
    }

    /**
     * Get details for a specific node
     *
     * @param int $nodeId Node ID
     * @return array Node details
     * @throws RouterOSApiException On API errors (404 if not found)
     *
     * Required scope: nodes:read
     *
     * @example
     * ```php
     * $node = $clusterApi->getNode(1);
     *
     * echo "Name: " . $node['data']['name'] . "\n";
     * echo "Host: " . $node['data']['host'] . "\n";
     * echo "Status: " . $node['data']['status'] . "\n";
     * echo "Last seen: " . $node['data']['last_seen_at'] . "\n";
     * ```
     */
    public function getNode(int $nodeId): array
    {
        return $this->client->get("/api/v1/nodes/{$nodeId}");
    }

    /**
     * Create a new node in the cluster
     *
     * Registers a new RouterOS device with the cluster manager.
     * The system will attempt to connect to the device to verify credentials.
     *
     * @param string $name Unique name for the node (e.g., 'router1', 'core-switch')
     * @param string $host Hostname or IP address of the RouterOS device
     * @param string $username RouterOS API username
     * @param string $password RouterOS API password
     * @param int $port API port (default: 8728 for non-SSL, 8729 for SSL)
     * @param bool $useSsl Whether to use SSL/TLS connection
     * @return array Created node details
     * @throws RouterOSApiException On API errors or validation failures
     *
     * Required scope: nodes:write
     *
     * @example
     * ```php
     * // Create a node with default port (8728)
     * $node = $clusterApi->createNode(
     *     'router1',
     *     '192.168.1.1',
     *     'admin',
     *     'secretpassword'
     * );
     *
     * echo "Created node with ID: " . $node['data']['id'] . "\n";
     *
     * // Create a node with SSL
     * $sslNode = $clusterApi->createNode(
     *     'secure-router',
     *     '192.168.1.2',
     *     'admin',
     *     'secretpassword',
     *     8729,  // SSL port
     *     true   // Enable SSL
     * );
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": {
     *         "id": 1,
     *         "name": "router1",
     *         "host": "192.168.1.1",
     *         "port": 8728,
     *         "use_ssl": false,
     *         "status": "online"
     *     }
     * }
     * ```
     */
    public function createNode(
        string $name,
        string $host,
        string $username,
        string $password,
        int $port = 8728,
        bool $useSsl = false
    ): array {
        return $this->client->post('/api/v1/nodes', [
            'name' => $name,
            'host' => $host,
            'username' => $username,
            'password' => $password,
            'port' => $port,
            'use_ssl' => $useSsl
        ]);
    }

    /**
     * Update an existing node
     *
     * Updates node configuration. You can update any combination of fields.
     * Note: Changing credentials will trigger a connection test.
     *
     * @param int $nodeId Node ID to update
     * @param array $data Fields to update. Supported fields:
     *                    - name: string - Node name
     *                    - host: string - Hostname or IP
     *                    - port: int - API port
     *                    - username: string - API username
     *                    - password: string - API password
     *                    - use_ssl: bool - SSL/TLS setting
     * @return array Updated node details
     * @throws RouterOSApiException On API errors
     *
     * Required scope: nodes:write
     *
     * @example
     * ```php
     * // Update just the name
     * $node = $clusterApi->updateNode(1, [
     *     'name' => 'router1-primary'
     * ]);
     *
     * // Update credentials
     * $node = $clusterApi->updateNode(1, [
     *     'username' => 'api-user',
     *     'password' => 'new-secure-password'
     * ]);
     *
     * // Update multiple fields
     * $node = $clusterApi->updateNode(1, [
     *     'name' => 'router1-updated',
     *     'host' => '192.168.1.100',
     *     'port' => 8729,
     *     'use_ssl' => true
     * ]);
     * ```
     */
    public function updateNode(int $nodeId, array $data): array
    {
        return $this->client->put("/api/v1/nodes/{$nodeId}", $data);
    }

    /**
     * Delete a node from the cluster
     *
     * Removes a node from the cluster manager. This does not affect the
     * actual RouterOS device - it only removes it from management.
     *
     * WARNING: Deleting a node will remove all local associations but
     * configurations made on the device will remain.
     *
     * @param int $nodeId Node ID to delete
     * @return void
     * @throws RouterOSApiException On API errors (404 if not found)
     *
     * Required scope: nodes:write
     *
     * @example
     * ```php
     * // Delete a node
     * $clusterApi->deleteNode(1);
     * echo "Node deleted successfully\n";
     *
     * // With error handling
     * try {
     *     $clusterApi->deleteNode(999);
     * } catch (RouterOSApiException $e) {
     *     if ($e->getHttpStatus() === 404) {
     *         echo "Node not found\n";
     *     }
     * }
     * ```
     */
    public function deleteNode(int $nodeId): void
    {
        $this->client->delete("/api/v1/nodes/{$nodeId}");
    }

    /**
     * Test connection to a node
     *
     * Attempts to connect to the RouterOS device and verify credentials.
     * Useful for troubleshooting connectivity issues.
     *
     * @param int $nodeId Node ID to test
     * @return array Test results
     * @throws RouterOSApiException On connection failure or API errors
     *
     * Required scope: nodes:read
     *
     * @example
     * ```php
     * try {
     *     $result = $clusterApi->testConnection(1);
     *     echo "Connection successful!\n";
     *     echo "Message: " . $result['data']['message'] . "\n";
     * } catch (RouterOSApiException $e) {
     *     echo "Connection failed: " . $e->getMessage() . "\n";
     * }
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": {
     *         "success": true,
     *         "message": "Connection successful"
     *     }
     * }
     * ```
     */
    public function testConnection(int $nodeId): array
    {
        return $this->client->post("/api/v1/nodes/{$nodeId}/test");
    }

    // =========================================================================
    // CLUSTER HEALTH & STATISTICS
    // =========================================================================

    /**
     * Get cluster health information
     *
     * Returns health metrics for all nodes including CPU, memory, uptime, etc.
     * Nodes that fail to respond will show error status.
     *
     * @return array Cluster health data
     * @throws RouterOSApiException On API errors
     *
     * Required scope: nodes:read
     *
     * @example
     * ```php
     * $health = $clusterApi->getClusterHealth();
     *
     * // Overall summary
     * $summary = $health['data']['summary'];
     * echo sprintf(
     *     "Cluster: %d/%d nodes healthy\n",
     *     $summary['healthy_nodes'],
     *     $summary['total_nodes']
     * );
     *
     * // Per-node health
     * foreach ($health['data']['nodes'] as $nodeId => $nodeHealth) {
     *     if (isset($nodeHealth['error'])) {
     *         echo "Node $nodeId: ERROR - " . $nodeHealth['error'] . "\n";
     *     } else {
     *         echo sprintf(
     *             "Node %s: CPU %d%%, Memory %d%%, Uptime: %s\n",
     *             $nodeHealth['name'],
     *             $nodeHealth['cpu_load'],
     *             $nodeHealth['memory_percent'],
     *             $nodeHealth['uptime']
     *         );
     *     }
     * }
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": {
     *         "nodes": {
     *             "1": {
     *                 "name": "router1",
     *                 "status": "healthy",
     *                 "cpu_load": 15,
     *                 "free_memory": 268435456,
     *                 "total_memory": 536870912,
     *                 "memory_percent": 50,
     *                 "uptime": "5d 12h 30m",
     *                 "version": "7.12",
     *                 "board_name": "CHR",
     *                 "architecture": "x86_64"
     *             }
     *         },
     *         "summary": {
     *             "total_nodes": 3,
     *             "healthy_nodes": 3,
     *             "unhealthy_nodes": 0
     *         }
     *     }
     * }
     * ```
     */
    public function getClusterHealth(): array
    {
        return $this->client->get('/api/v1/cluster/health');
    }

    /**
     * Get cluster statistics
     *
     * Returns summary statistics about the cluster.
     *
     * @return array Cluster statistics
     * @throws RouterOSApiException On API errors
     *
     * Required scope: nodes:read
     *
     * @example
     * ```php
     * $stats = $clusterApi->getClusterStats();
     *
     * echo "Total nodes: " . $stats['data']['total_nodes'] . "\n";
     * echo "Active nodes: " . $stats['data']['active_nodes'] . "\n";
     * echo "Offline nodes: " . $stats['data']['offline_nodes'] . "\n";
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": {
     *         "total_nodes": 3,
     *         "active_nodes": 3,
     *         "offline_nodes": 0
     *     }
     * }
     * ```
     */
    public function getClusterStats(): array
    {
        return $this->client->get('/api/v1/cluster/stats');
    }

    // =========================================================================
    // UTILITY METHODS
    // =========================================================================

    /**
     * Find a node by name
     *
     * Searches through all nodes to find one with the matching name.
     *
     * @param string $name Node name to search for
     * @return array|null Node data if found, null otherwise
     * @throws RouterOSApiException On API errors
     *
     * @example
     * ```php
     * $node = $clusterApi->findNodeByName('router1');
     *
     * if ($node) {
     *     echo "Found node with ID: " . $node['id'] . "\n";
     * } else {
     *     echo "Node not found\n";
     * }
     * ```
     */
    public function findNodeByName(string $name): ?array
    {
        $nodes = $this->listNodes();

        foreach ($nodes['data'] as $node) {
            if ($node['name'] === $name) {
                return $node;
            }
        }

        return null;
    }

    /**
     * Get all online nodes
     *
     * Returns only nodes that are currently online and responding.
     *
     * @return array List of online nodes
     * @throws RouterOSApiException On API errors
     *
     * @example
     * ```php
     * $onlineNodes = $clusterApi->getOnlineNodes();
     *
     * echo count($onlineNodes) . " nodes are online\n";
     * foreach ($onlineNodes as $node) {
     *     echo "- " . $node['name'] . " (" . $node['host'] . ")\n";
     * }
     * ```
     */
    public function getOnlineNodes(): array
    {
        $nodes = $this->listNodes();

        return array_filter($nodes['data'], function ($node) {
            return $node['status'] === 'online';
        });
    }

    /**
     * Get all offline nodes
     *
     * Returns only nodes that are currently offline or unreachable.
     *
     * @return array List of offline nodes
     * @throws RouterOSApiException On API errors
     *
     * @example
     * ```php
     * $offlineNodes = $clusterApi->getOfflineNodes();
     *
     * if (count($offlineNodes) > 0) {
     *     echo "WARNING: " . count($offlineNodes) . " nodes are offline!\n";
     *     foreach ($offlineNodes as $node) {
     *         echo "- " . $node['name'] . " (" . $node['host'] . ")\n";
     *     }
     * }
     * ```
     */
    public function getOfflineNodes(): array
    {
        $nodes = $this->listNodes();

        return array_filter($nodes['data'], function ($node) {
            return $node['status'] === 'offline';
        });
    }
}

// =============================================================================
// STANDALONE USAGE EXAMPLE
// =============================================================================
/*
// Example: Complete cluster management workflow

require_once 'RouterOSClient.php';
require_once 'cluster_api.php';

// Initialize client
$client = new RouterOSClient('https://routeros-cm.example.com', 'your-api-token');
$clusterApi = new ClusterApi($client);

try {
    // 1. Check current cluster status
    $stats = $clusterApi->getClusterStats();
    echo "Current cluster has {$stats['data']['total_nodes']} nodes\n";

    // 2. Add a new router to the cluster
    $newNode = $clusterApi->createNode(
        'new-router',           // Name
        '192.168.1.100',        // IP address
        'admin',                // Username
        'secretpassword',       // Password
        8728,                   // Port
        false                   // SSL
    );
    echo "Created node: {$newNode['data']['name']} (ID: {$newNode['data']['id']})\n";

    // 3. Test the connection
    $testResult = $clusterApi->testConnection($newNode['data']['id']);
    echo "Connection test: {$testResult['data']['message']}\n";

    // 4. Get cluster health
    $health = $clusterApi->getClusterHealth();
    foreach ($health['data']['nodes'] as $id => $nodeHealth) {
        echo "Node {$nodeHealth['name']}: CPU {$nodeHealth['cpu_load']}%\n";
    }

    // 5. Update the node name
    $clusterApi->updateNode($newNode['data']['id'], [
        'name' => 'new-router-primary'
    ]);
    echo "Node renamed successfully\n";

    // 6. List all nodes
    $nodes = $clusterApi->listNodes();
    echo "\nAll nodes:\n";
    foreach ($nodes['data'] as $node) {
        echo "  - {$node['name']} ({$node['host']}) - {$node['status']}\n";
    }

} catch (RouterOSApiException $e) {
    echo "API Error: " . $e->getMessage() . "\n";
    echo "HTTP Status: " . $e->getHttpStatus() . "\n";
    echo "Error Code: " . $e->getErrorCode() . "\n";
}
*/
