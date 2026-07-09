defmodule Aveline.Contract do
  @moduledoc """
  The machine-readable write contract for docs: block types, block ops,
  edit modes, and comment dispositions — with a valid example for every
  block and op.

  This is the single answer to "what shape does a block / op take?", so
  an agent never has to reverse-engineer it from get-orientation output
  or validation errors. Served at GET /api/contract and printed by
  `aveline contract`.

  Every `example` here is asserted valid against the real validators
  (`Block` / `Operation`) by `Aveline.ContractTest`, and the block-type
  and op lists are asserted to match `Block.types/0` / `Operation.ops/0`
  exactly. If a shape drifts or a type is added, the test fails — not the
  agent.
  """

  alias Aveline.Blocks.Block
  alias Aveline.Blocks.Operation

  @doc "The full write contract, JSON-ready (string keys throughout)."
  def write_contract do
    %{
      "overview" =>
        "How to write to Aveline docs. A doc is an ordered list of blocks. " <>
          "Create one with `create-doc --blocks`; change one with `edit-doc` " <>
          "(--blocks to replace the whole body, or --ops for a surgical edit). " <>
          "This contract is the authoritative shape reference — copy an example " <>
          "and adjust it rather than guessing.",
      "ids" => %{
        "block_id" =>
          "b_<random>. Omit it on a new block and the server mints one. Keep it " <>
            "on blocks you are editing so a --blocks full replace reconciles them by id.",
        "list_item_id" => "li_<random>. Minted if omitted."
      },
      "inline_spans" => inline_spans(),
      "block_types" => block_types(),
      "operations" => operations(),
      "edit_modes" => edit_modes(),
      "dispositions" => dispositions()
    }
  end

  # The rich-text primitive shared by paragraph / list item / table cell /
  # doc_link note. The example is validated transitively (it's the body of
  # the paragraph block example below).
  defp inline_spans do
    %{
      "summary" =>
        "Rich text inside a paragraph, list item, table cell, or doc_link note: " <>
          "a list of span objects, never a flat string.",
      "span" => %{
        "text" => "required string",
        "marks" => "optional list, any of: bold, italic, code, strike",
        "link" =>
          "optional: {href: <url>} for external, or {doc: <slug>} for another " <>
            "doc in this workspace (server resolves the slug). One or the other."
      }
    }
  end

  defp block_types do
    [
      %{
        "type" => "heading",
        "summary" => "A section heading.",
        "example" => %{"type" => "heading", "level" => 2, "text" => "Section title"},
        "notes" => [
          "level is 1, 2, or 3.",
          "Heading text is a FLAT string — unlike paragraph/list/table, which use a spans array."
        ]
      },
      %{
        "type" => "paragraph",
        "summary" => "A block of prose.",
        "example" => %{
          "type" => "paragraph",
          "content" => [
            %{"text" => "Plain, then "},
            %{"text" => "bold", "marks" => ["bold"]},
            %{"text" => ", and a "},
            %{"text" => "link", "link" => %{"href" => "https://example.com"}},
            %{"text" => "."}
          ]
        },
        "notes" => ["content is a list of inline spans (see inline_spans), not a string."]
      },
      %{
        "type" => "code",
        "summary" => "A code block.",
        "example" => %{
          "type" => "code",
          "language" => "elixir",
          "content" => "IO.puts(\"hi\")"
        },
        "notes" => ["content is a plain string. language may be null."]
      },
      %{
        "type" => "list",
        "summary" => "A bulleted or numbered list.",
        "example" => %{
          "type" => "list",
          "ordered" => false,
          "items" => [
            %{"content" => [%{"text" => "first item"}]},
            %{"content" => [%{"text" => "second item"}]}
          ]
        },
        "notes" => [
          "ordered defaults to false (bulleted); true is numbered.",
          "Each item is {content: [spans]}; item ids (li_...) are minted if omitted."
        ]
      },
      %{
        "type" => "table",
        "summary" => "A table with a header row.",
        "example" => %{
          "type" => "table",
          "headers" => ["Name", "Role"],
          "rows" => [
            [[%{"text" => "Ada"}], [%{"text" => "Engineer"}]],
            [[%{"text" => "Grace"}], [%{"text" => "Admiral"}]]
          ]
        },
        "notes" => [
          "rows is a list of rows; each row is a list of cells; each cell is a list of spans.",
          "Every row must have the same length as headers."
        ]
      },
      %{
        "type" => "doc_link",
        "summary" => "An ordered reference to another doc in this workspace (a card).",
        "example" => %{
          "type" => "doc_link",
          "doc_id" => "00000000-0000-0000-0000-000000000000",
          "note" => [%{"text" => "See the deploy runbook."}]
        },
        "notes" => [
          "Prefer `doc: <slug>` over doc_id — the server resolves the slug to the target's base_doc_id and verifies it exists.",
          "Optional note is a spans array. A body that chains doc_links makes a trail/story."
        ]
      },
      %{
        "type" => "chart",
        "summary" => "A live SQL query against a workspace data source, rendered as a chart or table.",
        "example" => %{
          "type" => "chart",
          "data_source_id" => "00000000-0000-0000-0000-000000000000",
          "query" => "select day, signups from daily_growth order by day",
          "viz" => %{"type" => "bar", "x" => "day", "y" => "signups"}
        },
        "notes" => [
          "Prefer `source: <data-source-name>` over data_source_id — the server resolves it.",
          "viz.type is table | line | bar | combo. line/bar need x and y column names.",
          "combo needs x and 1-4 series: [{y: <col>, type: line|bar, axis?: left|right}].",
          "Reads gain a computed result (columns/rows or an error) — never write result back."
        ]
      }
    ]
  end

  defp operations do
    [
      %{
        "op" => "append_block",
        "summary" => "Add a block at the end. The full block goes under \"block\".",
        "example" => %{
          "op" => "append_block",
          "block" => %{"type" => "paragraph", "content" => [%{"text" => "New last paragraph."}]}
        }
      },
      %{
        "op" => "insert_block",
        "summary" => "Insert a block after another. \"after\" is a block id; \"block\" is the full block.",
        "example" => %{
          "op" => "insert_block",
          "after" => "b_targetBlockId",
          "block" => %{"type" => "paragraph", "content" => [%{"text" => "Inserted here."}]}
        }
      },
      %{
        "op" => "modify_block",
        "summary" =>
          "Update an existing block. Top-level \"id\" + \"patch\" (a partial block) — " <>
            "NOT a nested \"block\" like append/insert. type and id cannot change.",
        "example" => %{
          "op" => "modify_block",
          "id" => "b_targetBlockId",
          "patch" => %{"content" => [%{"text" => "Replacement text."}]}
        }
      },
      %{
        "op" => "delete_block",
        "summary" => "Remove a block by \"id\".",
        "example" => %{"op" => "delete_block", "id" => "b_targetBlockId"}
      },
      %{
        "op" => "move_block",
        "summary" => "Reorder a block. \"after\" is a block id, or null to move it to the top.",
        "example" => %{"op" => "move_block", "id" => "b_targetBlockId", "after" => "b_otherBlockId"}
      }
    ]
  end

  defp edit_modes do
    %{
      "blocks" =>
        "Full replace. Send the whole doc as it should end up (get-doc, edit, resend). " <>
          "The server reconciles by block id: keep a block's id to update it, omit a block " <>
          "to delete it, add a block with no id for a new one. Deterministic (id match, not " <>
          "a text diff). Use this for most edits.",
      "operations" =>
        "Surgical. A list of ops applied in order — touch one block in a large doc without " <>
          "resending it.",
      "note" => "Send exactly one of blocks or operations to edit-doc, never both."
    }
  end

  defp dispositions do
    %{
      "when_required" =>
        "If your edit changes or deletes a block carrying an open comment, you must " <>
          "disposition that thread (agent edits only; humans may skip). Run " <>
          "`list-comments <slug>` to see open threads and their block anchors.",
      "shape" => "comment_dispositions: a list of {comment_id, action, ...}.",
      "actions" => [
        %{
          "action" => "resolve",
          "fields" => "comment_id, reply (optional)",
          "means" => "Mark the thread resolved; reply posts an agent comment pinned to this version."
        },
        %{
          "action" => "reanchor",
          "fields" => "comment_id, new_block_id",
          "means" => "Move the comment to a different block that exists in the new version."
        },
        %{
          "action" => "leave",
          "fields" => "comment_id, note (optional)",
          "means" =>
            "Keep it open. Not allowed if the anchor block was deleted — resolve or reanchor instead."
        }
      ],
      "example" => [
        %{"comment_id" => "<uuid from list-comments>", "action" => "resolve", "reply" => "Fixed here."}
      ]
    }
  end

  @doc "Block type names covered by the contract (for drift checks)."
  def block_type_names, do: Enum.map(block_types(), & &1["type"])

  @doc "Op names covered by the contract (for drift checks)."
  def operation_names, do: Enum.map(operations(), & &1["op"])

  @doc "Every block example, for validation in tests."
  def block_examples, do: Enum.map(block_types(), & &1["example"])

  @doc "Every op example, for validation in tests."
  def operation_examples, do: Enum.map(operations(), & &1["example"])

  # Keep the drift-check helpers honest about their sources.
  @doc false
  def _validator_sources, do: {Block.types(), Operation.ops()}
end
