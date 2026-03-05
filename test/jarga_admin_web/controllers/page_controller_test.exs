defmodule JargaAdminWeb.PageControllerTest do
  use JargaAdminWeb.ConnCase

  test "GET / redirects to /chat", %{conn: conn} do
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/chat"
  end
end
