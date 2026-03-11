defmodule JargaAdminWeb.Plugs.ChannelResolverTest do
  # async: false because tests mutate global Application config
  use ExUnit.Case, async: false

  import Plug.Test
  import Plug.Conn

  alias JargaAdminWeb.Plugs.ChannelResolver

  # Helper: run init then call (mirrors real plug pipeline)
  defp resolve(conn, opts \\ []) do
    opts = ChannelResolver.init(opts)
    ChannelResolver.call(conn, opts)
  end

  describe "init/1" do
    test "returns a map with strategy, default, and hostnames" do
      result = ChannelResolver.init(strategy: :hostname)

      assert is_map(result)
      assert result.strategy == :hostname
      assert is_binary(result.default)
      assert is_map(result.hostnames)
    end

    test "reads strategy from app config when not specified" do
      Application.put_env(:jarga_admin, :channel_strategy, :hostname)

      result = ChannelResolver.init([])

      assert result.strategy == :hostname

      Application.put_env(:jarga_admin, :channel_strategy, :single)
    end
  end

  describe "call/2 with :single strategy" do
    test "uses configured default channel" do
      Application.put_env(:jarga_admin, :default_channel, "my-store")

      conn = resolve(conn(:get, "/store"), strategy: :single)

      assert conn.assigns.channel_handle == "my-store"

      Application.put_env(:jarga_admin, :default_channel, "online-store")
    end

    test "falls back to online-store when no config" do
      Application.delete_env(:jarga_admin, :default_channel)

      conn = resolve(conn(:get, "/store"), strategy: :single)

      assert conn.assigns.channel_handle == "online-store"
    end
  end

  describe "call/2 with :hostname strategy" do
    test "resolves channel from hostname map" do
      Application.put_env(:jarga_admin, :channel_hostnames, %{
        "shop.example.com" => "online-store",
        "wholesale.example.com" => "b2b-portal"
      })

      conn =
        conn(:get, "/store")
        |> Map.put(:host, "wholesale.example.com")
        |> resolve(strategy: :hostname)

      assert conn.assigns.channel_handle == "b2b-portal"

      Application.put_env(:jarga_admin, :channel_hostnames, %{})
    end

    test "falls back to default channel for unknown hostname" do
      Application.put_env(:jarga_admin, :channel_hostnames, %{
        "shop.example.com" => "online-store"
      })

      Application.put_env(:jarga_admin, :default_channel, "fallback-store")

      conn =
        conn(:get, "/store")
        |> Map.put(:host, "unknown.example.com")
        |> resolve(strategy: :hostname)

      assert conn.assigns.channel_handle == "fallback-store"

      Application.put_env(:jarga_admin, :channel_hostnames, %{})
      Application.put_env(:jarga_admin, :default_channel, "online-store")
    end
  end

  describe "call/2 with :path_prefix strategy" do
    test "resolves channel from first path segment" do
      conn = resolve(conn(:get, "/b2b-portal/products"), strategy: :path_prefix)

      assert conn.assigns.channel_handle == "b2b-portal"
    end

    test "falls back to default channel for root path" do
      Application.delete_env(:jarga_admin, :default_channel)

      conn = resolve(conn(:get, "/"), strategy: :path_prefix)

      assert conn.assigns.channel_handle == "online-store"
    end
  end

  describe "call/2 defaults" do
    test "uses :single strategy when no strategy specified" do
      Application.delete_env(:jarga_admin, :default_channel)

      conn = resolve(conn(:get, "/store"))

      assert conn.assigns.channel_handle == "online-store"
    end
  end

  describe "channel handle validation" do
    test "sanitizes channel handle to alphanumeric and hyphens" do
      conn = resolve(conn(:get, "/evil;DROP TABLE/products"), strategy: :path_prefix)

      # Should strip invalid characters
      assert conn.assigns.channel_handle =~ ~r/\A[a-zA-Z0-9\-]+\z/
    end

    test "enforces max length on channel handle" do
      long_path = "/" <> String.duplicate("a", 200) <> "/products"
      conn = resolve(conn(:get, long_path), strategy: :path_prefix)

      assert byte_size(conn.assigns.channel_handle) <= 64
    end
  end

  describe "default_channel/0" do
    test "returns the configured default channel" do
      Application.put_env(:jarga_admin, :default_channel, "my-store")

      assert ChannelResolver.default_channel() == "my-store"

      Application.put_env(:jarga_admin, :default_channel, "online-store")
    end

    test "falls back to online-store" do
      Application.delete_env(:jarga_admin, :default_channel)

      assert ChannelResolver.default_channel() == "online-store"
    end
  end
end
