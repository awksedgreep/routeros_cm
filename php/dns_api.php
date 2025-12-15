<?php
/**
 * RouterOS Cluster Manager - DNS Management API
 *
 * This file provides functions for managing DNS records across the RouterOS cluster.
 * All DNS operations are performed cluster-wide - records are synchronized across
 * all active nodes automatically.
 *
 * @package RouterOSCM
 * @version 1.0.0
 *
 * REQUIRED SCOPES:
 * ================
 * - dns:read  - Required for listing records, getting settings
 * - dns:write - Required for creating, updating, deleting records, flushing cache
 *
 * CLUSTER BEHAVIOR:
 * =================
 * All DNS operations are performed on ALL active nodes in the cluster. The API returns
 * information about which nodes succeeded and which failed for each operation.
 *
 * USAGE:
 * ======
 * ```php
 * require_once 'RouterOSClient.php';
 * require_once 'dns_api.php';
 *
 * $client = new RouterOSClient('https://your-server.com', 'your-token');
 * $dnsApi = new DnsApi($client);
 *
 * // Create a DNS record on all nodes
 * $result = $dnsApi->createRecord('app.local', '192.168.1.100');
 * ```
 */

require_once __DIR__ . '/RouterOSClient.php';

/**
 * DNS Record Management API
 *
 * Provides methods for:
 * - Creating, updating, and deleting DNS records
 * - Listing DNS records across the cluster
 * - Managing DNS server settings
 * - Flushing DNS cache
 */
class DnsApi
{
    /** @var RouterOSClient API client instance */
    private RouterOSClient $client;

    /**
     * Create a new DnsApi instance
     *
     * @param RouterOSClient $client Configured API client
     */
    public function __construct(RouterOSClient $client)
    {
        $this->client = $client;
    }

    // =========================================================================
    // DNS RECORD MANAGEMENT
    // =========================================================================

    /**
     * List all DNS records across the cluster
     *
     * Returns DNS records from all active nodes, grouped by record name.
     * Each record shows which nodes have it configured.
     *
     * @param string|null $type Optional: Filter by record type ('A', 'AAAA', 'CNAME')
     * @return array List of DNS records
     * @throws RouterOSApiException On API errors
     *
     * Required scope: dns:read
     *
     * @example
     * ```php
     * // Get all DNS records
     * $records = $dnsApi->listRecords();
     *
     * foreach ($records['data'] as $record) {
     *     echo sprintf(
     *         "%s -> %s (on %d nodes)\n",
     *         $record['name'],
     *         $record['address'] ?? $record['cname'],
     *         count($record['nodes'])
     *     );
     * }
     *
     * // Get only A records
     * $aRecords = $dnsApi->listRecords('A');
     *
     * // Get only CNAME records
     * $cnameRecords = $dnsApi->listRecords('CNAME');
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": [
     *         {
     *             "name": "app.local",
     *             "type": "A",
     *             "address": "192.168.1.100",
     *             "ttl": "1d",
     *             "comment": "Application server",
     *             "nodes": [
     *                 {
     *                     "node_name": "router1",
     *                     "node_id": 1,
     *                     "record_id": "*1A"
     *                 },
     *                 {
     *                     "node_name": "router2",
     *                     "node_id": 2,
     *                     "record_id": "*1B"
     *                 }
     *             ]
     *         }
     *     ]
     * }
     * ```
     */
    public function listRecords(?string $type = null): array
    {
        $params = [];
        if ($type !== null) {
            $params['type'] = $type;
        }

        return $this->client->get('/api/v1/dns/records', $params);
    }

    /**
     * Get a specific DNS record by name
     *
     * @param string $name Record name (domain name)
     * @return array Record details
     * @throws RouterOSApiException On API errors (404 if not found)
     *
     * Required scope: dns:read
     *
     * @example
     * ```php
     * $record = $dnsApi->getRecord('app.local');
     *
     * echo "Name: " . $record['data']['name'] . "\n";
     * echo "Address: " . $record['data']['address'] . "\n";
     * echo "TTL: " . $record['data']['ttl'] . "\n";
     * echo "Configured on " . count($record['data']['nodes']) . " nodes\n";
     * ```
     */
    public function getRecord(string $name): array
    {
        return $this->client->get("/api/v1/dns/records/" . urlencode($name));
    }

    /**
     * Create a new DNS A record
     *
     * Creates an A record (hostname to IPv4 address mapping) on all active nodes.
     *
     * @param string $name Domain name (e.g., 'app.local', 'server.internal')
     * @param string $address IPv4 address (e.g., '192.168.1.100')
     * @param string|null $ttl Time to live (e.g., '1d', '1h', '5m'). Default: server default
     * @param string|null $comment Optional comment/description
     * @return array Operation result with success/failure per node
     * @throws RouterOSApiException On API errors
     *
     * Required scope: dns:write
     *
     * @example
     * ```php
     * // Simple A record
     * $result = $dnsApi->createARecord('app.local', '192.168.1.100');
     *
     * // A record with TTL and comment
     * $result = $dnsApi->createARecord(
     *     'api.internal',
     *     '192.168.1.50',
     *     '1h',                    // 1 hour TTL
     *     'API server endpoint'    // Comment
     * );
     *
     * // Check results
     * echo "Created on " . count($result['data']['successes']) . " nodes\n";
     * if (!empty($result['data']['failures'])) {
     *     echo "Failed on " . count($result['data']['failures']) . " nodes\n";
     * }
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": {
     *         "operation": "create",
     *         "resource": "dns_record",
     *         "successes": [
     *             {"node": "router1", "node_id": 1, "id": "*1A"}
     *         ],
     *         "failures": []
     *     }
     * }
     * ```
     */
    public function createARecord(
        string $name,
        string $address,
        ?string $ttl = null,
        ?string $comment = null
    ): array {
        $data = [
            'name' => $name,
            'address' => $address,
            'type' => 'A'
        ];

        if ($ttl !== null) {
            $data['ttl'] = $ttl;
        }

        if ($comment !== null) {
            $data['comment'] = $comment;
        }

        return $this->client->post('/api/v1/dns/records', $data);
    }

    /**
     * Create a new DNS AAAA record (IPv6)
     *
     * Creates an AAAA record (hostname to IPv6 address mapping) on all active nodes.
     *
     * @param string $name Domain name
     * @param string $address IPv6 address
     * @param string|null $ttl Time to live
     * @param string|null $comment Optional comment
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: dns:write
     *
     * @example
     * ```php
     * $result = $dnsApi->createAAAARecord(
     *     'ipv6.local',
     *     '2001:db8::1',
     *     '1d'
     * );
     * ```
     */
    public function createAAAARecord(
        string $name,
        string $address,
        ?string $ttl = null,
        ?string $comment = null
    ): array {
        $data = [
            'name' => $name,
            'address' => $address,
            'type' => 'AAAA'
        ];

        if ($ttl !== null) {
            $data['ttl'] = $ttl;
        }

        if ($comment !== null) {
            $data['comment'] = $comment;
        }

        return $this->client->post('/api/v1/dns/records', $data);
    }

    /**
     * Create a new DNS CNAME record
     *
     * Creates a CNAME record (alias) on all active nodes.
     *
     * @param string $name Domain name (the alias)
     * @param string $cname Target domain name (what the alias points to)
     * @param string|null $ttl Time to live
     * @param string|null $comment Optional comment
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: dns:write
     *
     * @example
     * ```php
     * // Create alias: www.local -> app.local
     * $result = $dnsApi->createCNAMERecord('www.local', 'app.local');
     *
     * // With TTL
     * $result = $dnsApi->createCNAMERecord(
     *     'mail.local',
     *     'mailserver.local',
     *     '1h'
     * );
     * ```
     */
    public function createCNAMERecord(
        string $name,
        string $cname,
        ?string $ttl = null,
        ?string $comment = null
    ): array {
        $data = [
            'name' => $name,
            'cname' => $cname,
            'type' => 'CNAME'
        ];

        if ($ttl !== null) {
            $data['ttl'] = $ttl;
        }

        if ($comment !== null) {
            $data['comment'] = $comment;
        }

        return $this->client->post('/api/v1/dns/records', $data);
    }

    /**
     * Create a DNS record (generic method)
     *
     * Creates any type of DNS record. Use the type-specific methods for convenience.
     *
     * @param array $data Record data:
     *                    - name: string (required) - Domain name
     *                    - address: string - IP address (for A/AAAA)
     *                    - cname: string - Target domain (for CNAME)
     *                    - type: string - Record type (A, AAAA, CNAME)
     *                    - ttl: string - Time to live
     *                    - comment: string - Description
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: dns:write
     *
     * @example
     * ```php
     * $result = $dnsApi->createRecord([
     *     'name' => 'custom.local',
     *     'address' => '10.0.0.1',
     *     'type' => 'A',
     *     'ttl' => '30m',
     *     'comment' => 'Custom record'
     * ]);
     * ```
     */
    public function createRecord(array $data): array
    {
        return $this->client->post('/api/v1/dns/records', $data);
    }

    /**
     * Update a DNS record by name
     *
     * Updates an existing DNS record on all nodes where it exists.
     *
     * @param string $name Record name to update
     * @param array $data Fields to update:
     *                    - address: string - New IP address
     *                    - cname: string - New CNAME target
     *                    - ttl: string - New TTL
     *                    - comment: string - New comment
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: dns:write
     *
     * @example
     * ```php
     * // Update IP address
     * $result = $dnsApi->updateRecord('app.local', [
     *     'address' => '192.168.1.200'
     * ]);
     *
     * // Update TTL and comment
     * $result = $dnsApi->updateRecord('app.local', [
     *     'ttl' => '2h',
     *     'comment' => 'Updated application server'
     * ]);
     *
     * // Check results
     * echo "Updated on " . count($result['data']['successes']) . " nodes\n";
     * ```
     */
    public function updateRecord(string $name, array $data): array
    {
        return $this->client->put("/api/v1/dns/records/" . urlencode($name), $data);
    }

    /**
     * Delete a DNS record by name
     *
     * Deletes the record from all nodes where it exists.
     *
     * @param string $name Record name to delete
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: dns:write
     *
     * @example
     * ```php
     * // Delete a record
     * $result = $dnsApi->deleteRecord('old-app.local');
     *
     * echo "Deleted from " . count($result['data']['successes']) . " nodes\n";
     *
     * // With error handling
     * try {
     *     $dnsApi->deleteRecord('nonexistent.local');
     * } catch (RouterOSApiException $e) {
     *     echo "Delete failed: " . $e->getMessage() . "\n";
     * }
     * ```
     */
    public function deleteRecord(string $name): array
    {
        return $this->client->delete("/api/v1/dns/records/" . urlencode($name));
    }

    // =========================================================================
    // DNS SERVER SETTINGS
    // =========================================================================

    /**
     * Get DNS server settings
     *
     * Returns DNS server configuration from all active nodes.
     *
     * @return array DNS server settings
     * @throws RouterOSApiException On API errors
     *
     * Required scope: dns:read
     *
     * @example
     * ```php
     * $settings = $dnsApi->getSettings();
     *
     * foreach ($settings['data'] as $nodeSettings) {
     *     echo sprintf(
     *         "Node %s: Servers: %s, Cache: %s\n",
     *         $nodeSettings['node_name'],
     *         $nodeSettings['servers'] ?? 'none',
     *         $nodeSettings['cache_size'] ?? 'default'
     *     );
     * }
     * ```
     */
    public function getSettings(): array
    {
        return $this->client->get('/api/v1/dns/settings');
    }

    /**
     * Update DNS server settings
     *
     * Updates DNS server configuration on all active nodes.
     *
     * @param array $data Settings to update:
     *                    - servers: string - Comma-separated upstream DNS servers
     *                    - allow-remote-requests: bool - Allow DNS requests from network
     *                    - cache-size: string - DNS cache size
     *                    - cache-max-ttl: string - Maximum cache TTL
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: dns:write
     *
     * @example
     * ```php
     * // Set upstream DNS servers
     * $result = $dnsApi->updateSettings([
     *     'servers' => '8.8.8.8,8.8.4.4'
     * ]);
     *
     * // Configure DNS cache
     * $result = $dnsApi->updateSettings([
     *     'cache-size' => '4096KiB',
     *     'cache-max-ttl' => '1d'
     * ]);
     *
     * // Enable remote requests
     * $result = $dnsApi->updateSettings([
     *     'allow-remote-requests' => true
     * ]);
     * ```
     */
    public function updateSettings(array $data): array
    {
        return $this->client->patch('/api/v1/dns/settings', $data);
    }

    // =========================================================================
    // DNS CACHE
    // =========================================================================

    /**
     * Flush DNS cache on all nodes
     *
     * Clears the DNS cache on all active nodes in the cluster.
     * Useful after making DNS changes to ensure fresh lookups.
     *
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: dns:write
     *
     * @example
     * ```php
     * // Flush cache after updating records
     * $dnsApi->updateRecord('app.local', ['address' => '192.168.1.200']);
     * $result = $dnsApi->flushCache();
     *
     * echo "Cache flushed on " . count($result['data']['successes']) . " nodes\n";
     * ```
     */
    public function flushCache(): array
    {
        return $this->client->post('/api/v1/dns/cache/flush');
    }

    // =========================================================================
    // UTILITY METHODS
    // =========================================================================

    /**
     * Check if a DNS record exists
     *
     * @param string $name Record name to check
     * @return bool True if record exists on at least one node
     *
     * @example
     * ```php
     * if ($dnsApi->recordExists('app.local')) {
     *     echo "Record exists\n";
     * } else {
     *     echo "Record not found\n";
     * }
     * ```
     */
    public function recordExists(string $name): bool
    {
        try {
            $this->getRecord($name);
            return true;
        } catch (RouterOSApiException $e) {
            if ($e->getHttpStatus() === 404) {
                return false;
            }
            throw $e;
        }
    }

    /**
     * Create or update a DNS record
     *
     * If the record exists, it will be updated. Otherwise, it will be created.
     *
     * @param string $name Record name
     * @param string $address IP address
     * @param string|null $ttl Time to live
     * @param string|null $comment Optional comment
     * @return array Operation result
     *
     * @example
     * ```php
     * // Will create if not exists, update if exists
     * $result = $dnsApi->upsertARecord('app.local', '192.168.1.100', '1h');
     * ```
     */
    public function upsertARecord(
        string $name,
        string $address,
        ?string $ttl = null,
        ?string $comment = null
    ): array {
        if ($this->recordExists($name)) {
            $data = ['address' => $address];
            if ($ttl !== null) {
                $data['ttl'] = $ttl;
            }
            if ($comment !== null) {
                $data['comment'] = $comment;
            }
            return $this->updateRecord($name, $data);
        } else {
            return $this->createARecord($name, $address, $ttl, $comment);
        }
    }

    /**
     * Get all records for a specific type
     *
     * @param string $type Record type ('A', 'AAAA', 'CNAME')
     * @return array List of records
     *
     * @example
     * ```php
     * $aRecords = $dnsApi->getRecordsByType('A');
     * $cnameRecords = $dnsApi->getRecordsByType('CNAME');
     * ```
     */
    public function getRecordsByType(string $type): array
    {
        return $this->listRecords($type);
    }

    /**
     * Bulk create DNS records
     *
     * Creates multiple DNS records in sequence.
     *
     * @param array $records Array of record data arrays
     * @return array Results for each record
     *
     * @example
     * ```php
     * $results = $dnsApi->bulkCreate([
     *     ['name' => 'app1.local', 'address' => '192.168.1.101', 'type' => 'A'],
     *     ['name' => 'app2.local', 'address' => '192.168.1.102', 'type' => 'A'],
     *     ['name' => 'www.local', 'cname' => 'app1.local', 'type' => 'CNAME']
     * ]);
     *
     * foreach ($results as $name => $result) {
     *     if (isset($result['error'])) {
     *         echo "Failed to create $name: {$result['error']}\n";
     *     } else {
     *         echo "Created $name successfully\n";
     *     }
     * }
     * ```
     */
    public function bulkCreate(array $records): array
    {
        $results = [];

        foreach ($records as $record) {
            $name = $record['name'] ?? 'unknown';
            try {
                $results[$name] = $this->createRecord($record);
            } catch (RouterOSApiException $e) {
                $results[$name] = ['error' => $e->getMessage()];
            }
        }

        return $results;
    }

    /**
     * Bulk delete DNS records
     *
     * Deletes multiple DNS records in sequence.
     *
     * @param array $names Array of record names to delete
     * @return array Results for each record
     *
     * @example
     * ```php
     * $results = $dnsApi->bulkDelete([
     *     'old-app1.local',
     *     'old-app2.local',
     *     'deprecated.local'
     * ]);
     * ```
     */
    public function bulkDelete(array $names): array
    {
        $results = [];

        foreach ($names as $name) {
            try {
                $results[$name] = $this->deleteRecord($name);
            } catch (RouterOSApiException $e) {
                $results[$name] = ['error' => $e->getMessage()];
            }
        }

        return $results;
    }
}

// =============================================================================
// STANDALONE USAGE EXAMPLE
// =============================================================================
/*
// Example: Complete DNS management workflow

require_once 'RouterOSClient.php';
require_once 'dns_api.php';

// Initialize client
$client = new RouterOSClient('https://routeros-cm.example.com', 'your-api-token');
$dnsApi = new DnsApi($client);

try {
    // 1. List existing DNS records
    echo "Current DNS records:\n";
    $records = $dnsApi->listRecords();
    foreach ($records['data'] as $record) {
        $target = $record['address'] ?? $record['cname'] ?? 'unknown';
        echo "  {$record['name']} -> $target\n";
    }

    // 2. Create new DNS records
    echo "\nCreating DNS records...\n";

    // A record for web server
    $result = $dnsApi->createARecord('web.internal', '192.168.1.10', '1h', 'Web server');
    echo "Created web.internal: " . count($result['data']['successes']) . " nodes\n";

    // A record for database
    $result = $dnsApi->createARecord('db.internal', '192.168.1.20', '1h', 'Database server');
    echo "Created db.internal: " . count($result['data']['successes']) . " nodes\n";

    // CNAME alias
    $result = $dnsApi->createCNAMERecord('www.internal', 'web.internal');
    echo "Created www.internal alias\n";

    // 3. Update a record
    echo "\nUpdating web.internal...\n";
    $result = $dnsApi->updateRecord('web.internal', [
        'address' => '192.168.1.11',
        'comment' => 'Web server - updated IP'
    ]);
    echo "Updated on " . count($result['data']['successes']) . " nodes\n";

    // 4. Flush DNS cache after changes
    echo "\nFlushing DNS cache...\n";
    $result = $dnsApi->flushCache();
    echo "Cache flushed on " . count($result['data']['successes']) . " nodes\n";

    // 5. Delete a record
    echo "\nDeleting www.internal...\n";
    $result = $dnsApi->deleteRecord('www.internal');
    echo "Deleted from " . count($result['data']['successes']) . " nodes\n";

    // 6. Bulk operations
    echo "\nBulk creating records...\n";
    $bulkResults = $dnsApi->bulkCreate([
        ['name' => 'app1.internal', 'address' => '192.168.1.101', 'type' => 'A'],
        ['name' => 'app2.internal', 'address' => '192.168.1.102', 'type' => 'A'],
        ['name' => 'app3.internal', 'address' => '192.168.1.103', 'type' => 'A']
    ]);

    foreach ($bulkResults as $name => $result) {
        if (isset($result['error'])) {
            echo "  FAILED: $name - {$result['error']}\n";
        } else {
            echo "  OK: $name\n";
        }
    }

} catch (RouterOSApiException $e) {
    echo "API Error: " . $e->getMessage() . "\n";
    echo "HTTP Status: " . $e->getHttpStatus() . "\n";
}
*/
