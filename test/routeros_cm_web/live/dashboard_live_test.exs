defmodule RouterosCmWeb.DashboardLiveTest do
  use RouterosCmWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "Dashboard page (authenticated)" do
    setup :register_and_log_in_user

    test "displays dashboard content", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "Overview of your RouterOS cluster"
      assert html =~ "Total Nodes"
    end

    test "shows empty state when no nodes exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "No nodes"
    end
  end

  describe "Dashboard page (unauthenticated)" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/")
      assert path == ~p"/users/log-in"
    end
  end
end
