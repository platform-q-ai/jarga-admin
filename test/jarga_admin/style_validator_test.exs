defmodule JargaAdmin.StyleValidatorTest do
  use ExUnit.Case, async: true

  alias JargaAdmin.StyleValidator

  describe "validate/1" do
    test "returns empty map for nil" do
      assert StyleValidator.validate(nil) == %{}
    end

    test "returns empty map for non-map input" do
      assert StyleValidator.validate("string") == %{}
      assert StyleValidator.validate(42) == %{}
      assert StyleValidator.validate([]) == %{}
    end

    test "passes through valid layout properties" do
      style = %{
        "background" => "#f5f0eb",
        "padding" => "80px 32px",
        "margin" => "0 auto",
        "max_width" => "1200px",
        "gap" => "24px",
        "text_align" => "center",
        "min_height" => "400px",
        "border_radius" => "8px"
      }

      result = StyleValidator.validate(style)

      assert result["background"] == "#f5f0eb"
      assert result["padding"] == "80px 32px"
      assert result["margin"] == "0 auto"
      assert result["max_width"] == "1200px"
      assert result["gap"] == "24px"
      assert result["text_align"] == "center"
      assert result["min_height"] == "400px"
      assert result["border_radius"] == "8px"
    end

    test "passes through valid border properties" do
      style = %{
        "border_top" => "1px solid rgba(0,0,0,0.08)",
        "border_bottom" => "1px solid #e5e5e5"
      }

      result = StyleValidator.validate(style)
      assert result["border_top"] == "1px solid rgba(0,0,0,0.08)"
      assert result["border_bottom"] == "1px solid #e5e5e5"
    end

    test "passes through valid typography properties" do
      style = %{
        "title_size" => "24px",
        "title_weight" => "300",
        "title_color" => "#1a1a1a",
        "title_spacing" => "0.2em",
        "text_color" => "#666666",
        "text_size" => "14px"
      }

      result = StyleValidator.validate(style)
      assert result["title_size"] == "24px"
      assert result["title_weight"] == "300"
      assert result["title_color"] == "#1a1a1a"
      assert result["title_spacing"] == "0.2em"
      assert result["text_color"] == "#666666"
      assert result["text_size"] == "14px"
    end

    test "passes through valid card properties" do
      style = %{
        "card_background" => "#f5f5f5",
        "card_padding" => "16px",
        "card_aspect_ratio" => "1/1",
        "card_border" => "1px solid rgba(0,0,0,0.08)"
      }

      result = StyleValidator.validate(style)
      assert result["card_background"] == "#f5f5f5"
      assert result["card_padding"] == "16px"
      assert result["card_aspect_ratio"] == "1/1"
      assert result["card_border"] == "1px solid rgba(0,0,0,0.08)"
    end

    test "passes through valid rgba and hsl colours" do
      style = %{
        "background" => "rgba(255, 255, 255, 0.9)",
        "text_color" => "hsl(0, 0%, 40%)",
        "title_color" => "hsla(0, 0%, 40%, 0.5)"
      }

      result = StyleValidator.validate(style)
      assert result["background"] == "rgba(255, 255, 255, 0.9)"
      assert result["text_color"] == "hsl(0, 0%, 40%)"
      assert result["title_color"] == "hsla(0, 0%, 40%, 0.5)"
    end

    test "rejects unknown properties" do
      style = %{
        "background" => "#ffffff",
        "position" => "absolute",
        "display" => "none",
        "z_index" => "9999",
        "overflow" => "hidden"
      }

      result = StyleValidator.validate(style)
      assert result["background"] == "#ffffff"
      refute Map.has_key?(result, "position")
      refute Map.has_key?(result, "display")
      refute Map.has_key?(result, "z_index")
      refute Map.has_key?(result, "overflow")
    end

    test "rejects values containing semicolons" do
      style = %{
        "background" => "#fff; position: absolute",
        "padding" => "10px; display: none"
      }

      result = StyleValidator.validate(style)
      assert result == %{}
    end

    test "rejects values containing url()" do
      style = %{
        "background" => "url(https://evil.com/tracker.gif)"
      }

      result = StyleValidator.validate(style)
      assert result == %{}
    end

    test "rejects values containing expression()" do
      style = %{
        "background" => "expression(alert(1))"
      }

      result = StyleValidator.validate(style)
      assert result == %{}
    end

    test "rejects values containing javascript:" do
      style = %{
        "background" => "javascript:alert(1)"
      }

      result = StyleValidator.validate(style)
      assert result == %{}
    end

    test "rejects values containing import" do
      style = %{
        "background" => "@import url(evil.css)"
      }

      result = StyleValidator.validate(style)
      assert result == %{}
    end

    test "rejects CSS unicode escape bypass attempts" do
      # \75 is 'u' — \75rl(...) should be caught as url(...)
      style = %{"background" => "\\75rl(https://evil.com/tracker.gif)"}
      assert StyleValidator.validate(style) == %{}

      # \65 is 'e' — \65xpression(...) should be caught as expression(...)
      style2 = %{"background" => "\\65xpression(alert(1))"}
      assert StyleValidator.validate(style2) == %{}
    end

    test "rejects var(), paint(), element(), env() functions" do
      for func <- [
            "var(--secret)",
            "paint(myPainter)",
            "element(#el)",
            "env(safe-area-inset-top)"
          ] do
        result = StyleValidator.validate(%{"background" => func})
        assert result == %{}, "should reject #{func}"
      end
    end

    test "rejects values exceeding max length" do
      long_value = String.duplicate("a", 300)
      style = %{"background" => long_value}
      assert StyleValidator.validate(style) == %{}
    end

    test "rejects invalid text_align values" do
      style = %{
        "text_align" => "evil"
      }

      result = StyleValidator.validate(style)
      assert result == %{}
    end

    test "allows valid text_align values" do
      for align <- ["left", "center", "right", "justify"] do
        result = StyleValidator.validate(%{"text_align" => align})
        assert result["text_align"] == align
      end
    end

    test "rejects non-string values" do
      style = %{
        "background" => 123,
        "padding" => true,
        "margin" => nil
      }

      result = StyleValidator.validate(style)
      assert result == %{}
    end

    test "returns empty map for empty input map" do
      assert StyleValidator.validate(%{}) == %{}
    end
  end

  describe "to_inline_style/1" do
    test "converts validated style to inline CSS string" do
      style = %{
        "background" => "#f5f0eb",
        "padding" => "80px 32px",
        "max_width" => "1200px"
      }

      result = StyleValidator.to_inline_style(style)
      assert result =~ "background:#f5f0eb"
      assert result =~ "padding:80px 32px"
      assert result =~ "max-width:1200px"
    end

    test "returns empty string for empty map" do
      assert StyleValidator.to_inline_style(%{}) == ""
    end

    test "returns empty string for nil" do
      assert StyleValidator.to_inline_style(nil) == ""
    end

    test "converts underscored property names to hyphenated CSS" do
      style = %{
        "text_align" => "center",
        "min_height" => "400px",
        "border_top" => "1px solid #ccc",
        "border_radius" => "8px"
      }

      result = StyleValidator.to_inline_style(style)
      assert result =~ "text-align:center"
      assert result =~ "min-height:400px"
      assert result =~ "border-top:1px solid #ccc"
      assert result =~ "border-radius:8px"
    end

    test "excludes card_ and title_ prefixed properties from inline style" do
      style = %{
        "background" => "#fff",
        "card_background" => "#f5f5f5",
        "title_size" => "24px"
      }

      result = StyleValidator.to_inline_style(style)
      assert result =~ "background:#fff"
      refute result =~ "card"
      refute result =~ "title"
    end
  end

  describe "card_style/1" do
    test "extracts card-specific properties as inline CSS" do
      style = %{
        "background" => "#fff",
        "card_background" => "#f5f5f5",
        "card_padding" => "16px",
        "card_aspect_ratio" => "1/1",
        "card_border" => "1px solid #ccc"
      }

      result = StyleValidator.card_style(style)
      assert result =~ "background:#f5f5f5"
      assert result =~ "padding:16px"
      assert result =~ "aspect-ratio:1/1"
      assert result =~ "border:1px solid #ccc"
      refute result =~ "background:#fff"
    end

    test "returns empty string when no card properties" do
      assert StyleValidator.card_style(%{"background" => "#fff"}) == ""
      assert StyleValidator.card_style(%{}) == ""
      assert StyleValidator.card_style(nil) == ""
    end
  end

  describe "title_style/1" do
    test "extracts title-specific properties as inline CSS" do
      style = %{
        "background" => "#fff",
        "title_size" => "24px",
        "title_weight" => "300",
        "title_color" => "#1a1a1a",
        "title_spacing" => "0.2em"
      }

      result = StyleValidator.title_style(style)
      assert result =~ "font-size:24px"
      assert result =~ "font-weight:300"
      assert result =~ "color:#1a1a1a"
      assert result =~ "letter-spacing:0.2em"
      refute result =~ "background"
    end

    test "returns empty string when no title properties" do
      assert StyleValidator.title_style(%{"background" => "#fff"}) == ""
      assert StyleValidator.title_style(%{}) == ""
      assert StyleValidator.title_style(nil) == ""
    end
  end
end
