defmodule RouterosCmWeb.WireGuardLive.IndexTest do
  use RouterosCmWeb.ConnCase

  @moduletag :integration

  import Phoenix.LiveViewTest

  describe "WireGuard Index page (authenticated)" do
    setup :register_and_log_in_user

    test "displays wireguard page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/wireguard")

      assert html =~ "WireGuard Interfaces"
    end

    test "shows new interface form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/wireguard/new")

      assert has_element?(view, "#interface-form")
    end
  end

  describe "WireGuard Index page (unauthenticated)" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/wireguard")
      assert path == ~p"/users/log-in"
    end
  end
end
