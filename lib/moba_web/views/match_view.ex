defmodule MobaWeb.MatchView do
  use MobaWeb, :view

  def player_pick(battle, %{player_id: pid, player_picks: picks}) do
    %{attacker_id: aid, defender_id: did, attacker_player_id: apid, defender_player_id: dpid} = battle
    Enum.find(picks, &((&1.id == aid && apid == pid) || (&1.id == did && dpid == pid)))
  end

  def opponent_pick(battle, %{opponent_id: oid, opponent_picks: picks}) do
    %{attacker_id: aid, defender_id: did, attacker_player_id: apid, defender_player_id: dpid} = battle
    Enum.find(picks, &((&1.id == aid && apid == oid) || (&1.id == did && dpid == oid)))
  end
end
