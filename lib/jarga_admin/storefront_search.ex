defmodule JargaAdmin.StorefrontSearch do
  @moduledoc """
  Client-side product search filtering.

  The PIM API currently ignores the `search` query parameter and returns all
  products. This module provides in-memory filtering as a workaround until
  the API implements full-text search.

  Search is multi-field (title, name, description, tags, vendor, product_type)
  and multi-word (all terms must match). Results are ranked with title matches
  scored higher than other field matches.

  ## Usage

      products = Api.list_products(%{"search" => query, "limit" => "50"})
      filtered = StorefrontSearch.filter(products, query, limit: 12)

  When the API starts filtering correctly, this module can be removed and the
  caller can use the API results directly.
  """

  @doc """
  Filters a list of PIM products by a search query.

  Matches against: `title`, `name`, `description_html` (HTML stripped),
  `tags`, `vendor`, `product_type`.

  Multi-word queries require ALL terms to match (AND logic).
  Results are ranked by relevance: title/name matches score higher.

  ## Options

    * `:limit` — maximum number of results to return (default: no limit)

  """
  @spec filter(list() | nil, String.t() | nil, keyword()) :: list()
  def filter(products, query, opts \\ [])

  def filter(nil, _query, _opts), do: []
  def filter([], _query, _opts), do: []
  def filter(products, nil, _opts), do: products
  def filter(products, "", _opts), do: products

  def filter(products, query, opts) when is_list(products) and is_binary(query) do
    terms =
      query
      |> String.downcase()
      |> String.split(~r/\s+/, trim: true)

    products
    |> Enum.map(fn product -> {product, score(product, terms)} end)
    |> Enum.filter(fn {_product, score} -> score > 0 end)
    |> Enum.sort_by(fn {_product, score} -> score end, :desc)
    |> then(fn results ->
      case Keyword.get(opts, :limit) do
        nil -> results
        limit when is_integer(limit) and limit > 0 -> Enum.take(results, limit)
        _ -> results
      end
    end)
    |> Enum.map(fn {product, _score} -> product end)
  end

  # ── Scoring ──────────────────────────────────────────────────────────────

  # Score a product against search terms. Returns 0 if any term doesn't match.
  defp score(product, terms) do
    searchable = build_searchable(product)

    term_scores =
      Enum.map(terms, fn term ->
        score_term(searchable, term)
      end)

    if Enum.all?(term_scores, &(&1 > 0)) do
      Enum.sum(term_scores)
    else
      0
    end
  end

  # Score a single term against searchable fields. Title/name matches
  # score 10, other fields score 1.
  defp score_term(searchable, term) do
    title_match =
      if String.contains?(searchable.title, term) or
           String.contains?(searchable.name, term),
         do: 10,
         else: 0

    other_match =
      if String.contains?(searchable.tags, term) or
           String.contains?(searchable.vendor, term) or
           String.contains?(searchable.product_type, term) or
           String.contains?(searchable.description, term),
         do: 1,
         else: 0

    title_match + other_match
  end

  # Build a map of lowercased searchable strings from a product.
  defp build_searchable(product) when is_map(product) do
    %{
      title: downcase(product["title"]),
      name: downcase(product["name"]),
      description: product["description_html"] |> strip_html() |> downcase(),
      tags: product["tags"] |> normalize_tags() |> downcase(),
      vendor: downcase(product["vendor"]),
      product_type: downcase(product["product_type"])
    }
  end

  defp downcase(nil), do: ""
  defp downcase(s) when is_binary(s), do: String.downcase(s)
  defp downcase(_), do: ""

  defp strip_html(nil), do: ""

  defp strip_html(html) when is_binary(html) do
    html
    |> String.replace(~r/<[^>]+>/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.trim()
  end

  defp normalize_tags(nil), do: ""
  defp normalize_tags(tags) when is_list(tags), do: Enum.join(tags, " ")
  defp normalize_tags(_), do: ""
end
