defmodule RouterosCmWeb.NodeLive.IndexTest do
  use RouterosCmWeb.ConnCase

  @moduletag :integration

  import Phoenix.LiveViewTest

  describe "Node Index page (authenticated)" do
    setup :register_and_log_in_user

    test "displays nodes page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/nodes")

      assert html =~ "Cluster Nodes"
    end

    test "shows new node modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/nodes/new")

      assert has_element?(view, "#node-modal")
    end
  end

  describe "Node Index page (unauthenticated)" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/nodes")
      assert path == ~p"/users/log-in"
    end
  end
end
