defmodule JargaAdmin.MediaUpload do
  @moduledoc """
  Orchestrates the staged media upload pipeline.

  Upload flow:
  1. `request_upload_url/3` — get pre-signed upload URL from Commerce API
  2. Client uploads file directly to the storage URL (PUT)
  3. `complete_upload/1` — finalise the upload, get a permanent media record
  4. `attach_to_product/2` — (optional) link media to a PIM product

  ## Content type restrictions

  Only image types are accepted: JPEG, PNG, WebP, GIF, SVG, AVIF.

  ## Size limit

  Maximum file size: 50 MB.
  """

  alias JargaAdmin.Api

  @max_file_size 50_000_000
  @allowed_types ~w(image/jpeg image/png image/webp image/gif image/svg+xml image/avif)

  @doc "Returns the list of allowed image MIME types."
  @spec allowed_content_types() :: [String.t()]
  def allowed_content_types, do: @allowed_types

  @doc """
  Requests a pre-signed upload URL from the Commerce API.

  Returns `{:ok, %{upload_url, asset_url, asset_key, http_method}}` on success.

  ## Validations

  - `content_type` must be an allowed image type
  - `byte_size` must be <= 50 MB
  - `filename` must be non-empty
  """
  @spec request_upload_url(String.t(), String.t(), non_neg_integer()) ::
          {:ok, map()} | {:error, atom()}
  def request_upload_url(filename, content_type, byte_size) do
    with :ok <- validate_filename(filename),
         :ok <- validate_content_type(content_type),
         :ok <- validate_size(byte_size) do
      case Api.get_upload_url(%{
             "filename" => sanitize_filename(filename),
             "content_type" => content_type,
             "byte_size" => byte_size
           }) do
        {:ok, %{"upload_url" => upload_url} = data} ->
          {:ok,
           %{
             upload_url: upload_url,
             asset_url: data["asset_url"],
             asset_key: data["asset_key"],
             http_method: data["http_method"] || "PUT"
           }}

        {:error, reason} ->
          {:error, reason}

        _ ->
          {:error, :api_error}
      end
    end
  end

  @doc """
  Completes a staged upload, creating a permanent media record.

  `asset_key` is the key returned by `request_upload_url/3`.
  """
  @spec complete_upload(String.t()) :: {:ok, map()} | {:error, any()}
  def complete_upload(asset_key) when is_binary(asset_key) do
    case Api.complete_upload(%{"asset_key" => asset_key}) do
      {:ok, data} when is_map(data) ->
        {:ok, %{id: data["id"], url: data["url"], content_type: data["content_type"]}}

      {:error, reason} ->
        {:error, reason}

      _ ->
        {:error, :api_error}
    end
  end

  @doc """
  Attaches a media record to a PIM product.
  """
  @spec attach_to_product(String.t(), String.t()) :: {:ok, map()} | {:error, any()}
  def attach_to_product(media_id, product_id)
      when is_binary(media_id) and is_binary(product_id) do
    case Api.attach_media(%{"media_id" => media_id, "product_id" => product_id}) do
      {:ok, data} -> {:ok, data}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :api_error}
    end
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp validate_filename(""), do: {:error, :invalid_filename}
  defp validate_filename(f) when is_binary(f) and byte_size(f) > 0, do: :ok
  defp validate_filename(_), do: {:error, :invalid_filename}

  defp validate_content_type(type) when type in @allowed_types, do: :ok
  defp validate_content_type(_), do: {:error, :invalid_content_type}

  defp validate_size(size) when is_integer(size) and size > 0 and size <= @max_file_size, do: :ok
  defp validate_size(_), do: {:error, :file_too_large}

  @doc """
  Uploads file data to a pre-signed storage URL.

  Returns `:ok` on success, `{:error, reason}` on failure.
  """
  @spec upload_to_storage(binary(), String.t(), String.t()) :: :ok | {:error, any()}
  def upload_to_storage(body, upload_url, content_type) when is_binary(body) do
    case Req.put(upload_url,
           body: body,
           headers: [{"content-type", content_type}],
           receive_timeout: 120_000
         ) do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      {:ok, resp} -> {:error, {:upload_failed, resp.status}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp sanitize_filename(filename) do
    filename
    |> Path.basename()
    |> String.replace(~r/[^a-zA-Z0-9._-]/, "_")
    |> String.slice(0, 255)
  end
end
