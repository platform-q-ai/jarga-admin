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
  # Uses reduce_while to short-circuit on first non-matching term.
  defp score(product, terms) do
    searchable = build_searchable(product)

    Enum.reduce_while(terms, 0, fn term, acc ->
      case score_term(searchable, term) do
        0 -> {:halt, 0}
        s -> {:cont, acc + s}
      end
    end)
  end

  # Score a single term against searchable fields. Title/name matches
  # score 10, other fields score 1. Uses a single `rest` string to minimize
  # String.contains? calls.
  defp score_term(searchable, term) do
    title_match =
      if String.contains?(searchable.title, term) or
           String.contains?(searchable.name, term),
         do: 10,
         else: 0

    other_match =
      if String.contains?(searchable.rest, term), do: 1, else: 0

    title_match + other_match
  end

  # Build a map of lowercased searchable strings from a product.
  # The `rest` field concatenates all non-title fields into a single string
  # for efficient matching with one String.contains? call.
  defp build_searchable(product) when is_map(product) do
    rest =
      [
        product["description_html"] |> strip_html(),
        product["tags"] |> normalize_tags(),
        product["vendor"],
        product["product_type"]
      ]
      |> Enum.map_join(" ", &downcase/1)

    %{
      title: downcase(product["title"]),
      name: downcase(product["name"]),
      rest: rest
    }
  end

  defp downcase(nil), do: ""
  defp downcase(s) when is_binary(s), do: String.downcase(s)
  defp downcase(_), do: ""

  defp strip_html(nil), do: ""

  # NOTE: strips HTML tags only — does not decode HTML entities.
  # Safe for search matching; do NOT reuse for rendering to clients.
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
