<?php
/**
 * RouterOS Cluster Manager - Audit Log API Client
 *
 * This file provides a PHP client for accessing audit logs from the RouterOS
 * Cluster Manager API. Audit logs track all changes made to the system including:
 * - DNS record operations (create, update, delete)
 * - WireGuard interface and peer changes
 * - GRE tunnel configuration
 * - Node management (add, remove, update)
 * - User management
 *
 * REQUIREMENTS:
 * - PHP 7.4 or higher
 * - cURL extension enabled
 * - RouterOSClient.php (base client class)
 *
 * AUTHENTICATION:
 * Requires an API token with 'audit:read' scope.
 *
 * @package     RouterOSCM
 * @subpackage  AuditAPI
 * @version     1.0.0
 * @author      RouterOS Cluster Manager
 * @license     MIT
 */

require_once __DIR__ . '/RouterOSClient.php';

/**
 * AuditAPI - Client for audit log operations
 *
 * Provides methods to query and retrieve audit logs from the RouterOS
 * Cluster Manager. All actions performed through the API are logged and
 * can be retrieved using this client.
 *
 * REQUIRED SCOPE: audit:read
 *
 * Example usage:
 * ```php
 * $client = new RouterOSClient('https://your-server.com', 'your-api-token');
 * $auditApi = new AuditAPI($client);
 *
 * // Get recent logs
 * $logs = $auditApi->listLogs();
 *
 * // Get failed operations
 * $errors = $auditApi->listLogs(['success' => false]);
 * ```
 */
class AuditAPI
{
    /**
     * @var RouterOSClient The API client instance
     */
    private RouterOSClient $client;

    /**
     * @var string Base path for audit API endpoints
     */
    private const BASE_PATH = '/api/v1/audit';

    /**
     * Valid action types for filtering
     */
    public const ACTION_CREATE = 'create';
    public const ACTION_UPDATE = 'update';
    public const ACTION_DELETE = 'delete';

    /**
     * Valid resource types for filtering
     */
    public const RESOURCE_DNS_RECORD = 'dns_record';
    public const RESOURCE_WIREGUARD_INTERFACE = 'wireguard_interface';
    public const RESOURCE_WIREGUARD_PEER = 'wireguard_peer';
    public const RESOURCE_GRE_TUNNEL = 'gre_tunnel';
    public const RESOURCE_NODE = 'node';
    public const RESOURCE_USER = 'user';
    public const RESOURCE_ROUTEROS_USER = 'routeros_user';

    /**
     * Constructor
     *
     * @param RouterOSClient $client An authenticated API client instance
     *
     * Example:
     * ```php
     * $client = new RouterOSClient('https://routeros-cm.example.com', 'your-token');
     * $auditApi = new AuditAPI($client);
     * ```
     */
    public function __construct(RouterOSClient $client)
    {
        $this->client = $client;
    }

    /**
     * List audit logs with optional filtering and pagination
     *
     * Retrieves a paginated list of audit logs. Results can be filtered by
     * action type, resource type, success status, and date range.
     *
     * @param array $options Filter and pagination options:
     *   - page (int): Page number, starting from 1 (default: 1)
     *   - per_page (int): Items per page, max 100 (default: 50)
     *   - action (string): Filter by action type (create, update, delete)
     *   - resource_type (string): Filter by resource type (dns_record, node, etc.)
     *   - success (bool): Filter by success status (true for successful, false for failed)
     *   - from (string): Start date in ISO 8601 format (e.g., '2024-01-01T00:00:00Z')
     *   - to (string): End date in ISO 8601 format
     *
     * @return array Response with:
     *   - data (array): List of audit log entries
     *   - meta (array): Pagination metadata (total, page, per_page, total_pages)
     *
     * @throws RouterOSClientException On API error
     *
     * Example - Get all logs:
     * ```php
     * $logs = $auditApi->listLogs();
     * foreach ($logs['data'] as $log) {
     *     echo "{$log['inserted_at']}: {$log['action']} {$log['resource_type']}\n";
     * }
     * echo "Total logs: {$logs['meta']['total']}\n";
     * ```
     *
     * Example - Get failed operations:
     * ```php
     * $errors = $auditApi->listLogs(['success' => false]);
     * foreach ($errors['data'] as $error) {
     *     echo "Failed: {$error['action']} on {$error['resource_type']}\n";
     *     print_r($error['details']);
     * }
     * ```
     *
     * Example - Get DNS changes from last 24 hours:
     * ```php
     * $yesterday = (new DateTime())->modify('-1 day')->format(DateTime::ISO8601);
     * $dnsLogs = $auditApi->listLogs([
     *     'resource_type' => AuditAPI::RESOURCE_DNS_RECORD,
     *     'from' => $yesterday
     * ]);
     * ```
     *
     * Example - Paginate through results:
     * ```php
     * $page = 1;
     * do {
     *     $response = $auditApi->listLogs(['page' => $page, 'per_page' => 100]);
     *     foreach ($response['data'] as $log) {
     *         processLog($log);
     *     }
     *     $page++;
     * } while ($page <= $response['meta']['total_pages']);
     * ```
     */
    public function listLogs(array $options = []): array
    {
        $query = [];

        // Pagination
        if (isset($options['page'])) {
            $query['page'] = (int) $options['page'];
        }
        if (isset($options['per_page'])) {
            $query['per_page'] = min((int) $options['per_page'], 100);
        }

        // Filters
        if (isset($options['action'])) {
            $query['action'] = $options['action'];
        }
        if (isset($options['resource_type'])) {
            $query['resource_type'] = $options['resource_type'];
        }
        if (isset($options['success'])) {
            $query['success'] = $options['success'] ? 'true' : 'false';
        }
        if (isset($options['from'])) {
            $query['from'] = $options['from'];
        }
        if (isset($options['to'])) {
            $query['to'] = $options['to'];
        }

        $path = self::BASE_PATH;
        if (!empty($query)) {
            $path .= '?' . http_build_query($query);
        }

        return $this->client->get($path);
    }

    /**
     * Get a specific audit log entry by ID
     *
     * Retrieves the full details of a single audit log entry.
     *
     * @param int $id The audit log entry ID
     *
     * @return array The audit log entry with fields:
     *   - id (int): Log entry ID
     *   - action (string): Action performed (create, update, delete)
     *   - resource_type (string): Type of resource affected
     *   - resource_id (string): ID of the affected resource
     *   - success (bool): Whether the operation succeeded
     *   - details (array): Additional operation details
     *   - ip_address (string|null): IP address of the requester
     *   - user (array|null): User who performed the action (id, email)
     *   - inserted_at (string): Timestamp of the log entry
     *
     * @throws RouterOSClientException If log not found or on API error
     *
     * Example:
     * ```php
     * $log = $auditApi->getLog(123);
     * echo "Action: {$log['data']['action']}\n";
     * echo "Resource: {$log['data']['resource_type']} (ID: {$log['data']['resource_id']})\n";
     * echo "Success: " . ($log['data']['success'] ? 'Yes' : 'No') . "\n";
     * echo "User: {$log['data']['user']['email']}\n";
     * echo "Details: " . json_encode($log['data']['details'], JSON_PRETTY_PRINT) . "\n";
     * ```
     */
    public function getLog(int $id): array
    {
        return $this->client->get(self::BASE_PATH . "/{$id}");
    }

    /**
     * Get audit log statistics
     *
     * Retrieves summary statistics about audit logs including total count
     * and count of entries created today.
     *
     * @return array Statistics with:
     *   - total (int): Total number of audit log entries
     *   - today (int): Number of entries created today
     *
     * @throws RouterOSClientException On API error
     *
     * Example:
     * ```php
     * $stats = $auditApi->getStats();
     * echo "Total audit entries: {$stats['data']['total']}\n";
     * echo "Entries today: {$stats['data']['today']}\n";
     * ```
     */
    public function getStats(): array
    {
        return $this->client->get(self::BASE_PATH . '/stats');
    }

    // =========================================================================
    // CONVENIENCE METHODS
    // =========================================================================

    /**
     * Get all logs for a specific action type
     *
     * Convenience method to filter logs by action.
     *
     * @param string $action Action type (create, update, delete)
     * @param array $options Additional filter options
     *
     * @return array Filtered audit logs
     *
     * Example - Get all create operations:
     * ```php
     * $creates = $auditApi->getLogsByAction(AuditAPI::ACTION_CREATE);
     * ```
     *
     * Example - Get delete operations from today:
     * ```php
     * $today = (new DateTime())->format('Y-m-d') . 'T00:00:00Z';
     * $deletes = $auditApi->getLogsByAction(AuditAPI::ACTION_DELETE, [
     *     'from' => $today
     * ]);
     * ```
     */
    public function getLogsByAction(string $action, array $options = []): array
    {
        $options['action'] = $action;
        return $this->listLogs($options);
    }

    /**
     * Get all logs for a specific resource type
     *
     * Convenience method to filter logs by resource type.
     *
     * @param string $resourceType Resource type constant
     * @param array $options Additional filter options
     *
     * @return array Filtered audit logs
     *
     * Example - Get all DNS record changes:
     * ```php
     * $dnsLogs = $auditApi->getLogsByResourceType(AuditAPI::RESOURCE_DNS_RECORD);
     * ```
     *
     * Example - Get WireGuard interface deletions:
     * ```php
     * $wgDeletes = $auditApi->getLogsByResourceType(
     *     AuditAPI::RESOURCE_WIREGUARD_INTERFACE,
     *     ['action' => AuditAPI::ACTION_DELETE]
     * );
     * ```
     */
    public function getLogsByResourceType(string $resourceType, array $options = []): array
    {
        $options['resource_type'] = $resourceType;
        return $this->listLogs($options);
    }

    /**
     * Get all failed operations
     *
     * Retrieves audit logs for operations that failed.
     *
     * @param array $options Additional filter options
     *
     * @return array Failed operation logs
     *
     * Example:
     * ```php
     * $failures = $auditApi->getFailedOperations();
     * foreach ($failures['data'] as $failure) {
     *     echo "Failed {$failure['action']} on {$failure['resource_type']}\n";
     *     if (isset($failure['details']['error'])) {
     *         echo "  Error: {$failure['details']['error']}\n";
     *     }
     * }
     * ```
     */
    public function getFailedOperations(array $options = []): array
    {
        $options['success'] = false;
        return $this->listLogs($options);
    }

    /**
     * Get logs for a date range
     *
     * Convenience method to get logs within a specific date range.
     *
     * @param DateTime|string $from Start date
     * @param DateTime|string $to End date
     * @param array $options Additional filter options
     *
     * @return array Filtered audit logs
     *
     * Example - Get logs from last week:
     * ```php
     * $lastWeek = (new DateTime())->modify('-7 days');
     * $now = new DateTime();
     * $logs = $auditApi->getLogsByDateRange($lastWeek, $now);
     * ```
     *
     * Example - Get January 2024 DNS changes:
     * ```php
     * $logs = $auditApi->getLogsByDateRange(
     *     '2024-01-01T00:00:00Z',
     *     '2024-01-31T23:59:59Z',
     *     ['resource_type' => AuditAPI::RESOURCE_DNS_RECORD]
     * );
     * ```
     */
    public function getLogsByDateRange($from, $to, array $options = []): array
    {
        if ($from instanceof DateTime) {
            $from = $from->format(DateTime::ISO8601);
        }
        if ($to instanceof DateTime) {
            $to = $to->format(DateTime::ISO8601);
        }

        $options['from'] = $from;
        $options['to'] = $to;
        return $this->listLogs($options);
    }

    /**
     * Get today's audit logs
     *
     * Convenience method to get all logs from today.
     *
     * @param array $options Additional filter options
     *
     * @return array Today's audit logs
     *
     * Example:
     * ```php
     * $todayLogs = $auditApi->getTodaysLogs();
     * echo "Operations today: {$todayLogs['meta']['total']}\n";
     * ```
     *
     * Example - Get today's failed operations:
     * ```php
     * $failures = $auditApi->getTodaysLogs(['success' => false]);
     * ```
     */
    public function getTodaysLogs(array $options = []): array
    {
        $today = (new DateTime())->format('Y-m-d') . 'T00:00:00Z';
        $options['from'] = $today;
        return $this->listLogs($options);
    }

    /**
     * Search logs for a specific resource ID
     *
     * Retrieves all audit logs related to a specific resource.
     * Note: This fetches all logs and filters client-side since the API
     * doesn't support resource_id filtering directly.
     *
     * @param string $resourceId The resource ID to search for
     * @param string|null $resourceType Optional resource type to narrow search
     * @param int $maxPages Maximum pages to search (default: 10)
     *
     * @return array Matching audit logs
     *
     * Example - Get all changes to a specific DNS record:
     * ```php
     * $recordLogs = $auditApi->getLogsForResource(
     *     'example.com',
     *     AuditAPI::RESOURCE_DNS_RECORD
     * );
     * foreach ($recordLogs as $log) {
     *     echo "{$log['inserted_at']}: {$log['action']}\n";
     * }
     * ```
     */
    public function getLogsForResource(
        string $resourceId,
        ?string $resourceType = null,
        int $maxPages = 10
    ): array {
        $results = [];
        $options = ['per_page' => 100];

        if ($resourceType !== null) {
            $options['resource_type'] = $resourceType;
        }

        for ($page = 1; $page <= $maxPages; $page++) {
            $options['page'] = $page;
            $response = $this->listLogs($options);

            foreach ($response['data'] as $log) {
                if ($log['resource_id'] === $resourceId) {
                    $results[] = $log;
                }
            }

            if ($page >= $response['meta']['total_pages']) {
                break;
            }
        }

        return $results;
    }

    /**
     * Export all logs to an array
     *
     * Fetches all audit logs by paginating through all pages.
     * Use with caution on large datasets.
     *
     * @param array $options Filter options
     * @param callable|null $progressCallback Optional callback called after each page
     *                                         Receives (currentPage, totalPages)
     *
     * @return array All matching audit logs
     *
     * Example - Export all logs:
     * ```php
     * $allLogs = $auditApi->exportAllLogs();
     * file_put_contents('audit_export.json', json_encode($allLogs, JSON_PRETTY_PRINT));
     * ```
     *
     * Example - Export with progress:
     * ```php
     * $allLogs = $auditApi->exportAllLogs([], function($page, $total) {
     *     echo "Fetching page {$page} of {$total}...\n";
     * });
     * ```
     *
     * Example - Export only DNS changes:
     * ```php
     * $dnsLogs = $auditApi->exportAllLogs([
     *     'resource_type' => AuditAPI::RESOURCE_DNS_RECORD
     * ]);
     * ```
     */
    public function exportAllLogs(array $options = [], ?callable $progressCallback = null): array
    {
        $allLogs = [];
        $page = 1;
        $options['per_page'] = 100;

        do {
            $options['page'] = $page;
            $response = $this->listLogs($options);

            foreach ($response['data'] as $log) {
                $allLogs[] = $log;
            }

            if ($progressCallback !== null) {
                $progressCallback($page, $response['meta']['total_pages']);
            }

            $page++;
        } while ($page <= $response['meta']['total_pages']);

        return $allLogs;
    }
}

// =============================================================================
// USAGE EXAMPLES
// =============================================================================

/*
 * Example 1: Basic Setup and Connection
 * =====================================
 *
 * require_once 'audit_api.php';
 *
 * // Create client with your API credentials
 * // The token must have 'audit:read' scope
 * $client = new RouterOSClient(
 *     'https://routeros-cm.example.com',
 *     'your-api-token-with-audit-read-scope'
 * );
 *
 * // Create audit API instance
 * $auditApi = new AuditAPI($client);
 *
 * // Test connection with stats
 * try {
 *     $stats = $auditApi->getStats();
 *     echo "Connected! Total audit entries: {$stats['data']['total']}\n";
 * } catch (RouterOSClientException $e) {
 *     echo "Connection failed: {$e->getMessage()}\n";
 * }
 */

/*
 * Example 2: Listing Recent Audit Logs
 * ====================================
 *
 * // Get the 20 most recent logs
 * $logs = $auditApi->listLogs(['per_page' => 20]);
 *
 * echo "Recent Activity:\n";
 * echo str_repeat('-', 80) . "\n";
 *
 * foreach ($logs['data'] as $log) {
 *     $status = $log['success'] ? 'OK' : 'FAILED';
 *     $user = $log['user'] ? $log['user']['email'] : 'System';
 *
 *     printf(
 *         "[%s] %-8s %-6s %-25s %s\n",
 *         substr($log['inserted_at'], 0, 19),
 *         $status,
 *         strtoupper($log['action']),
 *         $log['resource_type'],
 *         $user
 *     );
 * }
 *
 * echo str_repeat('-', 80) . "\n";
 * echo "Showing {$logs['meta']['per_page']} of {$logs['meta']['total']} entries\n";
 */

/*
 * Example 3: Filtering by Action Type
 * ===================================
 *
 * // Get all delete operations
 * $deletes = $auditApi->getLogsByAction(AuditAPI::ACTION_DELETE);
 * echo "Total delete operations: {$deletes['meta']['total']}\n\n";
 *
 * foreach ($deletes['data'] as $log) {
 *     echo "Deleted {$log['resource_type']}";
 *     if ($log['resource_id']) {
 *         echo " (ID: {$log['resource_id']})";
 *     }
 *     echo " at {$log['inserted_at']}\n";
 *
 *     if (!empty($log['details'])) {
 *         echo "  Details: " . json_encode($log['details']) . "\n";
 *     }
 * }
 */

/*
 * Example 4: Filtering by Resource Type
 * =====================================
 *
 * // Get all DNS record changes
 * $dnsLogs = $auditApi->getLogsByResourceType(AuditAPI::RESOURCE_DNS_RECORD);
 *
 * echo "DNS Record Changes:\n";
 * foreach ($dnsLogs['data'] as $log) {
 *     $action = ucfirst($log['action']);
 *     echo "{$action}: {$log['resource_id']}\n";
 *
 *     if (isset($log['details']['record'])) {
 *         $record = $log['details']['record'];
 *         echo "  Type: " . ($record['type'] ?? 'N/A') . "\n";
 *         echo "  Address: " . ($record['address'] ?? 'N/A') . "\n";
 *     }
 * }
 */

/*
 * Example 5: Finding Failed Operations
 * ====================================
 *
 * // Get failed operations
 * $failures = $auditApi->getFailedOperations();
 *
 * if ($failures['meta']['total'] === 0) {
 *     echo "No failed operations found!\n";
 * } else {
 *     echo "Failed Operations ({$failures['meta']['total']} total):\n\n";
 *
 *     foreach ($failures['data'] as $failure) {
 *         echo "FAILED: {$failure['action']} {$failure['resource_type']}\n";
 *         echo "  Time: {$failure['inserted_at']}\n";
 *
 *         if ($failure['user']) {
 *             echo "  User: {$failure['user']['email']}\n";
 *         }
 *
 *         if ($failure['ip_address']) {
 *             echo "  IP: {$failure['ip_address']}\n";
 *         }
 *
 *         if (!empty($failure['details'])) {
 *             echo "  Details:\n";
 *             foreach ($failure['details'] as $key => $value) {
 *                 if (is_array($value)) {
 *                     $value = json_encode($value);
 *                 }
 *                 echo "    {$key}: {$value}\n";
 *             }
 *         }
 *         echo "\n";
 *     }
 * }
 */

/*
 * Example 6: Date Range Filtering
 * ===============================
 *
 * // Get logs from the last 7 days
 * $weekAgo = (new DateTime())->modify('-7 days');
 * $now = new DateTime();
 *
 * $weekLogs = $auditApi->getLogsByDateRange($weekAgo, $now);
 * echo "Operations in the last 7 days: {$weekLogs['meta']['total']}\n";
 *
 * // Get logs from a specific date range
 * $logs = $auditApi->getLogsByDateRange(
 *     '2024-01-01T00:00:00Z',
 *     '2024-01-31T23:59:59Z'
 * );
 * echo "Operations in January 2024: {$logs['meta']['total']}\n";
 */

/*
 * Example 7: Today's Activity Summary
 * ===================================
 *
 * // Get today's stats
 * $stats = $auditApi->getStats();
 * echo "Activity Summary:\n";
 * echo "  Total entries: {$stats['data']['total']}\n";
 * echo "  Today's entries: {$stats['data']['today']}\n\n";
 *
 * // Get today's logs
 * $todayLogs = $auditApi->getTodaysLogs();
 *
 * // Count by action type
 * $actionCounts = [];
 * foreach ($todayLogs['data'] as $log) {
 *     $action = $log['action'];
 *     $actionCounts[$action] = ($actionCounts[$action] ?? 0) + 1;
 * }
 *
 * echo "Today's activity by action:\n";
 * foreach ($actionCounts as $action => $count) {
 *     echo "  {$action}: {$count}\n";
 * }
 */

/*
 * Example 8: Tracking Changes to a Specific Resource
 * ===================================================
 *
 * // Get all changes to a specific DNS record
 * $recordName = 'example.com';
 * $history = $auditApi->getLogsForResource($recordName, AuditAPI::RESOURCE_DNS_RECORD);
 *
 * echo "History for DNS record '{$recordName}':\n";
 * foreach ($history as $log) {
 *     $action = ucfirst($log['action']);
 *     $user = $log['user'] ? $log['user']['email'] : 'Unknown';
 *     echo "  [{$log['inserted_at']}] {$action} by {$user}\n";
 * }
 */

/*
 * Example 9: Exporting Audit Logs
 * ===============================
 *
 * // Export all DNS changes to a JSON file
 * echo "Exporting audit logs...\n";
 *
 * $dnsLogs = $auditApi->exportAllLogs(
 *     ['resource_type' => AuditAPI::RESOURCE_DNS_RECORD],
 *     function($page, $total) {
 *         echo "  Fetching page {$page} of {$total}...\n";
 *     }
 * );
 *
 * $filename = 'dns_audit_' . date('Y-m-d_His') . '.json';
 * file_put_contents($filename, json_encode($dnsLogs, JSON_PRETTY_PRINT));
 * echo "Exported " . count($dnsLogs) . " entries to {$filename}\n";
 */

/*
 * Example 10: Building an Audit Dashboard
 * ========================================
 *
 * // Function to generate an audit summary report
 * function generateAuditReport(AuditAPI $api): array {
 *     // Get statistics
 *     $stats = $api->getStats()['data'];
 *
 *     // Get today's logs
 *     $todayLogs = $api->getTodaysLogs(['per_page' => 100])['data'];
 *
 *     // Get recent failures
 *     $failures = $api->getFailedOperations(['per_page' => 10])['data'];
 *
 *     // Calculate activity breakdown
 *     $byAction = [];
 *     $byResource = [];
 *     $byUser = [];
 *
 *     foreach ($todayLogs as $log) {
 *         $byAction[$log['action']] = ($byAction[$log['action']] ?? 0) + 1;
 *         $byResource[$log['resource_type']] = ($byResource[$log['resource_type']] ?? 0) + 1;
 *
 *         $userEmail = $log['user']['email'] ?? 'System';
 *         $byUser[$userEmail] = ($byUser[$userEmail] ?? 0) + 1;
 *     }
 *
 *     return [
 *         'total_entries' => $stats['total'],
 *         'today_entries' => $stats['today'],
 *         'today_by_action' => $byAction,
 *         'today_by_resource' => $byResource,
 *         'today_by_user' => $byUser,
 *         'recent_failures' => $failures,
 *     ];
 * }
 *
 * // Generate and display report
 * $report = generateAuditReport($auditApi);
 *
 * echo "=== AUDIT DASHBOARD ===\n\n";
 *
 * echo "Total Entries: {$report['total_entries']}\n";
 * echo "Today's Entries: {$report['today_entries']}\n\n";
 *
 * echo "Today's Activity by Action:\n";
 * foreach ($report['today_by_action'] as $action => $count) {
 *     echo "  {$action}: {$count}\n";
 * }
 *
 * echo "\nToday's Activity by Resource:\n";
 * foreach ($report['today_by_resource'] as $resource => $count) {
 *     echo "  {$resource}: {$count}\n";
 * }
 *
 * echo "\nToday's Activity by User:\n";
 * foreach ($report['today_by_user'] as $user => $count) {
 *     echo "  {$user}: {$count}\n";
 * }
 *
 * if (count($report['recent_failures']) > 0) {
 *     echo "\n!!! Recent Failures !!!\n";
 *     foreach ($report['recent_failures'] as $failure) {
 *         echo "  [{$failure['inserted_at']}] {$failure['action']} {$failure['resource_type']}\n";
 *     }
 * }
 */

/*
 * Example 11: Pagination
 * ======================
 *
 * // Iterate through all pages of audit logs
 * $page = 1;
 * $totalProcessed = 0;
 *
 * do {
 *     $response = $auditApi->listLogs([
 *         'page' => $page,
 *         'per_page' => 50
 *     ]);
 *
 *     echo "Processing page {$page} of {$response['meta']['total_pages']}...\n";
 *
 *     foreach ($response['data'] as $log) {
 *         // Process each log entry
 *         $totalProcessed++;
 *     }
 *
 *     $page++;
 * } while ($page <= $response['meta']['total_pages']);
 *
 * echo "Processed {$totalProcessed} total entries\n";
 */

/*
 * Example 12: Error Handling
 * ==========================
 *
 * try {
 *     // Attempt to get a specific log
 *     $log = $auditApi->getLog(99999999);
 *     print_r($log);
 * } catch (RouterOSClientException $e) {
 *     if ($e->getCode() === 404) {
 *         echo "Audit log not found\n";
 *     } elseif ($e->getCode() === 401) {
 *         echo "Authentication failed - check your API token\n";
 *     } elseif ($e->getCode() === 403) {
 *         echo "Access denied - token needs 'audit:read' scope\n";
 *     } else {
 *         echo "API error: {$e->getMessage()}\n";
 *     }
 * }
 */
