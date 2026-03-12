defmodule JargaAdmin.PageRegistry do
  @moduledoc """
  Parses and manages the page registry — an ordered list of storefront pages
  with visibility and SEO metadata.

  The registry is stored as a Frontend API slot (`page_registry`) containing:

      %{
        "pages" => [
          %{"slug" => "home", "title" => "Home", "position" => 0,
           "show_in_nav" => false, "seo_priority" => "1.0"},
          ...
        ]
      }

  This module provides pure functions to parse, filter, and convert the
  registry data. It does NOT fetch from the API — callers are responsible
  for loading the slot data.
  """

  defstruct [:slug, :title, :position, :show_in_nav, :seo_priority]

  @type t :: %__MODULE__{
          slug: String.t(),
          title: String.t(),
          position: integer(),
          show_in_nav: boolean(),
          seo_priority: String.t()
        }

  @slug_re ~r/[^a-zA-Z0-9\-_\/]/

  @doc """
  Parses registry data (map or JSON string) into an ordered list of pages.

  Returns a list of `%PageRegistry{}` structs sorted by `position`.
  """
  @spec parse(map() | String.t() | nil) :: [t()]
  def parse(nil), do: []

  def parse(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, map} when is_map(map) -> parse(map)
      _ -> []
    end
  end

  def parse(%{"pages" => pages}) when is_list(pages) do
    pages
    |> Enum.map(&normalize_page/1)
    |> Enum.sort_by(& &1.position)
  end

  def parse(_), do: []

  @doc "Returns only pages where `show_in_nav` is true."
  @spec nav_pages([t()]) :: [t()]
  def nav_pages(pages) when is_list(pages) do
    Enum.filter(pages, & &1.show_in_nav)
  end

  @doc "Returns all pages (for sitemap generation)."
  @spec sitemap_pages([t()]) :: [t()]
  def sitemap_pages(pages) when is_list(pages), do: pages

  @doc """
  Converts nav pages to the link format used by the storefront nav bar.

  Returns a list of `%{"label" => "TITLE", "href" => "/store/slug"}` maps.
  """
  @spec nav_links([t()]) :: [map()]
  def nav_links(pages) when is_list(pages) do
    pages
    |> nav_pages()
    |> Enum.map(fn page ->
      %{
        "label" => String.upcase(page.title),
        "href" => page_href(page.slug)
      }
    end)
  end

  # ── Private ──────────────────────────────────────────────────────────────

  defp normalize_page(page) when is_map(page) do
    slug = sanitize_slug(page["slug"] || "")

    %__MODULE__{
      slug: slug,
      title: page["title"] || slug,
      position: parse_int(page["position"], 0),
      show_in_nav: page["show_in_nav"] == true,
      seo_priority: validate_priority(page["seo_priority"])
    }
  end

  defp sanitize_slug(slug) when is_binary(slug) do
    slug
    |> String.replace(~r/\.\./, "")
    |> then(&Regex.replace(@slug_re, &1, ""))
    |> String.replace(~r/\/+/, "/")
    |> String.trim_leading("/")
    |> String.trim_trailing("/")
  end

  defp sanitize_slug(_), do: ""

  defp parse_int(val, _default) when is_integer(val), do: val

  defp parse_int(val, default) when is_binary(val) do
    case Integer.parse(val) do
      {n, _} -> n
      _ -> default
    end
  end

  defp parse_int(_, default), do: default

  @valid_priorities ~w(0.0 0.1 0.2 0.3 0.4 0.5 0.6 0.7 0.8 0.9 1.0)

  defp validate_priority(p) when p in @valid_priorities, do: p
  defp validate_priority(_), do: "0.5"

  defp page_href("home"), do: "/store"
  defp page_href(slug), do: "/store/#{slug}"
end
