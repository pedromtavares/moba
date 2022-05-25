defmodule Moba.Accounts.Messages do
  @moduledoc """
  Manages Messages for the Community page
  """

  alias Moba.{Repo, Accounts}
  alias Accounts.Schema.Message

  import Ecto.Query, only: [from: 2]

  def latest_messages(channel, topic, limit) do
    query =
      from message in Message,
        where: message.channel == ^channel,
        where: message.topic == ^topic,
        limit: ^limit,
        order_by: [desc: :id]

    Repo.all(query) |> Repo.preload(:user)
  end

  def get_message!(id), do: Repo.get!(Message, id)

  def change_message(attrs), do: Message.changeset(%Message{}, attrs)

  def create_message!(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert!()
  end

  def delete_message(%Message{} = message), do: Repo.delete(message)
end
