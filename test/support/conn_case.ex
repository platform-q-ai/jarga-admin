defmodule JargaAdminWeb.ConnCase do
  @moduledoc """
  This module defines the test case to be used by
  tests that require setting up a connection.

  Such tests rely on `Phoenix.ConnTest` and also
  import other functionality to make it easier
  to build common data structures and query the data layer.

  Finally, if the test case interacts with the database,
  we enable the SQL sandbox, so changes done to the database
  are reverted at the end of every test. If you are using
  PostgreSQL, you can even run database tests asynchronously
  by setting `use JargaAdminWeb.ConnCase, async: true`, although
  this option is not recommended for other databases.
  """

  use ExUnit.CaseTemplate

  using do
    quote do
      # The default endpoint for testing
      @endpoint JargaAdminWeb.Endpoint

      use JargaAdminWeb, :verified_routes

      # Import conveniences for testing with connections
      import Plug.Conn
      import Phoenix.ConnTest
      import JargaAdminWeb.ConnCase
    end
  end

  setup _tags do
    # Invalidate all cached tab specs to prevent stale Bypass state from
    # a prior test leaking into the next one via TabStore's ETS cache.
    JargaAdmin.TabStore.invalidate_all_specs()
    # Clear the API URL so tests that don't set up Bypass don't accidentally
    # hit a prior test's Bypass instance.
    Application.delete_env(:jarga_admin, :api_url)
    {:ok, conn: Phoenix.ConnTest.build_conn()}
  end
end
