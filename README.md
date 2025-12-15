# RouterOS Cluster Manager

A comprehensive web application for centrally managing MikroTik RouterOS clusters. Provides unified control over networking, tunnels, DNS, user management, and monitoring across multiple RouterOS devices.

![Phoenix](https://img.shields.io/badge/Phoenix-1.8-orange.svg)
![Elixir](https://img.shields.io/badge/Elixir-1.15+-purple.svg)
![License](https://img.shields.io/badge/License-MIT-blue.svg)

## Features

### Infrastructure Management
- **Multi-Node Cluster:** Manage multiple RouterOS devices from a single interface
- **Encrypted Credentials:** AES-256-GCM encryption for stored node credentials
- **Real-Time Updates:** Live monitoring with automatic 30-second refresh intervals
- **Health Monitoring:** Track node online/offline status with visual indicators
- **Audit Logging:** Comprehensive audit trail for all operations with user attribution

### Resource Management
- **WireGuard VPN:** 
  - Interface management with cluster-wide deployment
  - Peer configuration with keepalive and preshared keys
  - IP address assignment visibility
- **GRE Tunnels:** Create and manage GRE tunnels across the cluster
- **DNS Management:** Static DNS record management (A, AAAA, CNAME, MX, TXT)
- **User Management:** RouterOS system user administration
- **IP Addresses:** View and manage IP addresses assigned to interfaces

### User Experience
- **Modern UI:** Built with DaisyUI + Tailwind CSS v4
- **Authentication:** Secure user authentication with role-based access
- **Responsive Design:** Mobile-friendly interface
- **Dashboard:** Cluster overview with statistics and recent activity

## Technology Stack

- **Framework:** Phoenix 1.8 with LiveView 1.0
- **Database:** SQLite 3 with Ecto
- **RouterOS API:** Official MikrotikApi library
- **Encryption:** Cloak (AES-256-GCM) for credential storage
- **UI Framework:** DaisyUI + Tailwind CSS v4
- **HTTP Client:** Req library

## Prerequisites

- **Elixir:** 1.15 or higher
- **Erlang/OTP:** 26 or higher
- **Node.js:** 18+ (for asset compilation)
- **RouterOS Devices:** API service enabled on target devices

### RouterOS Requirements

Ensure the API service is enabled on your RouterOS devices:

```routeros
/ip service enable api
# Or for SSL:
/ip service enable api-ssl
```

Default API ports:
- **8728** - Non-SSL API
- **8729** - SSL API
- **443** - HTTPS (if configured)

## Installation

### 1. Clone the Repository

```bash
git clone <repository-url>
cd routeros_cm
```

### 2. Install Dependencies

```bash
mix deps.get
npm install --prefix assets
```

### 3. Configure Database

Create and migrate the database:

```bash
mix ecto.setup
```

This will:
- Create the SQLite database
- Run all migrations
- Seed initial data (if any)

### 4. Configure Encryption

The application uses Cloak for encrypting node credentials. A default encryption key is generated, but you should configure your own for production.

Generate a new key:

```bash
mix cloak.generate_key
```

Add to `config/runtime.exs`:

```elixir
config :routeros_cm, RouterosCm.Vault,
  ciphers: [
    default: {Cloak.Ciphers.AES.GCM, tag: "AES.GCM.V1", key: Base.decode64!("YOUR_KEY_HERE")}
  ]
```

### 5. Start the Server

```bash
mix phx.server
```

Or start inside IEx:

```bash
iex -S mix phx.server
```

Visit [`http://localhost:4000`](http://localhost:4000) in your browser.

## Getting Started

### First-Time Setup

1. **Register an Account:**
   - Navigate to `/users/register`
   - Create your admin account

2. **Add Your First Node:**
   - Click "Nodes" in the navigation
   - Click "Add Node"
   - Fill in:
     - Name (e.g., "router-01")
     - IP address or hostname
     - API port (default: 8728)
     - Username (RouterOS user with API access)
     - Password

3. **Test Connection:**
   - After adding, the node will show online/offline status
   - Green badge = Connected successfully
   - Red badge = Connection failed (check credentials/network)

### Quick Actions

**Managing WireGuard:**
```
1. Navigate to Tunnels → WireGuard
2. Click "New Interface" to create an interface
3. Click the user icon to manage peers for an interface
```

**Managing DNS:**
```
1. Navigate to DNS
2. Click "Add Record"
3. Select record type and fill in details
4. Choose deployment scope (specific nodes or cluster-wide)
```

**Managing Users:**
```
1. Navigate to Users
2. Click "Add User"
3. Configure username, password, and group
4. Deploy to selected nodes
```

## Configuration

### Development

Edit `config/dev.exs` for development settings:

```elixir
config :routeros_cm, RouterosCmWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  debug_errors: true
```

### Production

See `DEPLOYMENT.md` for production configuration and deployment instructions.

### Environment Variables

Key environment variables:

```bash
# Secret key base (generate with: mix phx.gen.secret)
SECRET_KEY_BASE=your_secret_key_base

# Database path
DATABASE_PATH=priv/repo/routeros_cm.db

# Encryption key (generate with: mix cloak.generate_key)
CLOAK_KEY=your_encryption_key
```

## Usage Examples

### Cluster-Wide Deployment

When creating resources (DNS records, WireGuard interfaces, etc.), you can deploy to:
- **All active nodes:** Select "All active nodes (cluster-wide)"
- **Specific nodes:** Select individual nodes from the list

### Audit Trail

All operations are logged in the Audit Logs section:
- View what changes were made
- See who made the changes
- Filter by action type or date
- Track success/failure of operations

## Development

### Running Tests

```bash
# Run all tests
mix test

# Run with coverage
mix test --cover

# Run specific test file
mix test test/routeros_cm_web/live/dashboard_live_test.exs
```

### Code Quality

```bash
# Run formatter
mix format

# Run linter
mix precommit
```

### Database Operations

```bash
# Create migration
mix ecto.gen.migration migration_name

# Run migrations
mix ecto.migrate

# Rollback
mix ecto.rollback

# Reset database
mix ecto.reset
```

## Architecture

### No Local Storage for Resources

The application follows an **API-first** architecture:
- RouterOS resources (tunnels, DNS, users) are **NOT stored locally**
- All operations go directly to RouterOS API
- SQLite is only used for:
  - User accounts (authentication)
  - Node credentials (encrypted)
  - Audit logs

This design ensures:
- Single source of truth (RouterOS devices)
- No sync issues
- Direct API access
- Real-time data

### Concurrent Operations

All cluster-wide operations use `Task.async_stream` with:
- 15-second timeout per node
- Concurrent execution across nodes
- Graceful handling of partial failures

## Troubleshooting

### Node Shows Offline

1. **Check network connectivity:**
   ```bash
   ping <node-ip>
   ```

2. **Verify API service is running:**
   ```routeros
   /ip service print
   ```

3. **Test API access:**
   ```bash
   telnet <node-ip> 8728
   ```

4. **Check credentials:** Ensure the user has API permissions

### Connection Timeout

- Increase timeout in `config/config.exs`:
  ```elixir
  config :routeros_cm,
    api_timeout: 30_000  # 30 seconds
  ```

### Database Locked

SQLite may lock with concurrent access:
```bash
# Reset database
mix ecto.reset
```

## Contributing

Contributions are welcome! Please:

1. Fork the repository
2. Create a feature branch
3. Write tests for new features
4. Run `mix precommit` to ensure code quality
5. Submit a pull request

## License

MIT License - see LICENSE file for details

## Acknowledgments

- [Phoenix Framework](https://phoenixframework.org/)
- [MikroTik](https://mikrotik.com/) for RouterOS
- [DaisyUI](https://daisyui.com/) for UI components
- [Heroicons](https://heroicons.com/) for icons

## Support

For issues and questions:
- Create an issue in the repository
- Check existing documentation
- Review RouterOS API documentation

## Roadmap

See `tunnel_manager/routeros_cluster_manager.md` for detailed feature roadmap and migration plan.

### Future Enhancements
- Firewall rule management
- DHCP server configuration
- Routing (BGP, OSPF) management
- Configuration backup/restore
- Monitoring and alerting
- Script execution across cluster
