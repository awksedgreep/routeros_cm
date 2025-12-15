defmodule RouterosCmWeb.ErrorJSONTest do
  use RouterosCmWeb.ConnCase, async: true

  test "renders 404" do
    assert RouterosCmWeb.ErrorJSON.render("404.json", %{}) ==
             %{error: %{code: "not_found", message: "Resource not found"}}
  end

  test "renders 404 with resource" do
    assert RouterosCmWeb.ErrorJSON.render("404.json", %{resource: "Node"}) ==
             %{error: %{code: "not_found", message: "Node not found"}}
  end

  test "renders 500" do
    assert RouterosCmWeb.ErrorJSON.render("500.json", %{}) ==
             %{error: %{code: "internal_error", message: "An unexpected error occurred"}}
  end

  test "renders 401" do
    assert RouterosCmWeb.ErrorJSON.render("401.json", %{}) ==
             %{error: %{code: "unauthorized", message: "Invalid or missing API token"}}
  end

  test "renders 403 with scope" do
    assert RouterosCmWeb.ErrorJSON.render("403.json", %{scope: "dns:write"}) ==
             %{error: %{code: "forbidden", message: "Token lacks required scope: dns:write"}}
  end
end
