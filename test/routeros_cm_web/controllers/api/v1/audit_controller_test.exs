defmodule RouterosCmWeb.API.V1.AuditControllerTest do
  use RouterosCmWeb.ConnCase

  import RouterosCm.AccountsFixtures

  alias RouterosCm.{ApiAuth, Audit}

  setup %{conn: conn} do
    user = user_fixture()

    {:ok, token} =
      ApiAuth.create_token_for_user(user, %{
        name: "Test Token",
        scopes: ["audit:read"]
      })

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("authorization", "Bearer #{token.token}")

    %{conn: conn, api_token: token, user: user}
  end

  describe "authentication" do
    test "returns 401 without auth token", %{conn: conn} do
      conn =
        conn
        |> delete_req_header("authorization")
        |> get(~p"/api/v1/audit")

      assert %{"error" => %{"code" => "unauthorized"}} = json_response(conn, 401)
    end

    test "returns 403 without audit:read scope" do
      {:ok, wrong_scope_token} =
        ApiAuth.create_token(%{
          name: "DNS Only Token",
          scopes: ["dns:read"]
        })

      conn =
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer #{wrong_scope_token.token}")
        |> get(~p"/api/v1/audit")

      assert %{"error" => %{"code" => "forbidden"}} = json_response(conn, 403)
    end
  end

  describe "index" do
    test "returns list of audit logs", %{conn: conn, user: user} do
      # Create some audit logs
      Audit.log_success("test_action", "test_resource", %{user_id: user.id})
      Audit.log_success("another_action", "test_resource", %{user_id: user.id})

      conn = get(conn, ~p"/api/v1/audit")

      assert %{"data" => logs, "meta" => meta} = json_response(conn, 200)
      assert is_list(logs)
      assert length(logs) >= 2
      assert is_integer(meta["total"])
      assert is_integer(meta["page"])
      assert is_integer(meta["per_page"])
    end

    test "supports pagination", %{conn: conn, user: user} do
      # Create some audit logs
      for i <- 1..5 do
        Audit.log_success("action_#{i}", "test_resource", %{user_id: user.id})
      end

      conn = get(conn, ~p"/api/v1/audit?page=1&per_page=2")

      assert %{"data" => logs, "meta" => meta} = json_response(conn, 200)
      assert length(logs) == 2
      assert meta["page"] == 1
      assert meta["per_page"] == 2
    end

    test "supports action filter", %{conn: conn, user: user} do
      Audit.log_success("create", "dns_record", %{user_id: user.id})
      Audit.log_success("delete", "dns_record", %{user_id: user.id})

      conn = get(conn, ~p"/api/v1/audit?action=create")

      assert %{"data" => logs} = json_response(conn, 200)
      assert Enum.all?(logs, &(&1["action"] == "create"))
    end

    test "supports resource_type filter", %{conn: conn, user: user} do
      Audit.log_success("create", "dns_record", %{user_id: user.id})
      Audit.log_success("create", "wireguard_interface", %{user_id: user.id})

      conn = get(conn, ~p"/api/v1/audit?resource_type=dns_record")

      assert %{"data" => logs} = json_response(conn, 200)
      assert Enum.all?(logs, &(&1["resource_type"] == "dns_record"))
    end

    test "supports success filter", %{conn: conn, user: user} do
      Audit.log_success("create", "dns_record", %{user_id: user.id})
      Audit.log_failure("create", "dns_record", "test error", %{user_id: user.id})

      conn = get(conn, ~p"/api/v1/audit?success=true")

      assert %{"data" => logs} = json_response(conn, 200)
      assert Enum.all?(logs, &(&1["success"] == true))
    end
  end

  describe "show" do
    test "returns a specific audit log", %{conn: conn, user: user} do
      {:ok, log} = Audit.log_success("test_show", "test_resource", %{user_id: user.id})

      conn = get(conn, ~p"/api/v1/audit/#{log.id}")

      assert %{"data" => data} = json_response(conn, 200)
      assert data["id"] == log.id
      assert data["action"] == "test_show"
      assert data["resource_type"] == "test_resource"
    end

    test "returns 404 for non-existent log", %{conn: conn} do
      conn = get(conn, ~p"/api/v1/audit/999999")

      assert %{"error" => %{"code" => "not_found"}} = json_response(conn, 404)
    end
  end

  describe "stats" do
    test "returns audit statistics", %{conn: conn, user: user} do
      # Create an audit log to ensure stats are non-zero
      Audit.log_success("test_stats", "test_resource", %{user_id: user.id})

      conn = get(conn, ~p"/api/v1/audit/stats")

      assert %{"data" => stats} = json_response(conn, 200)
      assert is_integer(stats["total"])
      assert stats["total"] >= 1
      assert is_integer(stats["today"])
    end
  end
end
