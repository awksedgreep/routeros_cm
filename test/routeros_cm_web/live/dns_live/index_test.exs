defmodule RouterosCmWeb.DNSLive.IndexTest do
  use RouterosCmWeb.ConnCase

  import Phoenix.LiveViewTest

  describe "DNS Index page (authenticated)" do
    setup :register_and_log_in_user

    test "displays dns page", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dns")

      assert html =~ "DNS Records"
    end

    test "shows new record form", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/dns/new")

      # Check for any form element
      assert has_element?(view, "form")
    end
  end

  describe "DNS Index page (unauthenticated)" do
    test "redirects to login", %{conn: conn} do
      assert {:error, {:redirect, %{to: path}}} = live(conn, ~p"/dns")
      assert path == ~p"/users/log-in"
    end
  end
end
