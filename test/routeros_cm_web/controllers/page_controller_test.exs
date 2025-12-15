defmodule RouterosCmWeb.PageControllerTest do
  use RouterosCmWeb.ConnCase

  test "GET /", %{conn: conn} do
    conn = get(conn, ~p"/")
    # Root path requires authentication, redirects to login
    assert redirected_to(conn) == ~p"/users/log-in"
  end
end
