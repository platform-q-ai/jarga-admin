defmodule JargaAdminWeb.LiveHelpers do
  @moduledoc """
  Shared utility functions for LiveView modules.

  This module contains pure helper functions used by ChatLive and other
  LiveViews to reduce code duplication and centralise common patterns:

  - Toast notification management
  - Form parameter cleaning
  - API error message formatting
  """

  alias Phoenix.LiveView.Socket

  # ── Toast management ────────────────────────────────────────────────────────

  @doc """
  Push a toast notification onto the socket's `:toasts` assign.
  """
  @max_toasts 5

  def push_toast(%Socket{} = socket, kind, message)
      when kind in [:success, :error, :info, :warn] do
    toast = %{
      id: System.unique_integer([:positive]),
      kind: kind,
      message: message,
      inserted_at: DateTime.utc_now()
    }

    Phoenix.Component.update(socket, :toasts, fn toasts ->
      [toast | toasts]
      |> Enum.take(@max_toasts)
    end)
  end

  # ── Form parameters ─────────────────────────────────────────────────────────

  @doc """
  Remove internal form params (prefixed with `_`) and strip blank values.
  """
  def clean_form_params(params) do
    params
    |> Enum.reject(fn {k, v} -> String.starts_with?(k, "_") || v == "" end)
    |> Map.new()
  end

  # ── API error messages ──────────────────────────────────────────────────────

  @doc """
  Extract a human-readable error message from an API error response.
  Falls back to `default` when no specific message is found.
  """
  def api_error_message(%{body: %{"error" => %{"message" => msg}}}, _default)
      when is_binary(msg),
      do: msg

  def api_error_message(_err, default), do: default
end
