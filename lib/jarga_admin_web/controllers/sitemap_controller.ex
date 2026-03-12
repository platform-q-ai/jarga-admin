defmodule JargaAdminWeb.SitemapController do
  @moduledoc """
  Serves `/store/sitemap.xml` and `/robots.txt` for SEO.

  The sitemap is generated from the `page_registry` Frontend API slot.
  """
  use JargaAdminWeb, :controller

  alias JargaAdmin.Api
  alias JargaAdmin.PageRegistry

  @doc "GET /store/sitemap.xml"
  def sitemap(conn, _params) do
    pages = load_registry_pages()
    sitemap_pages = PageRegistry.sitemap_pages(pages)

    base_url =
      JargaAdminWeb.Endpoint.url()
      |> String.trim_trailing("/")

    xml = build_sitemap_xml(sitemap_pages, base_url)

    conn
    |> put_resp_content_type("application/xml")
    |> send_resp(200, xml)
  end

  @doc "GET /robots.txt"
  def robots(conn, _params) do
    base_url =
      JargaAdminWeb.Endpoint.url()
      |> String.trim_trailing("/")

    body = """
    User-agent: *
    Allow: /store/
    Disallow: /admin/

    Sitemap: #{base_url}/store/sitemap.xml
    """

    conn
    |> put_resp_content_type("text/plain")
    |> send_resp(200, body)
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp load_registry_pages do
    case Api.get_storefront_slot("page_registry") do
      {:ok, %{"payload_json" => payload}} when is_binary(payload) ->
        case Jason.decode(payload) do
          {:ok, data} -> PageRegistry.parse(data)
          _ -> []
        end

      {:ok, %{"payload_json" => payload}} when is_map(payload) ->
        PageRegistry.parse(payload)

      _ ->
        []
    end
  end

  defp build_sitemap_xml(pages, base_url) do
    urls =
      Enum.map_join(pages, "\n", fn page ->
        loc = page_url(page.slug, base_url)

        """
          <url>
            <loc>#{loc}</loc>
            <priority>#{page.seo_priority}</priority>
            <changefreq>weekly</changefreq>
          </url>\
        """
      end)

    """
    <?xml version="1.0" encoding="UTF-8"?>
    <urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
    #{urls}
    </urlset>
    """
  end

  defp page_url("home", base_url), do: "#{base_url}/store"
  defp page_url(slug, base_url), do: "#{base_url}/store/#{slug}"
end
