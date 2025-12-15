# REST API Implementation Plan

## Overview

This document outlines a phased approach to implementing a comprehensive REST API for the RouterOS Cluster Manager. The API will enable programmatic access to all network service provisioning features, making this application suitable as a microservice for network automation.

**Current State**: The application has well-structured context modules (`Cluster`, `DNS`, `Tunnels`, `RouterOSUsers`, `Audit`) that encapsulate all business logic. The API implementation primarily requires adding controllers, JSON views, and authentication mechanisms.

---

## Implementation Status

| Phase | Description | Status | Last Updated |
|-------|-------------|--------|--------------|
| 1 | API Foundation | **COMPLETE** | 2024-12-14 |
| 2 | Cluster & Node Management | **COMPLETE** | 2024-12-14 |
| 3 | DNS Management | **COMPLETE** | 2024-12-14 |
| 4 | GRE Tunnel API | **COMPLETE** | 2024-12-14 |
| 5 | WireGuard API | **COMPLETE** | 2024-12-14 |
| 6 | RouterOS Users API | **COMPLETE** | 2024-12-14 |
| 7 | Audit Log API | **COMPLETE** | 2024-12-14 |
| 8 | Documentation & Testing | **COMPLETE** | 2024-12-14 |

### Phase 1 Completed Files

- [x] `priv/repo/migrations/20251214205218_create_api_tokens.exs` - Migration for API tokens table
- [x] `lib/routeros_cm/accounts/api_token.ex` - API token Ecto schema with scopes
- [x] `lib/routeros_cm/api_auth.ex` - Token generation, verification, and management
- [x] `lib/routeros_cm/accounts/scope.ex` - Updated with api_token field
- [x] `lib/routeros_cm_web/plugs/api_auth.ex` - Bearer token authentication plug
- [x] `lib/routeros_cm_web/router.ex` - Added API v1 routes with all endpoints defined
- [x] `lib/routeros_cm_web/controllers/error_json.ex` - Enhanced error responses
- [x] `lib/routeros_cm_web/controllers/api/v1/base.ex` - Base controller with helpers

### Phase 2 Completed Files

- [x] `lib/routeros_cm_web/controllers/api/v1/node_controller.ex` - Full CRUD + connection test
- [x] `lib/routeros_cm_web/controllers/api/v1/cluster_controller.ex` - Health and stats endpoints
- [x] `test/support/fixtures/cluster_fixtures.ex` - Test fixtures for nodes
- [x] `test/routeros_cm_web/controllers/api/v1/node_controller_test.exs` - 11 tests
- [x] `test/routeros_cm_web/controllers/api/v1/cluster_controller_test.exs` - 4 tests

### Phase 3 Completed Files

- [x] `lib/routeros_cm_web/controllers/api/v1/dns_controller.ex` - Full CRUD + settings + cache flush
- [x] `test/routeros_cm_web/controllers/api/v1/dns_controller_test.exs` - 11 tests

### Phase 4 Completed Files

- [x] `lib/routeros_cm_web/controllers/api/v1/gre_controller.ex` - Full CRUD + IP assignment
- [x] `test/routeros_cm_web/controllers/api/v1/gre_controller_test.exs` - 10 tests

### Phase 5 Completed Files

- [x] `lib/routeros_cm_web/controllers/api/v1/wireguard_controller.ex` - Full CRUD + peers + keypair generation
- [x] `test/routeros_cm_web/controllers/api/v1/wireguard_controller_test.exs` - 15 tests

### Phase 6 Completed Files

- [x] `lib/routeros_cm_web/controllers/api/v1/routeros_user_controller.ex` - Full CRUD + groups + active sessions
- [x] `test/routeros_cm_web/controllers/api/v1/routeros_user_controller_test.exs` - 12 tests

### Phase 7 Completed Files

- [x] `lib/routeros_cm_web/controllers/api/v1/audit_controller.ex` - List, show, stats with filtering
- [x] `test/routeros_cm_web/controllers/api/v1/audit_controller_test.exs` - 10 tests

### Phase 8 Completed Files

- [x] `lib/routeros_cm_web/api_spec.ex` - OpenAPI 3.0 specification module
- [x] `lib/routeros_cm_web/api_schemas.ex` - OpenAPI schema definitions for all resources
- [x] `lib/routeros_cm_web/controllers/api/v1/open_api_controller.ex` - OpenAPI spec and Swagger UI endpoints
- [x] `lib/routeros_cm_web/router.ex` - Added api_public pipeline and documentation routes
- [x] `test/routeros_cm_web/controllers/api/v1/open_api_controller_test.exs` - 4 tests
- [x] `test/routeros_cm_web/controllers/api/v1/integration/full_flow_test.exs` - 10 integration tests

### API Implementation Complete

All 8 phases of the REST API implementation are now complete:
- **227 total tests** passing
- **OpenAPI/Swagger documentation** available at `/api/v1/docs`
- **JSON spec** available at `/api/v1/openapi`
- **Full integration test suite** covering all API flows and token scope enforcement

---

## Phase 1: API Foundation

### Objectives
- Set up API authentication (API tokens)
- Create base controller and error handling
- Establish consistent JSON response format
- Add API versioning support

### Tasks

#### 1.1 API Token Authentication

Create an API token system for service-to-service authentication.

**Database Migration**:
```elixir
# priv/repo/migrations/xxx_create_api_tokens.exs
create table(:api_tokens) do
  add :name, :string, null: false
  add :token_hash, :string, null: false
  add :description, :string
  add :scopes, {:array, :string}, default: []
  add :last_used_at, :utc_datetime
  add :expires_at, :utc_datetime
  add :user_id, references(:users, on_delete: :delete_all)
  timestamps()
end
create unique_index(:api_tokens, [:token_hash])
```

**Files to Create**:
- `lib/routeros_cm/accounts/api_token.ex` - Ecto schema
- `lib/routeros_cm/api_auth.ex` - Token generation/verification
- `lib/routeros_cm_web/plugs/api_auth.ex` - Plug for authentication
- `lib/routeros_cm_web/controllers/api/token_controller.ex` - Manage tokens via UI

**Token Scopes** (granular permissions):
- `nodes:read`, `nodes:write`
- `dns:read`, `dns:write`
- `tunnels:read`, `tunnels:write`
- `wireguard:read`, `wireguard:write`
- `users:read`, `users:write`
- `audit:read`

#### 1.2 API Base Setup

**Router Configuration** (`lib/routeros_cm_web/router.ex`):
```elixir
pipeline :api do
  plug :accepts, ["json"]
  plug RouterosCmWeb.Plugs.APIAuth
end

scope "/api/v1", RouterosCmWeb.API.V1, as: :api_v1 do
  pipe_through :api

  # All API routes go here
end
```

**Base Controller** (`lib/routeros_cm_web/controllers/api/v1/base_controller.ex`):
- Common helper functions
- Consistent response formatting
- Scope/permission checking

**Error Handling** (update `lib/routeros_cm_web/controllers/error_json.ex`):
```elixir
def render("400.json", %{reason: reason}) do
  %{error: %{code: "bad_request", message: reason}}
end

def render("401.json", _) do
  %{error: %{code: "unauthorized", message: "Invalid or missing API token"}}
end

def render("403.json", %{scope: scope}) do
  %{error: %{code: "forbidden", message: "Token lacks required scope: #{scope}"}}
end

def render("404.json", %{resource: resource}) do
  %{error: %{code: "not_found", message: "#{resource} not found"}}
end

def render("422.json", %{changeset: changeset}) do
  %{error: %{code: "validation_error", details: format_changeset_errors(changeset)}}
end

def render("500.json", _) do
  %{error: %{code: "internal_error", message: "An unexpected error occurred"}}
end
```

#### 1.3 Standard Response Format

All API responses follow a consistent structure:

**Success (single resource)**:
```json
{
  "data": { ... },
  "meta": { "request_id": "..." }
}
```

**Success (collection)**:
```json
{
  "data": [ ... ],
  "meta": {
    "request_id": "...",
    "total": 100,
    "page": 1,
    "per_page": 50
  }
}
```

**Cluster Operation Result**:
```json
{
  "data": {
    "operation": "create",
    "resource": "dns_record",
    "successes": [
      { "node": "router1", "id": "*1A" },
      { "node": "router2", "id": "*1B" }
    ],
    "failures": [
      { "node": "router3", "error": "connection timeout" }
    ]
  },
  "meta": { "request_id": "..." }
}
```

**Error**:
```json
{
  "error": {
    "code": "validation_error",
    "message": "Invalid request parameters",
    "details": { ... }
  },
  "meta": { "request_id": "..." }
}
```

### Deliverables
- [x] API token database migration
- [x] API token schema and context functions
- [x] API authentication plug
- [x] Base API controller
- [x] Enhanced error JSON views
- [ ] Request ID middleware (deferred - optional)
- [x] API versioning setup (v1 namespace)

---

## Phase 2: Cluster & Node Management API

### Endpoints

| Method | Endpoint | Description | Scope |
|--------|----------|-------------|-------|
| GET | `/api/v1/nodes` | List all nodes | `nodes:read` |
| GET | `/api/v1/nodes/:id` | Get node details | `nodes:read` |
| POST | `/api/v1/nodes` | Create a node | `nodes:write` |
| PATCH | `/api/v1/nodes/:id` | Update a node | `nodes:write` |
| DELETE | `/api/v1/nodes/:id` | Delete a node | `nodes:write` |
| POST | `/api/v1/nodes/:id/test` | Test node connection | `nodes:read` |
| GET | `/api/v1/cluster/health` | Get cluster health | `nodes:read` |
| GET | `/api/v1/cluster/stats` | Get cluster statistics | `nodes:read` |

### Files to Create

- `lib/routeros_cm_web/controllers/api/v1/node_controller.ex`
- `lib/routeros_cm_web/controllers/api/v1/cluster_controller.ex`
- `lib/routeros_cm_web/controllers/api/v1/json/node_json.ex`
- `lib/routeros_cm_web/controllers/api/v1/json/cluster_json.ex`

### Node JSON Response

```json
{
  "data": {
    "id": "uuid",
    "name": "router1",
    "host": "192.168.1.1",
    "port": 8728,
    "status": "online",
    "last_seen_at": "2024-01-15T10:30:00Z",
    "inserted_at": "2024-01-01T00:00:00Z",
    "updated_at": "2024-01-15T10:30:00Z"
  }
}
```

### Cluster Health Response

```json
{
  "data": {
    "nodes": {
      "uuid1": {
        "name": "router1",
        "status": "healthy",
        "cpu_load": 15,
        "memory": { "free": 268435456, "total": 536870912, "percent_used": 50 },
        "uptime": "5d 12h 30m",
        "version": "7.12"
      }
    },
    "summary": {
      "total_nodes": 3,
      "healthy_nodes": 3,
      "unhealthy_nodes": 0
    }
  }
}
```

### Tests

- `test/routeros_cm_web/controllers/api/v1/node_controller_test.exs`
- `test/routeros_cm_web/controllers/api/v1/cluster_controller_test.exs`

### Deliverables
- [x] Node controller with full CRUD
- [x] Cluster controller for health/stats
- [x] JSON views for nodes and cluster (embedded in controllers)
- [x] Controller tests (15 tests total)

---

## Phase 3: DNS Management API

### Endpoints

| Method | Endpoint | Description | Scope |
|--------|----------|-------------|-------|
| GET | `/api/v1/dns/records` | List DNS records (cluster view) | `dns:read` |
| GET | `/api/v1/dns/records/:name` | Get record by name | `dns:read` |
| POST | `/api/v1/dns/records` | Create DNS record | `dns:write` |
| PATCH | `/api/v1/dns/records/:name` | Update DNS record | `dns:write` |
| DELETE | `/api/v1/dns/records/:name` | Delete DNS record | `dns:write` |
| GET | `/api/v1/dns/settings` | Get DNS server settings | `dns:read` |
| PATCH | `/api/v1/dns/settings` | Update DNS settings | `dns:write` |
| POST | `/api/v1/dns/cache/flush` | Flush DNS cache | `dns:write` |

### Query Parameters

- `?type=A|AAAA|CNAME` - Filter by record type
- `?node=router1` - Filter by specific node (returns per-node view)

### Files to Create

- `lib/routeros_cm_web/controllers/api/v1/dns_controller.ex`
- `lib/routeros_cm_web/controllers/api/v1/json/dns_json.ex`

### DNS Record Response (Cluster View)

```json
{
  "data": [
    {
      "name": "app.local",
      "type": "A",
      "address": "192.168.1.100",
      "ttl": "1d",
      "nodes": [
        { "node_name": "router1", "node_id": "uuid1", "record_id": "*1A" },
        { "node_name": "router2", "node_id": "uuid2", "record_id": "*1B" }
      ]
    }
  ]
}
```

### Create/Update Request

```json
{
  "name": "app.local",
  "address": "192.168.1.100",
  "type": "A",
  "ttl": "1d",
  "comment": "Application server"
}
```

### Tests

- `test/routeros_cm_web/controllers/api/v1/dns_controller_test.exs`

### Deliverables
- [x] DNS controller with full CRUD
- [x] Cluster-wide and per-node query support
- [x] DNS JSON views (embedded in controller)
- [x] Controller tests (11 tests)

---

## Phase 4: GRE Tunnel API

### Endpoints

| Method | Endpoint | Description | Scope |
|--------|----------|-------------|-------|
| GET | `/api/v1/gre` | List GRE interfaces | `tunnels:read` |
| GET | `/api/v1/gre/:name` | Get GRE interface by name | `tunnels:read` |
| POST | `/api/v1/gre` | Create GRE interface | `tunnels:write` |
| DELETE | `/api/v1/gre/:name` | Delete GRE interface | `tunnels:write` |
| POST | `/api/v1/gre/:name/ip` | Assign IP to interface | `tunnels:write` |
| DELETE | `/api/v1/gre/:name/ip/:address` | Remove IP from interface | `tunnels:write` |

### Files to Create

- `lib/routeros_cm_web/controllers/api/v1/gre_controller.ex`
- `lib/routeros_cm_web/controllers/api/v1/json/gre_json.ex`

### GRE Interface Response

```json
{
  "data": [
    {
      "name": "gre-tunnel1",
      "local_address": "192.168.1.1",
      "remote_address": "10.0.0.1",
      "mtu": 1476,
      "ipsec_secret": "***",
      "allow_fast_path": false,
      "addresses": [
        { "address": "172.16.0.1/30", "interface": "gre-tunnel1" }
      ],
      "nodes": [
        { "node_name": "router1", "interface_id": "*1" },
        { "node_name": "router2", "interface_id": "*2" }
      ]
    }
  ]
}
```

### Create Request

```json
{
  "name": "gre-tunnel1",
  "local-address": "192.168.1.1",
  "remote-address": "10.0.0.1",
  "ipsec-secret": "optional-secret"
}
```

### Tests

- `test/routeros_cm_web/controllers/api/v1/gre_controller_test.exs`

### Deliverables
- [x] GRE controller
- [x] IP assignment endpoints
- [x] GRE JSON views (embedded in controller)
- [x] Controller tests (10 tests)

---

## Phase 5: WireGuard API

### Endpoints

#### Interfaces

| Method | Endpoint | Description | Scope |
|--------|----------|-------------|-------|
| GET | `/api/v1/wireguard` | List WireGuard interfaces | `wireguard:read` |
| GET | `/api/v1/wireguard/:name` | Get interface by name | `wireguard:read` |
| POST | `/api/v1/wireguard` | Create interface | `wireguard:write` |
| DELETE | `/api/v1/wireguard/:name` | Delete interface | `wireguard:write` |
| POST | `/api/v1/wireguard/:name/ip` | Assign IP | `wireguard:write` |
| DELETE | `/api/v1/wireguard/:name/ip/:address` | Remove IP | `wireguard:write` |

#### Peers

| Method | Endpoint | Description | Scope |
|--------|----------|-------------|-------|
| GET | `/api/v1/wireguard/:name/peers` | List peers | `wireguard:read` |
| POST | `/api/v1/wireguard/:name/peers` | Add peer | `wireguard:write` |
| DELETE | `/api/v1/wireguard/:name/peers/:public_key` | Remove peer | `wireguard:write` |
| POST | `/api/v1/wireguard/generate-keypair` | Generate new keypair | `wireguard:write` |

### Files to Create

- `lib/routeros_cm_web/controllers/api/v1/wireguard_controller.ex`
- `lib/routeros_cm_web/controllers/api/v1/json/wireguard_json.ex`

### WireGuard Interface Response

```json
{
  "data": [
    {
      "name": "wg0",
      "listen_port": 51820,
      "mtu": 1420,
      "public_key": "base64...",
      "addresses": [
        { "address": "10.0.0.1/24", "interface": "wg0" }
      ],
      "peer_count": 5,
      "nodes": [
        { "node_name": "router1", "interface_id": "*1" }
      ]
    }
  ]
}
```

### Peer Response

```json
{
  "data": [
    {
      "public_key": "base64...",
      "allowed_address": "10.0.0.2/32",
      "endpoint": "client.example.com:51820",
      "persistent_keepalive": 25,
      "last_handshake": "2024-01-15T10:30:00Z",
      "rx_bytes": 1048576,
      "tx_bytes": 2097152,
      "nodes": [
        { "node_name": "router1", "peer_id": "*1" }
      ]
    }
  ]
}
```

### Create Peer Request

```json
{
  "public-key": "base64...",
  "allowed-address": "10.0.0.2/32",
  "endpoint-address": "client.example.com",
  "endpoint-port": "51820",
  "persistent-keepalive": "25s"
}
```

### Tests

- `test/routeros_cm_web/controllers/api/v1/wireguard_controller_test.exs`

### Deliverables
- [x] WireGuard interface controller
- [x] Peer management endpoints
- [x] Keypair generation endpoint
- [x] WireGuard JSON views (embedded in controller)
- [x] Controller tests (15 tests)

---

## Phase 6: RouterOS Users API

### Endpoints

| Method | Endpoint | Description | Scope |
|--------|----------|-------------|-------|
| GET | `/api/v1/routeros-users` | List RouterOS users | `users:read` |
| GET | `/api/v1/routeros-users/:name` | Get user by name | `users:read` |
| POST | `/api/v1/routeros-users` | Create user | `users:write` |
| PATCH | `/api/v1/routeros-users/:name` | Update user | `users:write` |
| DELETE | `/api/v1/routeros-users/:name` | Delete user | `users:write` |
| GET | `/api/v1/routeros-users/groups` | List user groups | `users:read` |
| GET | `/api/v1/routeros-users/active` | List active sessions | `users:read` |

### Files to Create

- `lib/routeros_cm_web/controllers/api/v1/routeros_user_controller.ex`
- `lib/routeros_cm_web/controllers/api/v1/json/routeros_user_json.ex`

### RouterOS User Response

```json
{
  "data": [
    {
      "name": "admin",
      "group": "full",
      "comment": "Primary admin",
      "nodes": [
        {
          "node_name": "router1",
          "user_id": "*1",
          "last_logged_in": "2024-01-15T10:30:00Z",
          "disabled": false
        }
      ]
    }
  ]
}
```

### Create User Request

```json
{
  "name": "newuser",
  "password": "secure-password",
  "group": "write",
  "comment": "API created user"
}
```

### Tests

- `test/routeros_cm_web/controllers/api/v1/routeros_user_controller_test.exs`

### Deliverables
- [x] RouterOS user controller
- [x] Groups and active sessions endpoints
- [x] User JSON views (embedded in controller)
- [x] Controller tests (12 tests)

---

## Phase 7: Audit Log API

### Endpoints

| Method | Endpoint | Description | Scope |
|--------|----------|-------------|-------|
| GET | `/api/v1/audit` | List audit logs | `audit:read` |
| GET | `/api/v1/audit/:id` | Get specific log entry | `audit:read` |
| GET | `/api/v1/audit/stats` | Get audit statistics | `audit:read` |

### Query Parameters

- `?page=1&per_page=50` - Pagination
- `?action=create|update|delete` - Filter by action
- `?resource_type=dns_record|wireguard_interface|...` - Filter by resource
- `?success=true|false` - Filter by success status
- `?from=2024-01-01T00:00:00Z` - Filter by date range
- `?to=2024-01-15T23:59:59Z`

### Files to Create

- `lib/routeros_cm_web/controllers/api/v1/audit_controller.ex`
- `lib/routeros_cm_web/controllers/api/v1/json/audit_json.ex`

### Audit Log Response

```json
{
  "data": [
    {
      "id": "uuid",
      "action": "create",
      "resource_type": "dns_record",
      "resource_id": "app.local",
      "success": true,
      "user": {
        "id": "uuid",
        "email": "admin@example.com"
      },
      "details": {
        "node": "router1",
        "attrs": { "address": "192.168.1.100" }
      },
      "inserted_at": "2024-01-15T10:30:00Z"
    }
  ],
  "meta": {
    "total": 1250,
    "page": 1,
    "per_page": 50
  }
}
```

### Tests

- `test/routeros_cm_web/controllers/api/v1/audit_controller_test.exs`

### Deliverables
- [x] Audit controller with filtering
- [x] Pagination support
- [x] Audit JSON views (embedded in controller)
- [x] Controller tests (10 tests)

---

## Phase 8: Documentation & Testing

### OpenAPI/Swagger Documentation

Create OpenAPI 3.0 specification for all endpoints.

**Files to Create**:
- `lib/routeros_cm_web/api_spec.ex` - OpenAPI spec module
- `lib/routeros_cm_web/controllers/api/v1/docs_controller.ex` - Serve docs

**Tools**:
- Consider `open_api_spex` hex package for spec generation
- Swagger UI for interactive documentation

### Integration Tests

Create comprehensive integration tests that test full API flows:

- Authentication flow tests
- CRUD lifecycle tests for each resource
- Cluster operation tests (partial success scenarios)
- Error handling tests

### Load/Performance Tests

Basic performance benchmarks:
- Response time for list operations
- Concurrent request handling
- Cluster operation throughput

### Deliverables
- [x] OpenAPI 3.0 specification (`/api/v1/openapi`)
- [x] Swagger UI integration (`/api/v1/docs`)
- [x] Integration test suite (10 tests covering full flows)
- [ ] Performance benchmarks (optional - deferred)
- [x] API schemas for all resources

---

## Implementation Order

### Priority 1 (Foundation)
1. Phase 1: API Foundation - Required for all other phases

### Priority 2 (Core Resources)
2. Phase 2: Cluster & Node Management - Foundation for all operations
3. Phase 3: DNS Management - High-value, simpler implementation

### Priority 3 (Network Services)
4. Phase 4: GRE Tunnel API
5. Phase 5: WireGuard API

### Priority 4 (Supporting Features)
6. Phase 6: RouterOS Users API
7. Phase 7: Audit Log API

### Priority 5 (Polish)
8. Phase 8: Documentation & Testing

---

## Additional Considerations

### Rate Limiting

Consider adding rate limiting for production use:
```elixir
plug :rate_limit, max_requests: 100, interval_seconds: 60
```

### Webhook Support (Future)

For async notifications of cluster events:
- Webhook registration endpoints
- Event dispatch on resource changes
- Retry logic for failed deliveries

### Batch Operations (Future)

For high-volume provisioning:
```
POST /api/v1/batch
{
  "operations": [
    { "method": "POST", "path": "/dns/records", "body": {...} },
    { "method": "POST", "path": "/dns/records", "body": {...} }
  ]
}
```

### API Client SDKs (Future)

Generate client libraries for common languages:
- Python SDK
- Go SDK
- JavaScript/TypeScript SDK

---

## File Structure Summary

```
lib/routeros_cm/
  accounts/
    api_token.ex          # API token schema
  api_auth.ex             # Token generation/verification

lib/routeros_cm_web/
  plugs/
    api_auth.ex           # Authentication plug
  controllers/api/v1/
    base_controller.ex    # Common helpers
    node_controller.ex
    cluster_controller.ex
    dns_controller.ex
    gre_controller.ex
    wireguard_controller.ex
    routeros_user_controller.ex
    audit_controller.ex
    json/
      node_json.ex
      cluster_json.ex
      dns_json.ex
      gre_json.ex
      wireguard_json.ex
      routeros_user_json.ex
      audit_json.ex

test/routeros_cm_web/controllers/api/v1/
  node_controller_test.exs
  cluster_controller_test.exs
  dns_controller_test.exs
  gre_controller_test.exs
  wireguard_controller_test.exs
  routeros_user_controller_test.exs
  audit_controller_test.exs
  integration/
    full_provisioning_flow_test.exs
```

---

## Notes

- All endpoints return JSON
- All write operations are logged to the audit system
- All operations use the existing context modules (no new business logic needed)
- Tests should mock the MikroTik client to avoid real device dependencies
- Consider using `Mox` for mocking in tests
