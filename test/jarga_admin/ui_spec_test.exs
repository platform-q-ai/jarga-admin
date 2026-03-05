defmodule JargaAdmin.UiSpecTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.UiSpec

  @valid_spec %{
    "layout" => "full",
    "components" => [
      %{"type" => "metric_grid", "data" => %{"metrics" => []}},
      %{"type" => "data_table", "title" => "Orders", "data" => %{"columns" => [], "rows" => []}}
    ]
  }

  describe "parse/1" do
    test "extracts UI spec from markdown JSON block" do
      text = """
      Here's your dashboard.

      ```json
      {"ui": #{Jason.encode!(@valid_spec)}}
      ```

      Enjoy!
      """

      assert {:ok, spec} = UiSpec.parse(text)
      assert spec["layout"] == "full"
      assert length(spec["components"]) == 2
    end

    test "returns :no_spec when no JSON block found" do
      assert :no_spec = UiSpec.parse("Just plain text with no spec.")
    end

    test "returns :no_spec for invalid JSON" do
      assert :no_spec = UiSpec.parse("```json\n{invalid json}\n```")
    end

    test "filters out invalid component types" do
      text = """
      ```json
      {"ui": {"layout": "full", "components": [
        {"type": "data_table", "data": {}},
        {"type": "unknown_widget", "data": {}}
      ]}}
      ```
      """

      assert {:ok, spec} = UiSpec.parse(text)
      types = Enum.map(spec["components"], & &1["type"])
      assert "data_table" in types
      refute "unknown_widget" in types
    end
  end

  describe "from_map/1" do
    test "wraps an already-decoded spec" do
      assert {:ok, spec} = UiSpec.from_map(%{"ui" => @valid_spec})
      assert spec["layout"] == "full"
    end

    test "accepts a spec map directly" do
      assert {:ok, spec} = UiSpec.from_map(@valid_spec)
      assert spec["layout"] == "full"
    end

    test "returns :no_spec for non-spec map" do
      assert :no_spec = UiSpec.from_map(%{"other" => "data"})
    end
  end

  describe "strip_spec/1" do
    test "removes JSON spec block from text" do
      text = "Here is your data.\n\n```json\n{\"ui\": {}}\n```\n\nAsk me anything!"
      result = UiSpec.strip_spec(text)
      refute String.contains?(result, "```json")
      assert String.contains?(result, "Here is your data")
    end

    test "leaves plain text unchanged" do
      text = "No spec here."
      assert UiSpec.strip_spec(text) == text
    end
  end
end
