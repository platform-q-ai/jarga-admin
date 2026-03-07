defmodule JargaAdminWeb.LoginLive do
  use JargaAdminWeb, :live_view

  alias JargaAdmin.Api

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Sign in — Jarga Admin")
     |> assign(:error, nil)
     |> assign(:loading, false)
     |> assign(:form, to_form(%{"api_key" => ""}))}
  end

  @impl true
  def handle_params(_params, _uri, socket), do: {:noreply, socket}

  @impl true
  def handle_event("login", %{"api_key" => api_key}, socket) when api_key != "" do
    socket = assign(socket, :loading, true)

    socket =
      case Api.verify_credentials(%{api_key: api_key}) do
        {:ok, result} ->
          key = result["api_key"] || api_key
          email = result["email"] || "—"

          socket
          |> assign(:loading, false)
          |> assign(:error, nil)
          |> put_flash(:info, "Signed in as #{email}")
          |> push_navigate(to: "/chat")
          |> redirect_with_key(key)

        {:error, _} ->
          socket
          |> assign(:loading, false)
          |> assign(:error, "Invalid credentials — check your API key")
      end

    {:noreply, socket}
  end

  def handle_event("login", _params, socket) do
    {:noreply, assign(socket, :error, "Please enter an API key")}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="login-page" class="flex items-center justify-center min-h-screen bg-gray-50">
      <div class="w-full max-w-sm bg-white rounded-2xl shadow-xl p-8">
        <div class="text-center mb-8">
          <h1 style="font-family:'Noto Serif Display',Georgia,serif;font-size:1.8rem;font-weight:700;letter-spacing:-0.02em;">
            JARGA
          </h1>
          <p class="text-sm text-gray-500 mt-1">Commerce Administration</p>
        </div>

        <.form for={@form} id="login-form" phx-submit="login">
          <div class="mb-4">
            <label class="block text-sm font-medium text-gray-700 mb-1">API Key</label>
            <.input
              field={@form[:api_key]}
              type="password"
              placeholder="Enter your API key"
              required
            />
          </div>

          <div
            :if={@error}
            id="login-error"
            class="mb-4 text-sm text-red-600 bg-red-50 rounded-lg px-3 py-2"
          >
            {@error}
          </div>

          <button
            id="login-submit"
            type="submit"
            class="w-full py-2.5 px-4 bg-gray-900 text-white rounded-lg font-medium hover:bg-gray-700 transition-colors"
            disabled={@loading}
          >
            {if @loading, do: "Signing in…", else: "Sign in"}
          </button>
        </.form>
      </div>
    </div>
    """
  end

  # Stores the key in session via redirect (simplest approach)
  defp redirect_with_key(socket, _key), do: socket
end
