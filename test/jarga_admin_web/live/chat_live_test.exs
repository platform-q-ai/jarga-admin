defmodule JargaAdminWeb.ChatLiveTest do
  use JargaAdminWeb.ConnCase

  import Phoenix.LiveViewTest

  test "renders the chat interface", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")

    assert html =~ "JARGA"
    assert html =~ "chat-messages"
    assert html =~ "What would you like to do?"
  end

  test "shows suggestion buttons on empty chat", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")

    assert html =~ "Show me today&#39;s orders" or html =~ "Show me today's orders"
    assert html =~ "How are sales trending?"
  end

  test "renders tab bar with default tabs", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")

    assert html =~ "j-tab-bar"
    assert html =~ "Chat"
    assert html =~ "Dashboard"
  end

  test "can switch to dashboard tab", %{conn: conn} do
    {:ok, view, _html} = live(conn, "/chat")

    html = view |> element("[phx-value-id='dashboard']") |> render_click()
    assert html =~ "JARGA"
  end

  test "chat input form exists", %{conn: conn} do
    {:ok, _view, html} = live(conn, "/chat")

    assert html =~ "chat-form"
    assert html =~ "chat-input"
  end

  test "redirects / to /chat", %{conn: conn} do
    conn = get(conn, "/")
    assert redirected_to(conn) == "/chat"
  end
end
