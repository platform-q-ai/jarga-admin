defmodule JargaAdminWeb.MediaLibraryLive do
  @moduledoc """
  Admin LiveView for uploading and browsing media.

  Supports drag-and-drop image upload via LiveView uploads. Uploaded images
  are sent through the MediaUpload pipeline: request pre-signed URL → upload
  to storage → complete upload → display CDN URL.

  ## Usage

  Mount at `/admin/media` or equivalent admin route.
  """
  use JargaAdminWeb, :live_view

  alias JargaAdmin.MediaUpload

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:page_title, "Media Library")
     |> stream(:uploaded_media, [])
     |> assign(:upload_error, nil)
     |> allow_upload(:media,
       accept: MediaUpload.allowed_content_types(),
       max_entries: 5,
       max_file_size: 50_000_000,
       auto_upload: false
     )}
  end

  @impl true
  def handle_event("validate", _params, socket) do
    {:noreply, socket}
  end

  @impl true
  def handle_event("cancel-upload", %{"ref" => ref}, socket) do
    {:noreply, cancel_upload(socket, :media, ref)}
  end

  @impl true
  def handle_event("upload", _params, socket) do
    uploaded_files =
      consume_uploaded_entries(socket, :media, fn %{path: path}, entry ->
        result = process_upload(path, entry)
        {:ok, result}
      end)

    {successful, errors} =
      Enum.split_with(uploaded_files, fn
        {:ok, _} -> true
        _ -> false
      end)

    successful = Enum.map(successful, fn {:ok, data} -> data end)

    error_msg =
      case errors do
        [] -> nil
        errs -> "#{length(errs)} upload(s) failed"
      end

    {:noreply,
     socket
     |> stream(:uploaded_media, successful)
     |> assign(:upload_error, error_msg)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <div class="max-w-4xl mx-auto py-8 px-4">
        <h1 class="text-2xl font-semibold mb-6">Media Library</h1>

        <form id="upload-form" phx-submit="upload" phx-change="validate" class="mb-8">
          <div
            class="border-2 border-dashed border-gray-300 rounded-lg p-8 text-center"
            phx-drop-target={@uploads.media.ref}
          >
            <p class="text-gray-500 mb-4">Drag and drop images here, or click to browse</p>
            <.live_file_input upload={@uploads.media} class="mb-4" />
          </div>

          <%= for entry <- @uploads.media.entries do %>
            <div class="flex items-center gap-4 mt-4 p-3 bg-gray-50 rounded">
              <.live_img_preview entry={entry} class="w-16 h-16 object-cover rounded" />
              <div class="flex-1">
                <p class="text-sm font-medium">{entry.client_name}</p>
                <div class="w-full bg-gray-200 rounded-full h-2 mt-1">
                  <div class="bg-black h-2 rounded-full" style={"width: #{entry.progress}%"}></div>
                </div>
              </div>
              <button
                type="button"
                phx-click="cancel-upload"
                phx-value-ref={entry.ref}
                class="text-red-500 text-sm"
              >
                Cancel
              </button>
            </div>
          <% end %>

          <button
            :if={@uploads.media.entries != []}
            type="submit"
            class="mt-4 px-6 py-2 bg-black text-white rounded hover:bg-gray-800"
          >
            Upload {length(@uploads.media.entries)} file(s)
          </button>
        </form>

        <div :if={@upload_error} class="bg-red-50 text-red-700 p-3 rounded mb-4">
          {@upload_error}
        </div>

        <div id="uploaded-media" phx-update="stream" class="space-y-3">
          <div class="hidden only:block text-gray-400 text-sm">No uploads yet</div>
          <div
            :for={{dom_id, upload} <- @streams.uploaded_media}
            id={dom_id}
            class="flex items-center gap-4 p-3 bg-green-50 rounded"
          >
            <div class="flex-1">
              <p class="text-sm font-medium">{upload.filename}</p>
              <p class="text-xs text-gray-500 font-mono">{upload.asset_url}</p>
            </div>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp process_upload(path, entry) do
    byte_size = File.stat!(path).size

    case MediaUpload.request_upload_url(
           entry.client_name,
           entry.client_type,
           byte_size
         ) do
      {:ok, %{upload_url: upload_url, asset_url: asset_url, asset_key: asset_key}} ->
        # Upload file to pre-signed URL
        case MediaUpload.upload_to_storage(File.read!(path), upload_url, entry.client_type) do
          :ok ->
            # Complete the upload
            case MediaUpload.complete_upload(asset_key) do
              {:ok, %{id: id}} ->
                {:ok,
                 %{
                   id: id,
                   filename: entry.client_name,
                   asset_url: asset_url
                 }}

              {:error, reason} ->
                {:error, reason}
            end

          {:error, reason} ->
            {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

end
