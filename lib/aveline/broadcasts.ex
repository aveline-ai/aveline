defmodule Aveline.Broadcasts do
  @moduledoc """
  Central PubSub helper. Topics are keyed by stable identifiers
  (base_doc_id for docs, workspace_id for workspaces) so subscribers
  stay attached across edits.
  """

  alias Phoenix.PubSub

  @pubsub Aveline.PubSub

  def subscribe(topic) when is_binary(topic), do: PubSub.subscribe(@pubsub, topic)
  def unsubscribe(topic) when is_binary(topic), do: PubSub.unsubscribe(@pubsub, topic)

  def doc_topic(base_doc_id), do: "doc:" <> base_doc_id
  def doc_comments_topic(base_doc_id), do: "doc:" <> base_doc_id <> ":comments"
  def workspace_docs_topic(workspace_id), do: "workspace:" <> workspace_id <> ":docs"

  def publish_doc_event(event, %{base_doc_id: base, workspace_id: ws_id} = doc)
      when event in [:doc_created, :doc_updated, :doc_deleted, :doc_restored] do
    # No-op when PubSub isn't running (e.g. a data migration or any
    # non-web context driving Docs): a doc write shouldn't fail because
    # the live-update bus is down. Live viewers, when present, are served.
    if Process.whereis(@pubsub) do
      PubSub.broadcast(@pubsub, doc_topic(base), {event, doc})
      PubSub.broadcast(@pubsub, workspace_docs_topic(ws_id), {event, doc})
    end

    :ok
  end
end
