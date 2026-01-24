# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] - 2025-01-XX

### Initial Release

Complete rewrite and migration from `tunnel_manager` to `routeros_cm` with modern Phoenix framework and enhanced cluster management.

### Added

#### Infrastructure
- Phoenix 1.8 with LiveView 1.0 for real-time UI updates
- PostgreSQL database with Ecto 3.13.5 for user management
- AES-256-GCM encryption for node credentials (Cloak)
- Audit logging for all cluster operations
- User authentication system with email/password
- Multi-node cluster management dashboard

#### Cluster Management
- Node CRUD operations with connection testing
- Encrypted credential storage for RouterOS API access
- Health monitoring and status tracking
- Last-seen timestamps for node connectivity
- Test connection functionality before saving

#### WireGuard Management
- Interface creation, update, and deletion
- Peer management with public key authentication
- Handshake statistics and last-seen tracking
- TX/RX byte counters with formatted display
- Cluster-wide or per-node deployment options
- Real-time status updates

#### GRE Tunnel Management
- GRE interface creation and configuration
- Remote endpoint and local address setup
- MTU configuration
- Cluster-wide or per-node deployment
- Running/disabled status tracking

#### IP Address Management
- IP address assignment to interfaces
- CIDR notation support
- Integration with WireGuard and GRE interfaces
- Display of all IPs per interface in tables
- Cluster-wide or per-node deployment

#### DNS Management
- Static DNS record management (A, AAAA, CNAME)
- DNS server settings configuration
- DNS cache viewing and flushing
- TTL configuration support
- Cluster-wide or per-node deployment

#### RouterOS User Management
- System user creation and management
- Group-based permissions (read, write, full)
- Password management
- User enabling/disabling
- Cluster-wide or per-node deployment

#### User Experience
- Dashboard with cluster statistics
- Recent activity feed (10 most recent actions)
- Real-time updates every 30 seconds
- Confirmation dialogs for destructive operations
- Loading states with spinner animations
- Empty state messages with helpful hints
- Formatted byte display (B, KB, MB, GB)
- Error handling with user-friendly messages

#### Development
- Comprehensive README with setup instructions
- Deployment guide with production configuration
- Basic LiveView test suite
- Pre-commit checks (formatting, credo, tests)
- Mix aliases for common tasks

### Changed

#### Architecture
- Migrated from older Phoenix version to Phoenix 1.8
- Switched to API-first architecture (no local RouterOS resource storage)
- Replaced outdated HTTP clients with Req library
- Moved from database-backed resources to pure API operations
- Implemented Task.async_stream for concurrent cluster operations
- Removed dependency on background job processing (Oban)

#### UI/UX
- Modernized UI with DaisyUI and Tailwind CSS v4
- Added real-time LiveView updates (30s interval)
- Improved navigation with consistent header
- Enhanced forms with better validation
- Added cluster-wide deployment toggle switches

### Technical Details

#### Dependencies
- Phoenix 1.8.5 / Phoenix LiveView 1.0.1
- Ecto 3.13.5 / Ecto SQL 3.13.3
- Postgrex (PostgreSQL driver)
- MikrotikApi 0.3.1 (official RouterOS API client)
- Req 0.5.9 (modern HTTP client)
- Cloak 1.1.4 (AES-256-GCM encryption)
- Tailwind CSS v4
- DaisyUI (UI components)

#### Configuration
- Environment-based configuration (dev, test, prod)
- Encrypted credential storage with Cloak
- Configurable timeouts (15s default for cluster operations)
- LiveView auto-refresh (30s interval)

#### Testing
- Basic LiveView integration tests
- Authentication flow testing
- Page rendering verification
- Manual testing focus for real-world scenarios

### Removed

- **Background Jobs**: Removed Oban dependency - LiveView auto-refresh provides sufficient real-time updates
- **Local Resource Storage**: RouterOS resources (WireGuard, GRE, DNS, users) no longer stored in local database
- **Old HTTP Clients**: Removed HTTPoison and Tesla in favor of Req
- **Comprehensive Test Suite**: Focused on minimal tests for manual validation phase

### Security

- AES-256-GCM encryption for RouterOS credentials at rest
- User authentication with bcrypt password hashing
- Secure session management
- No plaintext credential storage
- Audit logging for all operations

### Performance

- Concurrent cluster operations with Task.async_stream
- 15-second timeouts for all RouterOS API calls
- Connection pooling for database operations
- Optimized LiveView updates (30s auto-refresh)
- Efficient PostgreSQL database for minimal overhead

### Migration Notes

#### For Users Migrating from tunnel_manager

1. **Database Changes**: New schema focused on users, nodes, and audit logs only
2. **No Resource Migration**: RouterOS resources (tunnels, DNS, users) are not migrated - they remain on RouterOS devices as the single source of truth
3. **Node Re-registration**: All RouterOS nodes must be re-added with their credentials
4. **User Accounts**: New user registration required (old accounts not migrated)
5. **Audit History**: Previous audit logs not migrated

#### Breaking Changes

- Complete rewrite - no backward compatibility with tunnel_manager
- Different database schema
- New API endpoints and LiveView routes
- Changed configuration format

### Known Limitations

- No firewall rule management (planned for future release)
- No DHCP management (planned for future release)
- No static routing configuration (planned for future release)
- No RADIUS/PPP user management (planned for future release)
- Basic test coverage (comprehensive tests deferred)
- No background health monitoring (manual refresh or auto-refresh)

### Roadmap

See [README.md](README.md#roadmap) for planned features and enhancements.

---

## Version History

### [0.1.0] - Initial Release
- First stable release of RouterOS Cluster Manager
- Migrated from legacy tunnel_manager codebase
- Core cluster management features complete
- Ready for production deployment

---

## Contributing

See [README.md](README.md#development) for development setup.

---

## Support

For issues, questions, or feature requests, please contact the development team or open an issue in the repository.
