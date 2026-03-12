defmodule JargaAdmin.MediaUploadTest do
  use ExUnit.Case

  alias JargaAdmin.MediaUpload

  setup do
    bypass = Bypass.open()
    original_url = Application.get_env(:jarga_admin, :api_url)
    Application.put_env(:jarga_admin, :api_url, "http://localhost:#{bypass.port}")

    on_exit(fn ->
      Application.put_env(:jarga_admin, :api_url, original_url)
    end)

    {:ok, bypass: bypass}
  end

  describe "request_upload_url/1" do
    test "returns upload URL and asset URL on success", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/pim/media/upload-url", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            data: %{
              upload_url: "https://storage.example.com/put/test.jpg",
              asset_url: "https://cdn.example.com/test.jpg",
              asset_key: "pim/media/test.jpg",
              http_method: "PUT"
            }
          })
        )
      end)

      assert {:ok, result} =
               MediaUpload.request_upload_url("test.jpg", "image/jpeg", 1024)

      assert result.upload_url == "https://storage.example.com/put/test.jpg"
      assert result.asset_url == "https://cdn.example.com/test.jpg"
      assert result.asset_key == "pim/media/test.jpg"
    end

    test "rejects non-image content types" do
      assert {:error, :invalid_content_type} =
               MediaUpload.request_upload_url("test.exe", "application/octet-stream", 1024)
    end

    test "rejects files over size limit" do
      assert {:error, :file_too_large} =
               MediaUpload.request_upload_url("large.jpg", "image/jpeg", 50_000_001)
    end

    test "validates filename" do
      assert {:error, :invalid_filename} =
               MediaUpload.request_upload_url("", "image/jpeg", 1024)
    end
  end

  describe "complete_upload/1" do
    test "completes a staged upload", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/pim/media/staged-uploads/complete", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          200,
          Jason.encode!(%{
            data: %{
              id: "media_123",
              url: "https://cdn.example.com/test.jpg",
              content_type: "image/jpeg"
            }
          })
        )
      end)

      assert {:ok, %{id: "media_123"}} =
               MediaUpload.complete_upload("pim/media/test.jpg")
    end
  end

  describe "attach_to_product/2" do
    test "attaches media to a product", %{bypass: bypass} do
      Bypass.expect_once(bypass, "POST", "/v1/pim/media/attach", fn conn ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(200, Jason.encode!(%{data: %{status: "attached"}}))
      end)

      assert {:ok, _} = MediaUpload.attach_to_product("media_123", "prod_1")
    end
  end

  describe "allowed_content_types/0" do
    test "returns a list of image MIME types" do
      types = MediaUpload.allowed_content_types()
      assert "image/jpeg" in types
      assert "image/png" in types
      assert "image/webp" in types
      refute "application/javascript" in types
    end
  end
end
