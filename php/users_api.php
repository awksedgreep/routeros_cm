<?php
/**
 * RouterOS Cluster Manager - RouterOS User Management API
 *
 * This file provides functions for managing RouterOS system users across the cluster.
 * These are the users that can log into the RouterOS devices directly (via Winbox,
 * SSH, API, etc.), NOT the web application users.
 *
 * @package RouterOSCM
 * @version 1.0.0
 *
 * REQUIRED SCOPES:
 * ================
 * - users:read  - Required for listing users, groups, and active sessions
 * - users:write - Required for creating, updating, and deleting users
 *
 * SECURITY CONSIDERATIONS:
 * ========================
 * - Users created through this API have direct access to RouterOS devices
 * - Always use strong passwords
 * - Use the principle of least privilege - assign appropriate groups
 * - Audit user changes regularly
 *
 * USER GROUPS:
 * ============
 * RouterOS has predefined user groups:
 * - full: Full administrative access
 * - write: Can make configuration changes
 * - read: Read-only access
 * - (custom groups may also exist)
 *
 * USAGE:
 * ======
 * ```php
 * require_once 'RouterOSClient.php';
 * require_once 'users_api.php';
 *
 * $client = new RouterOSClient('https://your-server.com', 'your-token');
 * $usersApi = new RouterOSUsersApi($client);
 *
 * // Create a new RouterOS user
 * $result = $usersApi->createUser('monitor', 'SecurePass123!', 'read');
 * ```
 */

require_once __DIR__ . '/RouterOSClient.php';

/**
 * RouterOS User Management API
 *
 * Provides methods for:
 * - Creating, updating, and deleting RouterOS users
 * - Listing users across the cluster
 * - Viewing user groups
 * - Monitoring active sessions
 */
class RouterOSUsersApi
{
    /** @var RouterOSClient API client instance */
    private RouterOSClient $client;

    /**
     * Create a new RouterOSUsersApi instance
     *
     * @param RouterOSClient $client Configured API client
     */
    public function __construct(RouterOSClient $client)
    {
        $this->client = $client;
    }

    // =========================================================================
    // USER MANAGEMENT
    // =========================================================================

    /**
     * List all RouterOS users across the cluster
     *
     * Returns users from all active nodes, grouped by username.
     * Shows which nodes have each user configured.
     *
     * @return array List of users
     * @throws RouterOSApiException On API errors
     *
     * Required scope: users:read
     *
     * @example
     * ```php
     * $users = $usersApi->listUsers();
     *
     * foreach ($users['data'] as $user) {
     *     echo sprintf(
     *         "User: %s (Group: %s) - on %d nodes\n",
     *         $user['name'],
     *         $user['group'],
     *         count($user['nodes'])
     *     );
     *
     *     // Show per-node details
     *     foreach ($user['nodes'] as $nodeInfo) {
     *         $status = $nodeInfo['disabled'] ? 'DISABLED' : 'active';
     *         echo "  - {$nodeInfo['node_name']}: $status, last login: {$nodeInfo['last_logged_in']}\n";
     *     }
     * }
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": [
     *         {
     *             "name": "admin",
     *             "group": "full",
     *             "comment": "System administrator",
     *             "nodes": [
     *                 {
     *                     "node_name": "router1",
     *                     "node_id": 1,
     *                     "user_id": "*1",
     *                     "last_logged_in": "2024-01-15T10:30:00Z",
     *                     "disabled": false
     *                 }
     *             ]
     *         }
     *     ]
     * }
     * ```
     */
    public function listUsers(): array
    {
        return $this->client->get('/api/v1/routeros-users');
    }

    /**
     * Get a specific RouterOS user by name
     *
     * @param string $name Username
     * @return array User details
     * @throws RouterOSApiException On API errors (404 if not found)
     *
     * Required scope: users:read
     *
     * @example
     * ```php
     * $user = $usersApi->getUser('admin');
     *
     * echo "Username: " . $user['data']['name'] . "\n";
     * echo "Group: " . $user['data']['group'] . "\n";
     * echo "Comment: " . ($user['data']['comment'] ?? 'none') . "\n";
     * echo "Present on " . count($user['data']['nodes']) . " nodes\n";
     * ```
     */
    public function getUser(string $name): array
    {
        return $this->client->get("/api/v1/routeros-users/" . urlencode($name));
    }

    /**
     * Create a new RouterOS user
     *
     * Creates a user on all active nodes in the cluster.
     *
     * WARNING: This user will have direct access to RouterOS devices!
     * Use strong passwords and appropriate group permissions.
     *
     * @param string $name Username (alphanumeric, dashes, underscores)
     * @param string $password User password (use a strong password!)
     * @param string $group User group ('full', 'write', 'read', or custom)
     * @param string|null $comment Optional description/comment
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: users:write
     *
     * @example
     * ```php
     * // Create an admin user
     * $result = $usersApi->createUser(
     *     'new-admin',
     *     'VerySecurePassword123!',
     *     'full',
     *     'Secondary administrator'
     * );
     *
     * // Create a monitoring user (read-only)
     * $result = $usersApi->createUser(
     *     'monitor',
     *     'MonitorPass456!',
     *     'read',
     *     'Monitoring system user'
     * );
     *
     * // Create a user for automation (write access)
     * $result = $usersApi->createUser(
     *     'automation',
     *     'AutomationKey789!',
     *     'write',
     *     'Automation scripts'
     * );
     *
     * echo "Created on " . count($result['data']['successes']) . " nodes\n";
     *
     * if (!empty($result['data']['failures'])) {
     *     echo "Failed on " . count($result['data']['failures']) . " nodes:\n";
     *     foreach ($result['data']['failures'] as $failure) {
     *         echo "  - {$failure['node']}: {$failure['error']}\n";
     *     }
     * }
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": {
     *         "operation": "create",
     *         "resource": "routeros_user",
     *         "successes": [
     *             {"node": "router1", "node_id": 1}
     *         ],
     *         "failures": []
     *     }
     * }
     * ```
     */
    public function createUser(
        string $name,
        string $password,
        string $group = 'full',
        ?string $comment = null
    ): array {
        $data = [
            'name' => $name,
            'password' => $password,
            'group' => $group
        ];

        if ($comment !== null) {
            $data['comment'] = $comment;
        }

        return $this->client->post('/api/v1/routeros-users', $data);
    }

    /**
     * Update an existing RouterOS user
     *
     * Updates user properties on all nodes where the user exists.
     *
     * @param string $name Username to update
     * @param array $data Fields to update:
     *                    - password: string - New password
     *                    - group: string - New group
     *                    - comment: string - New comment
     *                    - disabled: bool - Enable/disable user
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: users:write
     *
     * @example
     * ```php
     * // Change password
     * $result = $usersApi->updateUser('monitor', [
     *     'password' => 'NewSecurePassword123!'
     * ]);
     *
     * // Change group
     * $result = $usersApi->updateUser('automation', [
     *     'group' => 'full'  // Promote to full access
     * ]);
     *
     * // Disable a user (without deleting)
     * $result = $usersApi->updateUser('old-admin', [
     *     'disabled' => true
     * ]);
     *
     * // Update multiple fields
     * $result = $usersApi->updateUser('monitor', [
     *     'group' => 'write',
     *     'comment' => 'Upgraded to write access'
     * ]);
     *
     * echo "Updated on " . count($result['data']['successes']) . " nodes\n";
     * ```
     */
    public function updateUser(string $name, array $data): array
    {
        return $this->client->put("/api/v1/routeros-users/" . urlencode($name), $data);
    }

    /**
     * Delete a RouterOS user
     *
     * Removes the user from all nodes where it exists.
     *
     * WARNING: This permanently removes the user's access to all RouterOS devices!
     *
     * @param string $name Username to delete
     * @return array Operation result
     * @throws RouterOSApiException On API errors
     *
     * Required scope: users:write
     *
     * @example
     * ```php
     * // Delete a user
     * $result = $usersApi->deleteUser('old-employee');
     *
     * echo "Deleted from " . count($result['data']['successes']) . " nodes\n";
     *
     * // With error handling
     * try {
     *     $usersApi->deleteUser('admin');
     * } catch (RouterOSApiException $e) {
     *     // Can't delete the default admin user on some systems
     *     echo "Failed: " . $e->getMessage() . "\n";
     * }
     * ```
     */
    public function deleteUser(string $name): array
    {
        return $this->client->delete("/api/v1/routeros-users/" . urlencode($name));
    }

    // =========================================================================
    // USER GROUPS
    // =========================================================================

    /**
     * List available user groups
     *
     * Returns the user groups available on each node.
     * Groups define what permissions users have.
     *
     * @return array List of groups per node
     * @throws RouterOSApiException On API errors
     *
     * Required scope: users:read
     *
     * @example
     * ```php
     * $groups = $usersApi->listGroups();
     *
     * foreach ($groups['data'] as $nodeGroups) {
     *     echo "Node {$nodeGroups['node_name']}:\n";
     *     foreach ($nodeGroups['groups'] as $group) {
     *         echo "  - {$group['name']}: {$group['policy']}\n";
     *     }
     * }
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": [
     *         {
     *             "node_name": "router1",
     *             "node_id": 1,
     *             "groups": [
     *                 {"name": "full", "policy": "local,telnet,ssh,ftp,..."},
     *                 {"name": "read", "policy": "local,telnet,ssh,..."},
     *                 {"name": "write", "policy": "local,telnet,ssh,..."}
     *             ]
     *         }
     *     ]
     * }
     * ```
     */
    public function listGroups(): array
    {
        return $this->client->get('/api/v1/routeros-users/groups');
    }

    // =========================================================================
    // ACTIVE SESSIONS
    // =========================================================================

    /**
     * List active user sessions
     *
     * Returns currently logged-in users across all nodes.
     * Shows who is connected and how (Winbox, SSH, API, etc.).
     *
     * @return array List of active sessions
     * @throws RouterOSApiException On API errors
     *
     * Required scope: users:read
     *
     * @example
     * ```php
     * $sessions = $usersApi->listActiveSessions();
     *
     * foreach ($sessions['data'] as $nodeSession) {
     *     echo "Node {$nodeSession['node_name']}:\n";
     *
     *     if (empty($nodeSession['sessions'])) {
     *         echo "  No active sessions\n";
     *         continue;
     *     }
     *
     *     foreach ($nodeSession['sessions'] as $session) {
     *         echo sprintf(
     *             "  - %s via %s from %s (since %s)\n",
     *             $session['name'],
     *             $session['via'],
     *             $session['address'] ?? 'local',
     *             $session['when']
     *         );
     *     }
     * }
     * ```
     *
     * Response structure:
     * ```json
     * {
     *     "data": [
     *         {
     *             "node_name": "router1",
     *             "node_id": 1,
     *             "sessions": [
     *                 {
     *                     "name": "admin",
     *                     "address": "192.168.1.100",
     *                     "via": "winbox",
     *                     "when": "jan/15/2024 10:30:00"
     *                 }
     *             ]
     *         }
     *     ]
     * }
     * ```
     */
    public function listActiveSessions(): array
    {
        return $this->client->get('/api/v1/routeros-users/active');
    }

    // =========================================================================
    // UTILITY METHODS
    // =========================================================================

    /**
     * Check if a user exists
     *
     * @param string $name Username to check
     * @return bool True if user exists on at least one node
     *
     * @example
     * ```php
     * if ($usersApi->userExists('admin')) {
     *     echo "User admin exists\n";
     * }
     * ```
     */
    public function userExists(string $name): bool
    {
        try {
            $this->getUser($name);
            return true;
        } catch (RouterOSApiException $e) {
            if ($e->getHttpStatus() === 404) {
                return false;
            }
            throw $e;
        }
    }

    /**
     * Change a user's password
     *
     * Convenience method for updating only the password.
     *
     * @param string $name Username
     * @param string $newPassword New password
     * @return array Operation result
     *
     * @example
     * ```php
     * $result = $usersApi->changePassword('admin', 'NewSecurePassword123!');
     * ```
     */
    public function changePassword(string $name, string $newPassword): array
    {
        return $this->updateUser($name, ['password' => $newPassword]);
    }

    /**
     * Disable a user
     *
     * Disables the user without deleting them.
     * They can be re-enabled later.
     *
     * @param string $name Username to disable
     * @return array Operation result
     *
     * @example
     * ```php
     * // Disable a user (they can no longer log in)
     * $result = $usersApi->disableUser('temporary-user');
     * ```
     */
    public function disableUser(string $name): array
    {
        return $this->updateUser($name, ['disabled' => true]);
    }

    /**
     * Enable a user
     *
     * Re-enables a previously disabled user.
     *
     * @param string $name Username to enable
     * @return array Operation result
     *
     * @example
     * ```php
     * // Re-enable a disabled user
     * $result = $usersApi->enableUser('temporary-user');
     * ```
     */
    public function enableUser(string $name): array
    {
        return $this->updateUser($name, ['disabled' => false]);
    }

    /**
     * Get users by group
     *
     * Returns all users that belong to a specific group.
     *
     * @param string $group Group name ('full', 'write', 'read', etc.)
     * @return array List of users in the group
     *
     * @example
     * ```php
     * // Get all full-access users
     * $fullAccessUsers = $usersApi->getUsersByGroup('full');
     *
     * echo "Users with full access:\n";
     * foreach ($fullAccessUsers as $user) {
     *     echo "  - " . $user['name'] . "\n";
     * }
     *
     * // Get all read-only users
     * $readOnlyUsers = $usersApi->getUsersByGroup('read');
     * ```
     */
    public function getUsersByGroup(string $group): array
    {
        $users = $this->listUsers();

        return array_filter($users['data'], function ($user) use ($group) {
            return $user['group'] === $group;
        });
    }

    /**
     * Get currently active users (unique)
     *
     * Returns a list of unique usernames that are currently logged in.
     *
     * @return array List of active usernames
     *
     * @example
     * ```php
     * $activeUsers = $usersApi->getActiveUsernames();
     *
     * echo "Currently logged in users: " . implode(', ', $activeUsers) . "\n";
     * ```
     */
    public function getActiveUsernames(): array
    {
        $sessions = $this->listActiveSessions();
        $usernames = [];

        foreach ($sessions['data'] as $nodeSession) {
            if (!empty($nodeSession['sessions'])) {
                foreach ($nodeSession['sessions'] as $session) {
                    $usernames[] = $session['name'];
                }
            }
        }

        return array_unique($usernames);
    }

    /**
     * Generate a secure random password
     *
     * Generates a cryptographically secure random password.
     *
     * @param int $length Password length (minimum 12)
     * @param bool $includeSpecial Include special characters
     * @return string Generated password
     *
     * @example
     * ```php
     * // Generate a 16-character password
     * $password = $usersApi->generatePassword(16);
     *
     * // Create user with generated password
     * $result = $usersApi->createUser('new-user', $password, 'read');
     *
     * echo "Created user with password: $password\n";
     * // Store this password securely!
     * ```
     */
    public function generatePassword(int $length = 16, bool $includeSpecial = true): string
    {
        $length = max(12, $length); // Minimum 12 characters

        $lowercase = 'abcdefghijklmnopqrstuvwxyz';
        $uppercase = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
        $numbers = '0123456789';
        $special = '!@#$%^&*()_+-=[]{}|;:,.<>?';

        $chars = $lowercase . $uppercase . $numbers;
        if ($includeSpecial) {
            $chars .= $special;
        }

        $password = '';
        $charsLength = strlen($chars);

        // Ensure at least one of each type
        $password .= $lowercase[random_int(0, strlen($lowercase) - 1)];
        $password .= $uppercase[random_int(0, strlen($uppercase) - 1)];
        $password .= $numbers[random_int(0, strlen($numbers) - 1)];
        if ($includeSpecial) {
            $password .= $special[random_int(0, strlen($special) - 1)];
        }

        // Fill the rest
        for ($i = strlen($password); $i < $length; $i++) {
            $password .= $chars[random_int(0, $charsLength - 1)];
        }

        // Shuffle the password
        return str_shuffle($password);
    }
}

// =============================================================================
// STANDALONE USAGE EXAMPLE
// =============================================================================
/*
// Example: Complete RouterOS user management workflow

require_once 'RouterOSClient.php';
require_once 'users_api.php';

// Initialize client
$client = new RouterOSClient('https://routeros-cm.example.com', 'your-api-token');
$usersApi = new RouterOSUsersApi($client);

try {
    // 1. List current users
    echo "Current RouterOS users:\n";
    $users = $usersApi->listUsers();
    foreach ($users['data'] as $user) {
        $status = $user['nodes'][0]['disabled'] ? 'DISABLED' : 'active';
        echo "  {$user['name']} ({$user['group']}) - $status\n";
    }

    // 2. Check available groups
    echo "\nAvailable groups:\n";
    $groups = $usersApi->listGroups();
    foreach ($groups['data'][0]['groups'] as $group) {
        echo "  - {$group['name']}\n";
    }

    // 3. Create a monitoring user
    echo "\nCreating monitoring user...\n";
    $password = $usersApi->generatePassword(16);
    $result = $usersApi->createUser(
        'monitor-user',
        $password,
        'read',
        'Automated monitoring'
    );
    echo "Created on " . count($result['data']['successes']) . " nodes\n";
    echo "Password: $password (store this securely!)\n";

    // 4. Create an automation user
    echo "\nCreating automation user...\n";
    $autoPassword = $usersApi->generatePassword(20);
    $result = $usersApi->createUser(
        'automation',
        $autoPassword,
        'write',
        'Automation scripts'
    );
    echo "Created on " . count($result['data']['successes']) . " nodes\n";

    // 5. Check active sessions
    echo "\nActive sessions:\n";
    $sessions = $usersApi->listActiveSessions();
    foreach ($sessions['data'] as $nodeSession) {
        echo "  {$nodeSession['node_name']}:\n";
        if (empty($nodeSession['sessions'])) {
            echo "    No active sessions\n";
        } else {
            foreach ($nodeSession['sessions'] as $session) {
                echo "    - {$session['name']} via {$session['via']}\n";
            }
        }
    }

    // 6. Get all admin users
    echo "\nFull access users:\n";
    $admins = $usersApi->getUsersByGroup('full');
    foreach ($admins as $admin) {
        echo "  - {$admin['name']}\n";
    }

    // 7. Disable a user (example)
    // $usersApi->disableUser('old-employee');

    // 8. Delete a user (example)
    // $usersApi->deleteUser('temp-user');

} catch (RouterOSApiException $e) {
    echo "API Error: " . $e->getMessage() . "\n";
    echo "HTTP Status: " . $e->getHttpStatus() . "\n";
}
*/
