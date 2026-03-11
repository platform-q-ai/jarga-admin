defmodule JargaAdminWeb.Plugs.ChannelResolverTest do
  use ExUnit.Case, async: true

  import Plug.Test
  import Plug.Conn

  alias JargaAdminWeb.Plugs.ChannelResolver

  describe "init/1" do
    test "passes options through" do
      assert ChannelResolver.init(strategy: :hostname) == [strategy: :hostname]
    end
  end

  describe "call/2 with :single strategy" do
    test "uses configured default channel" do
      Application.put_env(:jarga_admin, :default_channel, "my-store")

      conn =
        conn(:get, "/store")
        |> ChannelResolver.call(strategy: :single)

      assert conn.assigns.channel_handle == "my-store"

      Application.delete_env(:jarga_admin, :default_channel)
    end

    test "falls back to online-store when no config" do
      Application.delete_env(:jarga_admin, :default_channel)

      conn =
        conn(:get, "/store")
        |> ChannelResolver.call(strategy: :single)

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
        |> ChannelResolver.call(strategy: :hostname)

      assert conn.assigns.channel_handle == "b2b-portal"

      Application.delete_env(:jarga_admin, :channel_hostnames)
    end

    test "falls back to default channel for unknown hostname" do
      Application.put_env(:jarga_admin, :channel_hostnames, %{
        "shop.example.com" => "online-store"
      })

      Application.put_env(:jarga_admin, :default_channel, "fallback-store")

      conn =
        conn(:get, "/store")
        |> Map.put(:host, "unknown.example.com")
        |> ChannelResolver.call(strategy: :hostname)

      assert conn.assigns.channel_handle == "fallback-store"

      Application.delete_env(:jarga_admin, :channel_hostnames)
      Application.delete_env(:jarga_admin, :default_channel)
    end
  end

  describe "call/2 with :path_prefix strategy" do
    test "resolves channel from first path segment" do
      conn =
        conn(:get, "/b2b-portal/products")
        |> ChannelResolver.call(strategy: :path_prefix)

      assert conn.assigns.channel_handle == "b2b-portal"
    end

    test "falls back to default channel for root path" do
      Application.delete_env(:jarga_admin, :default_channel)

      conn =
        conn(:get, "/")
        |> ChannelResolver.call(strategy: :path_prefix)

      assert conn.assigns.channel_handle == "online-store"
    end
  end

  describe "call/2 defaults" do
    test "uses :single strategy when no strategy specified" do
      Application.delete_env(:jarga_admin, :default_channel)

      conn =
        conn(:get, "/store")
        |> ChannelResolver.call([])

      assert conn.assigns.channel_handle == "online-store"
    end
  end

  describe "channel handle validation" do
    test "sanitizes channel handle to alphanumeric and hyphens" do
      conn =
        conn(:get, "/evil;DROP TABLE/products")
        |> ChannelResolver.call(strategy: :path_prefix)

      # Should strip invalid characters
      assert conn.assigns.channel_handle =~ ~r/\A[a-zA-Z0-9\-]+\z/
    end
  end
end
