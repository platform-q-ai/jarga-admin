defmodule JargaAdmin.StyleValidator do
  @moduledoc """
  Validates per-component inline style maps from page specs.

  Accepts an allowlisted set of CSS properties with safe values (no injection).
  Converts validated style maps to inline CSS strings for use in HEEx templates.

  ## Property categories

  **Layout:** `background`, `padding`, `margin`, `max_width`, `gap`, `text_align`,
  `min_height`, `border_top`, `border_bottom`, `border_radius`

  **Typography:** `title_size`, `title_weight`, `title_color`, `title_spacing`,
  `text_color`, `text_size`

  **Card-level:** `card_background`, `card_padding`, `card_aspect_ratio`, `card_border`
  """

  # ── Allowlisted properties ──────────────────────────────────────────────

  # Properties that map directly to CSS (underscore → hyphen)
  @layout_properties ~w(
    background padding margin max_width gap text_align
    min_height border_top border_bottom border_radius
  )

  # Text body properties (color, size for body text)
  @text_properties ~w(text_color text_size)

  # Properties prefixed with title_ → map to font/color CSS on title elements
  @title_properties ~w(title_size title_weight title_color title_spacing)

  # Properties prefixed with card_ → map to CSS on card elements
  @card_properties ~w(card_background card_padding card_aspect_ratio card_border)

  @all_properties @layout_properties ++ @text_properties ++ @title_properties ++ @card_properties

  # ── Validation ──────────────────────────────────────────────────────────

  @valid_text_aligns ~w(left center right justify)

  # Maximum length for any single CSS value (prevents payload bloat)
  @max_value_length 256

  # Block dangerous CSS patterns
  @dangerous_patterns [
    ~r/;/,
    ~r/url\s*\(/i,
    ~r/expression\s*\(/i,
    ~r/javascript\s*:/i,
    ~r/@import/i,
    ~r/behavior\s*:/i,
    ~r/-moz-binding/i,
    ~r/var\s*\(/i,
    ~r/paint\s*\(/i,
    ~r/element\s*\(/i,
    ~r/env\s*\(/i,
    ~r/image-set\s*\(/i
  ]

  @doc """
  Validates a style map, keeping only allowlisted properties with safe values.

  Returns a map of validated `{property_name, value}` pairs.
  Returns an empty map for nil, non-map, or empty input.
  """
  def validate(nil), do: %{}
  def validate(style) when not is_map(style), do: %{}

  def validate(style) when is_map(style) do
    style
    |> Enum.filter(fn {key, value} ->
      key in @all_properties and is_binary(value) and value != "" and
        byte_size(value) <= @max_value_length and
        safe_value?(value) and valid_for_property?(key, value)
    end)
    |> Map.new()
  end

  defp safe_value?(value) do
    # Normalize CSS unicode escapes before checking patterns
    normalized = normalize_css_escapes(value)
    not Enum.any?(@dangerous_patterns, &Regex.match?(&1, normalized))
  end

  # CSS allows unicode escapes like \75 for 'u', \65 for 'e', etc.
  # An attacker could use \75rl(...) to bypass url() detection.
  # We normalize these before pattern matching.
  defp normalize_css_escapes(value) do
    value
    |> replace_unicode_escapes()
    |> String.replace(~r/\\(.)/, "\\1")
  end

  defp replace_unicode_escapes(value) do
    Regex.replace(~r/\\([0-9a-fA-F]{1,6})\s?/, value, fn _match, hex ->
      decode_css_hex(hex)
    end)
  end

  defp decode_css_hex(hex) do
    codepoint = String.to_integer(hex, 16)

    if codepoint > 0 and codepoint <= 0x10FFFF do
      <<codepoint::utf8>>
    else
      ""
    end
  rescue
    _ -> ""
  end

  defp valid_for_property?("text_align", value), do: value in @valid_text_aligns
  defp valid_for_property?(_key, _value), do: true

  # ── CSS Generation ──────────────────────────────────────────────────────

  @doc """
  Converts a validated style map to an inline CSS string.

  Only includes layout-level properties (background, padding, margin, etc.).
  Card and title properties are excluded — use `card_style/1` and `title_style/1`.

  Property names are converted from underscore to hyphen format.
  """
  def to_inline_style(nil), do: ""
  def to_inline_style(style) when style == %{}, do: ""

  @inline_properties @layout_properties ++ @text_properties

  @text_css_map %{
    "text_color" => "color",
    "text_size" => "font-size"
  }

  def to_inline_style(style) when is_map(style) do
    style
    |> Enum.filter(fn {key, _} -> key in @inline_properties end)
    |> Enum.map(fn {key, value} ->
      css_prop = Map.get(@text_css_map, key, to_css_prop(key))
      "#{css_prop}:#{value}"
    end)
    |> Enum.sort()
    |> Enum.join(";")
  end

  @doc """
  Extracts card-specific properties as an inline CSS string.

  Maps `card_background` → `background`, `card_padding` → `padding`, etc.
  """
  def card_style(nil), do: ""
  def card_style(style) when style == %{}, do: ""

  def card_style(style) when is_map(style) do
    style
    |> Enum.filter(fn {key, _} -> key in @card_properties end)
    |> Enum.map(fn {key, value} ->
      css_prop = key |> String.replace_prefix("card_", "") |> to_css_prop()
      "#{css_prop}:#{value}"
    end)
    |> Enum.sort()
    |> Enum.join(";")
  end

  @doc """
  Extracts title-specific properties as an inline CSS string.

  Maps `title_size` → `font-size`, `title_weight` → `font-weight`,
  `title_color` → `color`, `title_spacing` → `letter-spacing`.
  """
  def title_style(nil), do: ""
  def title_style(style) when style == %{}, do: ""

  @title_css_map %{
    "title_size" => "font-size",
    "title_weight" => "font-weight",
    "title_color" => "color",
    "title_spacing" => "letter-spacing"
  }

  def title_style(style) when is_map(style) do
    style
    |> Enum.filter(fn {key, _} -> key in @title_properties end)
    |> Enum.map(fn {key, value} ->
      css_prop = Map.get(@title_css_map, key, to_css_prop(key))
      "#{css_prop}:#{value}"
    end)
    |> Enum.sort()
    |> Enum.join(";")
  end

  # ── Value sanitizers ────────────────────────────────────────────────────

  @valid_dimension_pattern ~r/^\d+(\.\d+)?(px|rem|em|%|vw|vh|vmin|vmax|ch|ex)$/

  @doc """
  Sanitizes a CSS dimension value. Returns the value if valid, empty string otherwise.

  Valid: `"64px"`, `"2rem"`, `"50%"`, `"100vh"`, `"1.5em"`
  Invalid: anything containing `;`, `url(`, `expression(`, etc.
  """
  def sanitize_css_dimension(nil), do: ""
  def sanitize_css_dimension(""), do: ""

  def sanitize_css_dimension(value) when is_binary(value) do
    trimmed = String.trim(value)

    if Regex.match?(@valid_dimension_pattern, trimmed) do
      trimmed
    else
      ""
    end
  end

  def sanitize_css_dimension(_), do: ""

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp to_css_prop(key) do
    String.replace(key, "_", "-")
  end
end
