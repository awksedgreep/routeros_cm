# WireGuard Site-to-Site Setup Guide

This guide explains how to set up WireGuard VPN tunnels between your RouterOS cluster and remote sites.

## Concepts

### Cluster Interface
When you create a WireGuard interface in RouterOS Cluster Manager, it's deployed to **all active nodes** with the **same private key**. This means:
- All nodes share the same public key
- Remote sites only need one peer configuration to connect to the cluster
- Failover works automatically - if one node goes down, the remote can connect to another

### Cluster IP
The WireGuard interface IP is the same on all nodes (e.g., `10.0.0.1/24`). In a VRRP/failover setup, only one node actively uses this IP at a time.

## Setup Workflow

### Step 1: Create WireGuard Interface on Cluster

1. Navigate to **WireGuard** in the sidebar
2. Click **New Interface**
3. Fill in:
   - **Interface Name**: e.g., `wg-sites`
   - **Listen Port**: e.g., `51820` (optional, auto-assigned if blank)
   - **Private Key**: Leave blank to auto-generate (recommended)
   - **MTU**: `1420` (default)
4. Click **Create Interface**

The interface is created on all active nodes with the same private key.

### Step 2: Assign IP Address to Cluster Interface

1. On the interface card, click **Assign IP**
2. Enter the IP in CIDR format: e.g., `10.0.0.1/24`
3. Click **Assign IP**

The same IP is assigned to the interface on all nodes.

### Step 3: Copy the Cluster Public Key

The public key is displayed on the interface card. Click the copy button to copy it - you'll need this for the remote site configuration.

### Step 4: Configure the Remote Site

On the remote MikroTik router:

```routeros
# Create WireGuard interface
/interface wireguard add name=wg-cluster listen-port=51821

# Assign IP (different from cluster)
/ip address add address=10.0.0.2/24 interface=wg-cluster

# Add the cluster as a peer
/interface wireguard peers add \
  interface=wg-cluster \
  public-key="CLUSTER_PUBLIC_KEY_HERE" \
  endpoint-address=CLUSTER_NODE_IP \
  endpoint-port=51820 \
  allowed-address=10.0.0.1/32 \
  persistent-keepalive=25 \
  comment="Cluster peer"
```

Replace:
- `CLUSTER_PUBLIC_KEY_HERE` with the copied public key
- `CLUSTER_NODE_IP` with any cluster node's IP (or a floating IP/DNS name)

### Step 5: Add Remote Site as Peer on Cluster

1. Click **Manage Peers** on the interface card
2. Click **Add Peer**
3. Fill in:
   - **Public Key**: The remote site's WireGuard public key
   - **Allowed IPs**: `10.0.0.2/32` (the remote's tunnel IP)
   - **Endpoint Address**: Remote site's public IP (optional if remote initiates)
   - **Endpoint Port**: Remote's listen port (optional)
   - **Persistent Keepalive**: `25` (recommended for NAT traversal)
4. Click **Add Peer**

The peer is added to all cluster nodes automatically.

### Step 6: Verify Connection

On the remote router:
```routeros
/interface wireguard peers print
```

Look for `last-handshake` to confirm the tunnel is established.

In RouterOS Cluster Manager, the peers table shows:
- Last handshake time
- RX/TX transfer statistics
- Which nodes have the peer configured

## Remote Setup Helper

When adding a peer, check **"Show RouterOS commands for remote site"** to see the exact commands the remote site needs to run. This includes your cluster's public key automatically.

## Troubleshooting

### No Handshake
- Verify firewall rules allow UDP on the listen port
- Check that endpoint addresses are reachable
- Ensure public keys are correct on both sides

### Asymmetric Traffic
- Verify `allowed-address` covers the expected IP ranges
- Check routing tables on both sides

### Connection Drops
- Add `persistent-keepalive=25` to maintain NAT mappings
- Verify both endpoints can reach each other

## Architecture Notes

```
┌─────────────────────────────────────────────────────────┐
│                    CLUSTER (VRRP)                       │
│  ┌─────────────┐              ┌─────────────┐          │
│  │   Node r1   │              │   Node r2   │          │
│  │  wg-sites   │              │  wg-sites   │          │
│  │ 10.0.0.1/24 │              │ 10.0.0.1/24 │          │
│  │ (same key)  │              │ (same key)  │          │
│  └─────────────┘              └─────────────┘          │
└─────────────────────────────────────────────────────────┘
                          │
                    WireGuard Tunnel
                          │
              ┌───────────────────────┐
              │     REMOTE SITE       │
              │      wg-cluster       │
              │     10.0.0.2/24       │
              └───────────────────────┘
```

Both cluster nodes have the same WireGuard configuration. The remote site connects to whichever node is active (via VRRP floating IP or DNS failover).
