defmodule RouterosCmWeb.ApiSchemas do
  @moduledoc """
  OpenAPI schema definitions for the RouterOS Cluster Manager API.
  """
  alias OpenApiSpex.Schema

  # Common schemas

  defmodule Error do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Error",
      description: "API error response",
      type: :object,
      properties: %{
        error: %Schema{
          type: :object,
          properties: %{
            code: %Schema{type: :string, description: "Error code"},
            message: %Schema{type: :string, description: "Error message"},
            details: %Schema{type: :object, description: "Additional error details"}
          },
          required: [:code, :message]
        }
      },
      required: [:error],
      example: %{
        "error" => %{
          "code" => "validation_error",
          "message" => "Invalid request parameters"
        }
      }
    })
  end

  defmodule ClusterResult do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ClusterResult",
      description: "Result of a cluster-wide operation",
      type: :object,
      properties: %{
        data: %Schema{
          type: :object,
          properties: %{
            operation: %Schema{type: :string, description: "Operation performed"},
            resource: %Schema{type: :string, description: "Resource type"},
            successes: %Schema{
              type: :array,
              items: %Schema{
                type: :object,
                properties: %{
                  node: %Schema{type: :string},
                  node_id: %Schema{type: :integer},
                  id: %Schema{type: :string}
                }
              }
            },
            failures: %Schema{
              type: :array,
              items: %Schema{
                type: :object,
                properties: %{
                  node: %Schema{type: :string},
                  error: %Schema{type: :string}
                }
              }
            }
          }
        }
      },
      example: %{
        "data" => %{
          "operation" => "create",
          "resource" => "dns_record",
          "successes" => [%{"node" => "router1", "node_id" => 1, "id" => "*1A"}],
          "failures" => []
        }
      }
    })
  end

  # Node schemas

  defmodule Node do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "Node",
      description: "RouterOS node in the cluster",
      type: :object,
      properties: %{
        id: %Schema{type: :integer, description: "Node ID"},
        name: %Schema{type: :string, description: "Node name"},
        host: %Schema{type: :string, description: "Node hostname or IP"},
        port: %Schema{type: :integer, description: "API port"},
        use_ssl: %Schema{type: :boolean, description: "Whether to use SSL"},
        status: %Schema{type: :string, description: "Connection status"},
        last_seen_at: %Schema{type: :string, format: "date-time"},
        inserted_at: %Schema{type: :string, format: "date-time"},
        updated_at: %Schema{type: :string, format: "date-time"}
      },
      example: %{
        "id" => 1,
        "name" => "router1",
        "host" => "192.168.1.1",
        "port" => 8728,
        "use_ssl" => false,
        "status" => "online"
      }
    })
  end

  defmodule NodeCreateRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "NodeCreateRequest",
      description: "Request to create a new node",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Node name"},
        host: %Schema{type: :string, description: "Node hostname or IP"},
        port: %Schema{type: :integer, description: "API port", default: 8728},
        username: %Schema{type: :string, description: "API username"},
        password: %Schema{type: :string, description: "API password"},
        use_ssl: %Schema{type: :boolean, description: "Use SSL connection", default: false}
      },
      required: [:name, :host, :username, :password],
      example: %{
        "name" => "router1",
        "host" => "192.168.1.1",
        "port" => 8728,
        "username" => "admin",
        "password" => "secret"
      }
    })
  end

  # DNS schemas

  defmodule DNSRecord do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DNSRecord",
      description: "DNS record",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Domain name"},
        type: %Schema{type: :string, description: "Record type (A, AAAA, CNAME)"},
        address: %Schema{type: :string, description: "IP address for A/AAAA records"},
        cname: %Schema{type: :string, description: "Target for CNAME records"},
        ttl: %Schema{type: :string, description: "Time to live"},
        comment: %Schema{type: :string, description: "Comment"},
        nodes: %Schema{
          type: :array,
          items: %Schema{
            type: :object,
            properties: %{
              node_name: %Schema{type: :string},
              node_id: %Schema{type: :integer},
              record_id: %Schema{type: :string}
            }
          }
        }
      },
      example: %{
        "name" => "app.local",
        "type" => "A",
        "address" => "192.168.1.100",
        "ttl" => "1d",
        "nodes" => [%{"node_name" => "router1", "node_id" => 1, "record_id" => "*1A"}]
      }
    })
  end

  defmodule DNSRecordCreateRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "DNSRecordCreateRequest",
      description: "Request to create a DNS record",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Domain name"},
        address: %Schema{type: :string, description: "IP address"},
        cname: %Schema{type: :string, description: "CNAME target"},
        type: %Schema{type: :string, description: "Record type", default: "A"},
        ttl: %Schema{type: :string, description: "Time to live"},
        comment: %Schema{type: :string, description: "Comment"}
      },
      required: [:name],
      example: %{
        "name" => "app.local",
        "address" => "192.168.1.100",
        "type" => "A",
        "ttl" => "1d"
      }
    })
  end

  # GRE schemas

  defmodule GREInterface do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "GREInterface",
      description: "GRE tunnel interface",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Interface name"},
        local_address: %Schema{type: :string, description: "Local endpoint IP"},
        remote_address: %Schema{type: :string, description: "Remote endpoint IP"},
        mtu: %Schema{type: :string, description: "MTU value"},
        allow_fast_path: %Schema{type: :boolean},
        ipsec_secret: %Schema{type: :string, description: "IPSec secret (masked)"},
        running: %Schema{type: :boolean},
        disabled: %Schema{type: :boolean},
        nodes: %Schema{type: :array, items: %Schema{type: :object}}
      },
      example: %{
        "name" => "gre-tunnel1",
        "local_address" => "192.168.1.1",
        "remote_address" => "10.0.0.1",
        "mtu" => "1476"
      }
    })
  end

  # WireGuard schemas

  defmodule WireGuardInterface do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "WireGuardInterface",
      description: "WireGuard interface",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Interface name"},
        listen_port: %Schema{type: :string, description: "UDP listen port"},
        mtu: %Schema{type: :string, description: "MTU value"},
        public_key: %Schema{type: :string, description: "Public key"},
        running: %Schema{type: :boolean},
        disabled: %Schema{type: :boolean},
        nodes: %Schema{type: :array, items: %Schema{type: :object}}
      },
      example: %{
        "name" => "wg0",
        "listen_port" => "51820",
        "public_key" => "base64..."
      }
    })
  end

  defmodule WireGuardPeer do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "WireGuardPeer",
      description: "WireGuard peer",
      type: :object,
      properties: %{
        public_key: %Schema{type: :string, description: "Peer public key"},
        interface: %Schema{type: :string, description: "Interface name"},
        allowed_address: %Schema{type: :string, description: "Allowed IP address/subnet"},
        endpoint_address: %Schema{type: :string, description: "Peer endpoint address"},
        endpoint_port: %Schema{type: :string, description: "Peer endpoint port"},
        persistent_keepalive: %Schema{type: :string},
        last_handshake: %Schema{type: :string},
        rx: %Schema{type: :string, description: "Bytes received"},
        tx: %Schema{type: :string, description: "Bytes transmitted"},
        nodes: %Schema{type: :array, items: %Schema{type: :object}}
      }
    })
  end

  defmodule WireGuardKeypair do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "WireGuardKeypair",
      description: "WireGuard keypair",
      type: :object,
      properties: %{
        private_key: %Schema{type: :string, description: "Base64-encoded private key"},
        public_key: %Schema{type: :string, description: "Base64-encoded public key"}
      },
      example: %{
        "private_key" => "base64...",
        "public_key" => "base64..."
      }
    })
  end

  # RouterOS User schemas

  defmodule RouterOSUser do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RouterOSUser",
      description: "RouterOS user",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Username"},
        group: %Schema{type: :string, description: "User group"},
        comment: %Schema{type: :string, description: "Comment"},
        disabled: %Schema{type: :boolean},
        last_logged_in: %Schema{type: :string},
        nodes: %Schema{type: :array, items: %Schema{type: :object}}
      },
      example: %{
        "name" => "admin",
        "group" => "full",
        "disabled" => false
      }
    })
  end

  defmodule RouterOSUserCreateRequest do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "RouterOSUserCreateRequest",
      description: "Request to create a RouterOS user",
      type: :object,
      properties: %{
        name: %Schema{type: :string, description: "Username"},
        password: %Schema{type: :string, description: "Password"},
        group: %Schema{type: :string, description: "User group", default: "full"},
        comment: %Schema{type: :string, description: "Comment"}
      },
      required: [:name, :password],
      example: %{
        "name" => "newuser",
        "password" => "secret",
        "group" => "full"
      }
    })
  end

  # Audit schemas

  defmodule AuditLog do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AuditLog",
      description: "Audit log entry",
      type: :object,
      properties: %{
        id: %Schema{type: :integer, description: "Log ID"},
        action: %Schema{type: :string, description: "Action performed"},
        resource_type: %Schema{type: :string, description: "Resource type"},
        resource_id: %Schema{type: :integer, description: "Resource ID"},
        success: %Schema{type: :boolean, description: "Whether operation succeeded"},
        details: %Schema{type: :object, description: "Additional details"},
        ip_address: %Schema{type: :string, description: "Client IP address"},
        user: %Schema{
          type: :object,
          properties: %{
            id: %Schema{type: :integer},
            email: %Schema{type: :string}
          }
        },
        inserted_at: %Schema{type: :string, format: "date-time"}
      },
      example: %{
        "id" => 1,
        "action" => "create",
        "resource_type" => "dns_record",
        "success" => true,
        "inserted_at" => "2024-01-15T10:30:00Z"
      }
    })
  end

  defmodule AuditStats do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "AuditStats",
      description: "Audit log statistics",
      type: :object,
      properties: %{
        total: %Schema{type: :integer, description: "Total log entries"},
        today: %Schema{type: :integer, description: "Entries created today"}
      },
      example: %{
        "total" => 1250,
        "today" => 42
      }
    })
  end

  # Cluster schemas

  defmodule ClusterHealth do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ClusterHealth",
      description: "Cluster health information",
      type: :object,
      properties: %{
        nodes: %Schema{type: :object, description: "Health info per node"},
        summary: %Schema{
          type: :object,
          properties: %{
            total_nodes: %Schema{type: :integer},
            healthy_nodes: %Schema{type: :integer},
            unhealthy_nodes: %Schema{type: :integer}
          }
        }
      }
    })
  end

  defmodule ClusterStats do
    require OpenApiSpex

    OpenApiSpex.schema(%{
      title: "ClusterStats",
      description: "Cluster statistics",
      type: :object,
      properties: %{
        total_nodes: %Schema{type: :integer},
        active_nodes: %Schema{type: :integer},
        offline_nodes: %Schema{type: :integer}
      },
      example: %{
        "total_nodes" => 3,
        "active_nodes" => 3,
        "offline_nodes" => 0
      }
    })
  end
end
