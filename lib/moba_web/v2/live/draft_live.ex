defmodule MobaWeb.V2.DraftLive do
  use MobaWeb, :v2_live_view
  import MobaWeb.CoreComponents, only: [icon: 1]
  on_mount MobaWeb.V2.Hooks.TeamAccess
  alias Moba.Game.{TeamRuns, TeamTraining}
  alias MobaWeb.V2.CreateLive

  def mount(params, session, socket) do
    {:ok, socket} = CreateLive.mount(params, session, socket)
    player = socket.assigns.current_player

    record =
      if Map.get(player, :id) do
        {:ok, record} = TeamRuns.draft(socket.assigns.current_scope, player)
        record
      end

    run = if record, do: TeamRuns.state(record), else: %{picks: []}
    default_name = socket.assigns.current_scope.user && socket.assigns.current_scope.user.username
    team_name = if record, do: record.name || default_name

    {:ok,
     socket
     |> assign(
       draft_record: record,
       draft_picks: Enum.map(run.picks, &draft_pick/1),
       team_form: to_form(%{"name" => team_name}, as: :team),
       team_name_error: nil,
       draft_mode: true,
       launch_label: "Add to roster",
       cache_key: "team-draft-#{if record, do: record.id, else: session["cache_key"]}"
     )}
  end

  def handle_event("begin-training", %{"roster" => roster} = params, %{assigns: %{draft_record: %{} = draft}} = socket) do
    scope = socket.assigns.current_scope

    name =
      case params do
        %{"team" => %{"name" => value}} -> value
        _ -> socket.assigns.team_form[:name].value
      end

    result =
      with {:ok, picks} <- TeamTraining.decode_roster(roster) do
        TeamRuns.update(scope, draft, &TeamTraining.prepare_run(scope, &1, picks, name))
      end

    case result do
      {:ok, _record} ->
        {:noreply, push_navigate(socket, to: ~p"/training")}

      {:error, {:invalid, {:team_name, message}}} ->
        {:noreply, assign(socket, team_form: to_form(%{"name" => name}, as: :team), team_name_error: message)}

      {:error, :stale} ->
        case TeamRuns.get!(scope, draft.id).phase do
          "draft" -> {:noreply, put_flash(socket, :error, "Reload this page to start training.")}
          _ -> {:noreply, push_navigate(socket, to: ~p"/training")}
        end

      _ ->
        {:noreply, put_flash(socket, :error, "Choose three different unlocked avatars and valid builds.")}
    end
  end

  def handle_event(_, _, socket), do: {:noreply, socket}

  defp draft_pick(pick) do
    preset =
      pick.avatar.role
      |> Game.skill_builds_for()
      |> Enum.find_index(fn {_skills, name} -> name == pick[:preset_name] end)

    %{avatar: to_string(pick.avatar.id), skills: Enum.map(pick.skills, &to_string(&1.id)), preset: preset}
  end

  def handle_info(:training_access_revoked, socket), do: {:noreply, redirect(socket, to: "/base")}
  def handle_info(_, socket), do: {:noreply, socket}
end
