
#include <sourcemod>

#pragma semicolon 1

public Plugin:myinfo =
{
   name = "Votekick Toggle",
   author = "Forth",
   description = "Disables kick votes when below a certain player count",
   version = "0.1",
};

new Handle:g_hMinPlayers = INVALID_HANDLE;
new Handle:g_hVoteKick   = INVALID_HANDLE;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
   g_hVoteKick = FindConVar("sv_vote_issue_kick_allowed");
   if (g_hVoteKick == INVALID_HANDLE) {
      strcopy(error, err_max, "sv_vote_issue_kick_allowed");
      return APLRes_Failure;
   }

   return APLRes_Success;
}


public OnPluginStart()
{
   g_hMinPlayers = CreateConVar("sm_votekick_minplayers", "8",
      "Number of players required to enable kick voting");
}

public OnClientPutInServer(client)
{
   if (!GetConVarBool(g_hVoteKick) && GetClientCount() >= GetConVarInt(g_hMinPlayers))
      SetConVarBool(g_hVoteKick, true);
}

public OnClientDisconnect_Post(client)
{
   if (GetConVarBool(g_hVoteKick) && GetClientCount() < GetConVarInt(g_hMinPlayers))
      SetConVarBool(g_hVoteKick, false);
}
