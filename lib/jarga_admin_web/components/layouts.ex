defmodule JargaAdminWeb.Layouts do
  @moduledoc """
  Layouts for Jarga Admin — cinematic design system.
  """
  use JargaAdminWeb, :html

  embed_templates "layouts/*"

  @doc """
  Flash group for LiveView pages.
  """
  attr :flash, :map, required: true
  attr :id, :string, default: "flash-group"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite" class="j-toast-container">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />
    </div>
    """
  end
end
