# MikrotikApi Feature Requests

Feature requests identified while building RouterOS Cluster Manager.

**Status: All features implemented in MikrotikApi v0.3.2**

## Implemented Features

All requested features are now available in MikrotikApi 0.3.2:

### Options Support
All wrapper functions now accept `opts` for scheme/port configuration.

### WireGuard Operations
- `wireguard_interface_list/3`, `wireguard_interface_add/4`, `wireguard_interface_update/5`, `wireguard_interface_delete/4`
- `wireguard_interface_ensure/5`, `wireguard_interface_getall/4`
- `wireguard_peer_list/3`, `wireguard_peer_add/4`, `wireguard_peer_update/5`, `wireguard_peer_delete/4`
- `wireguard_peer_ensure/6`
- `wireguard_cluster_add/5`, `wireguard_cluster_add_peers/5`

### DNS Operations
- `dns_static_list/3`, `dns_static_add/4`, `dns_static_update/5`, `dns_static_delete/4`, `dns_static_ensure/5`
- `dns_settings_get/3`, `dns_settings_set/4`
- `dns_cache_list/3`, `dns_cache_flush/3`

### User Management
- `user_list/3`, `user_add/4`, `user_update/5`, `user_delete/4`, `user_ensure/5`
- `user_group_list/3`, `user_active_list/3`

### GRE Operations
- `gre_list/3`, `gre_add/4`, `gre_update/5`, `gre_delete/4`, `gre_ensure/5`

### System Information
- `system_resource/3`, `system_identity/3`, `system_identity_set/4`
- `system_health/3`, `system_packages/3`

## Notes

### HTTP Methods for RouterOS REST API

| Operation | Method | Path Pattern |
|-----------|--------|--------------|
| List | GET | `/resource` |
| Create | PUT | `/resource` |
| Read one | GET | `/resource/{id}` |
| Update | PATCH | `/resource/{id}` |
| Delete | DELETE | `/resource/{id}` |
| Action | POST | `/resource/action` |

### Common Gotchas

1. **PUT for create, not POST** - RouterOS REST API uses PUT to create new resources
2. **Actions use POST** - Operations like `/user/set`, `/dns/cache/flush` use POST
3. **Port 80 for HTTP, 443 for HTTPS** - Not the traditional API ports (8728/8729) which are for the binary protocol
4. **The `.id` field** - RouterOS uses `.id` (with dot) for resource identifiers
