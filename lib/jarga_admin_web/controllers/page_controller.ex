defmodule JargaAdminWeb.PageController do
  use JargaAdminWeb, :controller

  def home(conn, _params) do
    redirect(conn, to: ~p"/chat")
  end
end
