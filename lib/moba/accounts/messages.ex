defmodule Moba.Accounts.Messages do
  @moduledoc """
  Manages Messages for the Community page
  """

  alias Moba.{Repo, Accounts}
  alias Accounts.Schema.{Message, User}

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

  @doc "Allows three quick messages, then requires five quiet seconds before the next burst."
  def create_message(attrs) do
    Repo.transaction(fn ->
      user_id = Map.get(attrs, :user_id) || Map.get(attrs, "user_id")
      if user_id, do: reserve_message!(user_id)

      %Message{user_id: user_id}
      |> Message.changeset(attrs)
      |> Repo.insert!()
    end)
  end

  defp reserve_message!(user_id) do
    user = Repo.one!(from u in User, where: u.id == ^user_id, lock: "FOR UPDATE")
    now = DateTime.utc_now()

    quiet? =
      is_nil(user.chat_last_message_at) || DateTime.diff(now, user.chat_last_message_at, :microsecond) >= 5_000_000

    count = if quiet?, do: 0, else: user.chat_burst_count
    if count >= 3, do: Repo.rollback(:rate_limited)

    user
    |> Ecto.Changeset.change(chat_burst_count: count + 1, chat_last_message_at: now)
    |> Repo.update!()
  end

  def delete_message(%Message{} = message), do: Repo.delete(message)

  def notification_count(nil), do: 0

  def notification_count(%{community_seen_at: time}) do
    from(m in Message, where: m.inserted_at > ^time, where: m.channel == "community") |> Repo.aggregate(:count)
  end
end
