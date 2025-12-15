<?php
/**
 * RouterOS Cluster Manager - Base API Client
 *
 * This is the base client class for interacting with the RouterOS Cluster Manager API.
 * All other API classes extend this base class.
 *
 * @package RouterOSCM
 * @version 1.0.0
 * @author RouterOS Cluster Manager
 *
 * INSTALLATION:
 * =============
 * 1. Copy all PHP files to your project directory
 * 2. Include the files you need:
 *    require_once 'RouterOSClient.php';
 *    require_once 'cluster_api.php';
 *
 * REQUIREMENTS:
 * =============
 * - PHP 7.4 or higher
 * - cURL extension enabled
 * - JSON extension enabled
 *
 * AUTHENTICATION:
 * ===============
 * The API uses Bearer token authentication. You must first create an API token
 * through the web interface, then use that token in your API calls.
 *
 * Tokens have scopes that limit what operations they can perform:
 * - nodes:read, nodes:write     - Cluster and node management
 * - dns:read, dns:write         - DNS record management
 * - tunnels:read, tunnels:write - GRE tunnel management
 * - wireguard:read, wireguard:write - WireGuard management
 * - users:read, users:write     - RouterOS user management
 * - audit:read                  - Audit log access
 *
 * BASIC USAGE:
 * ============
 * ```php
 * require_once 'RouterOSClient.php';
 *
 * $client = new RouterOSClient('https://your-server.com', 'your-api-token');
 *
 * // Make a GET request
 * $response = $client->get('/api/v1/nodes');
 *
 * // Make a POST request
 * $response = $client->post('/api/v1/dns/records', [
 *     'name' => 'test.local',
 *     'address' => '192.168.1.100'
 * ]);
 * ```
 *
 * ERROR HANDLING:
 * ===============
 * All API errors throw RouterOSApiException with detailed error information.
 *
 * ```php
 * try {
 *     $response = $client->get('/api/v1/nodes/999');
 * } catch (RouterOSApiException $e) {
 *     echo "Error: " . $e->getMessage();
 *     echo "HTTP Status: " . $e->getHttpStatus();
 *     echo "Error Code: " . $e->getErrorCode();
 * }
 * ```
 */

/**
 * Custom exception for API errors
 */
class RouterOSApiException extends Exception
{
    /** @var int HTTP status code */
    private int $httpStatus;

    /** @var string|null API error code */
    private ?string $errorCode;

    /** @var array|null Additional error details */
    private ?array $details;

    /**
     * Create a new API exception
     *
     * @param string $message Error message
     * @param int $httpStatus HTTP status code
     * @param string|null $errorCode API error code
     * @param array|null $details Additional error details
     */
    public function __construct(
        string $message,
        int $httpStatus = 0,
        ?string $errorCode = null,
        ?array $details = null
    ) {
        parent::__construct($message, $httpStatus);
        $this->httpStatus = $httpStatus;
        $this->errorCode = $errorCode;
        $this->details = $details;
    }

    /**
     * Get the HTTP status code
     * @return int
     */
    public function getHttpStatus(): int
    {
        return $this->httpStatus;
    }

    /**
     * Get the API error code
     * @return string|null
     */
    public function getErrorCode(): ?string
    {
        return $this->errorCode;
    }

    /**
     * Get additional error details
     * @return array|null
     */
    public function getDetails(): ?array
    {
        return $this->details;
    }
}

/**
 * Base API client for RouterOS Cluster Manager
 */
class RouterOSClient
{
    /** @var string Base URL of the API server */
    protected string $baseUrl;

    /** @var string API authentication token */
    protected string $token;

    /** @var int Request timeout in seconds */
    protected int $timeout = 30;

    /** @var bool Whether to verify SSL certificates */
    protected bool $verifySsl = true;

    /** @var array Default headers for all requests */
    protected array $defaultHeaders = [];

    /**
     * Create a new API client instance
     *
     * @param string $baseUrl Base URL of the RouterOS CM server (e.g., 'https://routeros-cm.example.com')
     * @param string $token API authentication token
     *
     * @example
     * ```php
     * // Basic initialization
     * $client = new RouterOSClient('https://routeros-cm.local', 'your-api-token-here');
     *
     * // With custom options
     * $client = new RouterOSClient('https://routeros-cm.local', 'your-token');
     * $client->setTimeout(60);           // 60 second timeout
     * $client->setVerifySsl(false);      // Disable SSL verification (not recommended for production)
     * ```
     */
    public function __construct(string $baseUrl, string $token)
    {
        // Remove trailing slash from base URL
        $this->baseUrl = rtrim($baseUrl, '/');
        $this->token = $token;

        $this->defaultHeaders = [
            'Accept: application/json',
            'Content-Type: application/json',
            'Authorization: Bearer ' . $this->token
        ];
    }

    /**
     * Set the request timeout
     *
     * @param int $seconds Timeout in seconds
     * @return self
     */
    public function setTimeout(int $seconds): self
    {
        $this->timeout = $seconds;
        return $this;
    }

    /**
     * Set whether to verify SSL certificates
     *
     * WARNING: Disabling SSL verification is insecure and should only be used
     * in development environments with self-signed certificates.
     *
     * @param bool $verify Whether to verify SSL certificates
     * @return self
     */
    public function setVerifySsl(bool $verify): self
    {
        $this->verifySsl = $verify;
        return $this;
    }

    /**
     * Make a GET request to the API
     *
     * @param string $endpoint API endpoint (e.g., '/api/v1/nodes')
     * @param array $queryParams Optional query parameters
     * @return array Decoded JSON response
     * @throws RouterOSApiException On API errors
     *
     * @example
     * ```php
     * // Simple GET request
     * $nodes = $client->get('/api/v1/nodes');
     *
     * // GET with query parameters
     * $logs = $client->get('/api/v1/audit', [
     *     'page' => 1,
     *     'per_page' => 50,
     *     'action' => 'create'
     * ]);
     * ```
     */
    public function get(string $endpoint, array $queryParams = []): array
    {
        $url = $this->baseUrl . $endpoint;

        if (!empty($queryParams)) {
            $url .= '?' . http_build_query($queryParams);
        }

        return $this->request('GET', $url);
    }

    /**
     * Make a POST request to the API
     *
     * @param string $endpoint API endpoint
     * @param array $data Request body data
     * @return array Decoded JSON response
     * @throws RouterOSApiException On API errors
     *
     * @example
     * ```php
     * // Create a new DNS record
     * $result = $client->post('/api/v1/dns/records', [
     *     'name' => 'app.local',
     *     'address' => '192.168.1.100',
     *     'ttl' => '1d'
     * ]);
     * ```
     */
    public function post(string $endpoint, array $data = []): array
    {
        $url = $this->baseUrl . $endpoint;
        return $this->request('POST', $url, $data);
    }

    /**
     * Make a PUT request to the API
     *
     * @param string $endpoint API endpoint
     * @param array $data Request body data
     * @return array Decoded JSON response
     * @throws RouterOSApiException On API errors
     *
     * @example
     * ```php
     * // Update a node
     * $result = $client->put('/api/v1/nodes/1', [
     *     'name' => 'router1-updated',
     *     'username' => 'admin',
     *     'password' => 'newpassword'
     * ]);
     * ```
     */
    public function put(string $endpoint, array $data = []): array
    {
        $url = $this->baseUrl . $endpoint;
        return $this->request('PUT', $url, $data);
    }

    /**
     * Make a PATCH request to the API
     *
     * @param string $endpoint API endpoint
     * @param array $data Request body data
     * @return array Decoded JSON response
     * @throws RouterOSApiException On API errors
     */
    public function patch(string $endpoint, array $data = []): array
    {
        $url = $this->baseUrl . $endpoint;
        return $this->request('PATCH', $url, $data);
    }

    /**
     * Make a DELETE request to the API
     *
     * @param string $endpoint API endpoint
     * @return array|null Decoded JSON response (may be empty for 204 responses)
     * @throws RouterOSApiException On API errors
     *
     * @example
     * ```php
     * // Delete a DNS record
     * $client->delete('/api/v1/dns/records/test.local');
     * ```
     */
    public function delete(string $endpoint): ?array
    {
        $url = $this->baseUrl . $endpoint;
        return $this->request('DELETE', $url);
    }

    /**
     * Make an HTTP request to the API
     *
     * @param string $method HTTP method (GET, POST, PUT, PATCH, DELETE)
     * @param string $url Full URL to request
     * @param array|null $data Request body data (for POST, PUT, PATCH)
     * @return array|null Decoded JSON response
     * @throws RouterOSApiException On API errors or network failures
     */
    protected function request(string $method, string $url, ?array $data = null): ?array
    {
        $ch = curl_init();

        $options = [
            CURLOPT_URL => $url,
            CURLOPT_RETURNTRANSFER => true,
            CURLOPT_TIMEOUT => $this->timeout,
            CURLOPT_HTTPHEADER => $this->defaultHeaders,
            CURLOPT_SSL_VERIFYPEER => $this->verifySsl,
            CURLOPT_SSL_VERIFYHOST => $this->verifySsl ? 2 : 0,
        ];

        switch ($method) {
            case 'POST':
                $options[CURLOPT_POST] = true;
                if ($data !== null) {
                    $options[CURLOPT_POSTFIELDS] = json_encode($data);
                }
                break;

            case 'PUT':
                $options[CURLOPT_CUSTOMREQUEST] = 'PUT';
                if ($data !== null) {
                    $options[CURLOPT_POSTFIELDS] = json_encode($data);
                }
                break;

            case 'PATCH':
                $options[CURLOPT_CUSTOMREQUEST] = 'PATCH';
                if ($data !== null) {
                    $options[CURLOPT_POSTFIELDS] = json_encode($data);
                }
                break;

            case 'DELETE':
                $options[CURLOPT_CUSTOMREQUEST] = 'DELETE';
                break;
        }

        curl_setopt_array($ch, $options);

        $response = curl_exec($ch);
        $httpStatus = curl_getinfo($ch, CURLINFO_HTTP_CODE);
        $error = curl_error($ch);

        curl_close($ch);

        // Handle cURL errors
        if ($response === false) {
            throw new RouterOSApiException(
                "Network error: " . $error,
                0,
                'network_error'
            );
        }

        // Handle 204 No Content responses
        if ($httpStatus === 204) {
            return null;
        }

        // Decode JSON response
        $decoded = json_decode($response, true);

        if (json_last_error() !== JSON_ERROR_NONE) {
            throw new RouterOSApiException(
                "Invalid JSON response: " . json_last_error_msg(),
                $httpStatus,
                'json_error'
            );
        }

        // Handle API errors
        if ($httpStatus >= 400) {
            $errorMessage = $decoded['error']['message'] ?? 'Unknown error';
            $errorCode = $decoded['error']['code'] ?? 'unknown';
            $errorDetails = $decoded['error']['details'] ?? null;

            throw new RouterOSApiException(
                $errorMessage,
                $httpStatus,
                $errorCode,
                $errorDetails
            );
        }

        return $decoded;
    }

    /**
     * Get the base URL
     * @return string
     */
    public function getBaseUrl(): string
    {
        return $this->baseUrl;
    }

    /**
     * Test the API connection
     *
     * Makes a simple request to verify the connection and authentication are working.
     *
     * @return bool True if connection is successful
     * @throws RouterOSApiException On connection or auth failure
     *
     * @example
     * ```php
     * if ($client->testConnection()) {
     *     echo "Connection successful!";
     * }
     * ```
     */
    public function testConnection(): bool
    {
        // Try to get cluster stats - requires minimal permissions
        $this->get('/api/v1/cluster/stats');
        return true;
    }
}
