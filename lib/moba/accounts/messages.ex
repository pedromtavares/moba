defmodule Moba.Accounts.Messages do
  @moduledoc """
  Manages Messages for the Community page
  """

  alias Moba.{Repo, Accounts}
  alias Accounts.Schema.Message

  import Ecto.Query, only: [from: 2]

  def latest(channel, limit) do
    query =
      from message in Message,
        where: message.channel == ^channel,
        limit: ^limit,
        order_by: [desc: :id]

    Repo.all(query)
  end

  def get!(id), do: Repo.get!(Message, id)

  def change(attrs), do: Message.changeset(%Message{}, attrs)

  def create!(attrs) do
    %Message{}
    |> Message.changeset(attrs)
    |> Repo.insert!()
  end

  def delete(%Message{} = message), do: Repo.delete(message)
end
