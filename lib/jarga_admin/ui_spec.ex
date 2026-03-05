defmodule JargaAdmin.UiSpec do
  @moduledoc """
  Parses and validates UI spec JSON emitted by the Quecto agent.

  A UI spec has the structure:
      %{
        "layout" => "full" | "split",
        "components" => [
          %{"type" => "metric_grid" | "data_table" | "detail_card" | "chart" |
                       "alert_banner" | "dynamic_form" | "empty_state",
            "title" => "...",
            "data" => %{...}}
        ]
      }
  """

  @valid_types ~w(
    metric_grid metric_card data_table detail_card
    chart alert_banner dynamic_form empty_state
  )

  @doc """
  Parse a UI spec from the raw agent response text.
  Extracts the first JSON block with a "ui" key.
  Returns `{:ok, spec}` or `:no_spec`.
  """
  def parse(text) when is_binary(text) do
    # Look for ```json ... ``` blocks
    with [_, json_str] <- Regex.run(~r/```json\s*([\s\S]*?)```/, text),
         {:ok, parsed} <- Jason.decode(String.trim(json_str)),
         {:ok, spec} <- extract_spec(parsed) do
      {:ok, validate(spec)}
    else
      _ ->
        # Try to find raw JSON with "ui" key anywhere in text
        case Regex.run(~r/\{[^{}]*"ui"[^{}]*\{[\s\S]*?\}\s*\}/, text) do
          [json_str] ->
            case Jason.decode(json_str) do
              {:ok, parsed} ->
                case extract_spec(parsed) do
                  {:ok, spec} -> {:ok, validate(spec)}
                  _ -> :no_spec
                end

              _ ->
                :no_spec
            end

          _ ->
            :no_spec
        end
    end
  end

  def parse(_), do: :no_spec

  @doc """
  Parse a UI spec from a map (already decoded JSON).
  """
  def from_map(map) when is_map(map) do
    case extract_spec(map) do
      {:ok, spec} -> {:ok, validate(spec)}
      error -> error
    end
  end

  def from_map(_), do: :no_spec

  @doc """
  Strip the UI spec JSON block from agent response text,
  returning only the human-readable part.
  """
  def strip_spec(text) when is_binary(text) do
    text
    |> String.replace(~r/```json\s*\{[^`]*"ui"[\s\S]*?```/, "")
    |> String.trim()
  end

  def strip_spec(text), do: text

  # ──────────────────────────────────────────────────────────────────────────
  # Private helpers
  # ──────────────────────────────────────────────────────────────────────────

  defp extract_spec(%{"ui" => spec}) when is_map(spec), do: {:ok, spec}
  defp extract_spec(%{"layout" => _, "components" => _} = spec), do: {:ok, spec}
  defp extract_spec(_), do: :no_spec

  defp validate(spec) do
    components =
      (spec["components"] || [])
      |> Enum.filter(fn c ->
        c["type"] in @valid_types
      end)

    Map.put(spec, "components", components)
  end
end
