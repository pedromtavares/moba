defmodule Moba.Accounts.ReturnCampaign do
  @moduledoc """
  Prepares the Reborn invitation audience and redeems its single-use login links.

  On a running release, `prepare(path)` exports a read-only audience preview.
  `prepare(path, issue_tokens: true)` also creates the 30-day invitations.
  Pass `user_ids: [id]` to prepare the same invitation for a selected account.
  The output contains private account data; only the summary is returned to the caller.
  """

  import Ecto.Query

  alias Moba.{Repo, Accounts.UserToken, Accounts.Schema.User, Game.Schema.Player}

  @context "return:reborn_2026_10:"
  @validity_days 30
  @limit 770

  def audience(opts \\ []) do
    excluded = Enum.map(Keyword.get(opts, :exclude_emails, []), &normalize_email/1)

    players =
      from p in Player,
        join: u in assoc(p, :user),
        where: is_nil(p.bot_options),
        where: not is_nil(u.email) and fragment("btrim(?) <> ''", u.email),
        where: fragment("lower(btrim(?))", u.email) not in ^excluded,
        select: %{
          user_id: u.id,
          player_id: p.id,
          email: u.email,
          username: u.username,
          last_online_at: u.last_online_at,
          score: 100 * coalesce(p.best_immortal_streak, 0) + 100 * coalesce(p.pve_tier, 0) + coalesce(p.pvp_points, 0),
          wins: coalesce(p.total_wins, 0)
        }

    players =
      case Keyword.get(opts, :user_ids) do
        nil -> players
        ids -> where(players, [p, u], u.id in ^ids)
      end

    by_user =
      from p in subquery(players),
        where: p.score > 0,
        distinct: p.user_id,
        order_by: [asc: p.user_id, desc: p.score, desc: p.wins, asc: p.player_id]

    by_email =
      from p in subquery(by_user),
        distinct: fragment("lower(btrim(?))", p.email),
        order_by: [asc: fragment("lower(btrim(?))", p.email), desc: p.score, desc: p.wins, asc: p.player_id]

    from(p in subquery(by_email),
      order_by: [desc: p.score, desc: p.wins, asc: p.player_id],
      limit: ^@limit
    )
    |> Repo.all()
  end

  def preview(token) do
    with query when not is_nil(query) <- token_query(token),
         {invitation, user} <- Repo.one(query),
         true <- invitation.context == context_for(user) do
      {:ok, user}
    else
      _ -> :error
    end
  end

  def redeem(token) do
    with query when not is_nil(query) <- token_query(token) do
      Repo.transaction(fn ->
        with {invitation, user} <- Repo.one(lock(query, "FOR UPDATE")),
             true <- invitation.context == context_for(user),
             player_id when not is_nil(player_id) <- player_id(user.id) do
          Repo.delete!(invitation)
          %{user: user, player_id: player_id}
        else
          _ -> Repo.rollback(:invalid_invitation)
        end
      end)
      |> case do
        {:ok, login} -> {:ok, login}
        _ -> :error
      end
    else
      _ -> :error
    end
  end

  def prepare(path, opts \\ []) do
    if Path.type(path) != :absolute, do: raise(ArgumentError, "use an absolute private output path")
    issue? = Keyword.get(opts, :issue_tokens, false)

    # Reserve a new file and restrict access before writing addresses or login secrets.
    case File.open(path, [:write, :binary, :exclusive]) do
      {:ok, file} ->
        try do
          File.chmod!(path, 0o600)

          result =
            Repo.transaction(fn ->
              audience = audience(opts)
              contacts = if issue?, do: issue_invitations(audience), else: audience
              payload = %{campaign: "reborn_2026_10", tokens_issued: issue?, contacts: contacts}

              case IO.binwrite(file, Jason.encode!(payload, pretty: true)) do
                :ok -> %{count: length(contacts), tokens_issued: issue?, path: path}
                _ -> Repo.rollback(:output_write_failed)
              end
            end)

          case result do
            {:ok, summary} ->
              {:ok, summary}

            {:error, reason} ->
              File.rm(path)
              {:error, reason}
          end
        rescue
          error ->
            File.rm(path)
            reraise error, __STACKTRACE__
        after
          File.close(file)
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp issue_invitations(audience) do
    ids = Enum.map(audience, & &1.user_id)
    users = Repo.all(from u in User, where: u.id in ^ids, order_by: u.id, lock: "FOR UPDATE")
    by_id = Map.new(users, &{&1.id, &1})

    existing =
      from t in UserToken,
        where: t.user_id in ^ids and like(t.context, ^(@context <> "%")),
        where: t.inserted_at > ago(@validity_days, "day")

    if Repo.exists?(existing), do: Repo.rollback(:campaign_tokens_already_exist)

    Enum.map(audience, fn contact ->
      user = Map.fetch!(by_id, contact.user_id)
      if user.email != contact.email, do: Repo.rollback(:audience_changed)
      {encoded, invitation} = UserToken.build_email_token(user, context_for(user))
      Repo.insert!(invitation)
      Map.put(contact, :return_url, MobaWeb.Endpoint.url() <> "/return#token=" <> encoded)
    end)
  end

  defp token_query(token) when is_binary(token) and byte_size(token) == 43 do
    case Base.url_decode64(token, padding: false) do
      {:ok, decoded} when byte_size(decoded) == 32 ->
        hash = :crypto.hash(:sha256, decoded)

        from t in UserToken,
          join: u in assoc(t, :user),
          where: t.token == ^hash and like(t.context, ^(@context <> "%")),
          where: t.inserted_at > ago(@validity_days, "day") and t.sent_to == u.email,
          select: {t, u}

      _ ->
        nil
    end
  end

  defp token_query(_), do: nil

  # Credential binding invalidates invitations whenever the email or password changes.
  defp context_for(user) do
    credentials = :erlang.term_to_binary({user.email, user.hashed_password, user.password_hash})
    @context <> Base.url_encode64(:crypto.hash(:sha256, credentials), padding: false)
  end

  defp player_id(user_id) do
    from(p in Player,
      where: p.user_id == ^user_id and is_nil(p.bot_options),
      order_by: [
        desc: 100 * coalesce(p.best_immortal_streak, 0) + 100 * coalesce(p.pve_tier, 0) + coalesce(p.pvp_points, 0),
        desc: p.total_wins,
        asc: p.id
      ],
      select: p.id,
      limit: 1
    )
    |> Repo.one()
  end

  defp normalize_email(email), do: email |> String.trim() |> String.downcase()
end
