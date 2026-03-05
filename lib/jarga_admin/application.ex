defmodule JargaAdmin.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Initialise ETS tab store
    JargaAdmin.TabStore.init()

    children = [
      JargaAdminWeb.Telemetry,
      {DNSCluster, query: Application.get_env(:jarga_admin, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: JargaAdmin.PubSub},
      # Registry for Quecto bridge sessions
      {Registry, keys: :unique, name: JargaAdmin.Quecto.Registry},
      # Dynamic supervisor for per-session Quecto bridges
      {DynamicSupervisor, name: JargaAdmin.Quecto.Supervisor, strategy: :one_for_one},
      JargaAdminWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: JargaAdmin.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    JargaAdminWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
