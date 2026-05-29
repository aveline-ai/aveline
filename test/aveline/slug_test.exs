defmodule Aveline.SlugTest do
  use ExUnit.Case, async: true

  alias Aveline.Slug

  describe "derive/1" do
    test "lowercases and dashes" do
      assert Slug.derive("Hello World") == "hello-world"
      assert Slug.derive("  Trim Me  ") == "trim-me"
      assert Slug.derive("Multi   Space__yes") == "multi-space-yes"
    end

    test "drops leading/trailing dashes and bad chars" do
      assert Slug.derive("--oncall--") == "oncall"
      assert Slug.derive("oncall!?") == "oncall"
    end

    test "returns nil for empty input" do
      assert Slug.derive("") == nil
      assert Slug.derive("!!!") == nil
      assert Slug.derive("🔥🔥🔥") == nil
      assert Slug.derive(nil) == nil
    end

    test "caps at max length" do
      long = String.duplicate("a", 100)
      derived = Slug.derive(long)
      assert String.length(derived) <= Slug.max_length()
    end
  end

  describe "validate/1" do
    test "accepts valid slugs" do
      assert Slug.validate("oncall") == :ok
      assert Slug.validate("a") == :ok
      assert Slug.validate("multi-word-slug") == :ok
      assert Slug.validate("123") == :ok
    end

    test "rejects bad slugs" do
      assert Slug.validate("-leading") == {:error, :invalid_slug}
      assert Slug.validate("UPPER") == {:error, :invalid_slug}
      assert Slug.validate("has space") == {:error, :invalid_slug}
      assert Slug.validate("") == {:error, :invalid_slug}
      assert Slug.validate(nil) == {:error, :invalid_slug}
    end
  end
end
