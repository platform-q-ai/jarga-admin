defmodule JargaAdmin.StorefrontNav do
  @moduledoc """
  Parses and validates navigation data from the `storefront_nav` API slot.

  Supports nested children (max 1 level), highlight flags, and href
  sanitisation. Falls back gracefully on invalid data.

  ## Slot format

      %{
        "items" => [
          %{
            "label" => "BEDROOM",
            "href" => "/store/bedroom",
            "highlight" => false,
            "children" => [
              %{"label" => "Bedding", "href" => "/store/bedroom?c=bedding"},
              ...
            ]
          },
          ...
        ]
      }
  """

  @max_label_length 100

  @doc """
  Parses navigation data (map or JSON string) into a list of sanitised
  nav items. Supports nested `children` (max 1 level deep).
  """
  @spec parse(map() | String.t() | nil) :: [map()]
  def parse(nil), do: []

  def parse(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, map} when is_map(map) -> parse(map)
      _ -> []
    end
  end

  def parse(%{"items" => items}) when is_list(items) do
    Enum.map(items, &normalize_item(&1, _depth = 0))
  end

  def parse(_), do: []

  @doc "Returns true if a nav item has 4+ children (triggers mega-menu layout)."
  @spec mega_menu?(map()) :: boolean()
  def mega_menu?(%{"children" => children}) when is_list(children), do: length(children) >= 4
  def mega_menu?(_), do: false

  # ── Private ──────────────────────────────────────────────────────────────

  defp normalize_item(item, depth) when is_map(item) do
    base = %{
      "label" => item["label"] |> to_string() |> String.slice(0, @max_label_length),
      "href" => sanitize_href(item["href"]),
      "highlight" => item["highlight"] == true
    }

    if depth == 0 and is_list(item["children"]) do
      children =
        item["children"]
        |> Enum.map(&normalize_item(&1, 1))

      Map.put(base, "children", children)
    else
      base
    end
  end

  defp normalize_item(_, _depth), do: %{"label" => "", "href" => "#", "highlight" => false}

  @safe_href_re ~r/\A(\/[a-zA-Z0-9\-_\/\.\?=&%#]*|https?:\/\/)/

  defp sanitize_href(href) when is_binary(href) do
    if Regex.match?(@safe_href_re, href), do: href, else: "#"
  end

  defp sanitize_href(_), do: "#"
end
