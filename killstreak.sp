#include <sourcemod>

#pragma semicolon 1

public Plugin:myinfo =
{
   name = "Killstreak Setter",
   author = "Forth",
   description = "Sets a player's killstreak to an arbitrary value",
   version = "1.0"
}

new Handle:g_hCvarKSMin;
new Handle:g_hCvarKSMax;

public OnPluginStart()
{
   RegConsoleCmd("sm_ks", Command_Killstreak);

   g_hCvarKSMin = CreateConVar("sm_ks_min", "0",
      "Minimum killstreak value that can be set, -1 for no limit.");
   g_hCvarKSMax = CreateConVar("sm_ks_max", "10",
      "Maximum killstreak value that can be set, -1 for no limit.");
   AutoExecConfig(true, "plugin.killstreak");
}

public Action:Command_Killstreak(client, args)
{
   if (!client || !IsPlayerAlive(client))
      return Plugin_Handled;

   new String:kills[16];
   new n = 0;
   if (args > 0) {
      GetCmdArg(1, kills, sizeof(kills));
      n = StringToInt(kills);
      new min = GetConVarInt(g_hCvarKSMin);
      new max = GetConVarInt(g_hCvarKSMax);

      if (min != -1 && n < min)
         n = min;
      else if (max != -1 && n > max)
         n = max;
   }

   SetEntProp(client, Prop_Send, "m_iKillStreak", n);
   ReplyToCommand(client, "[SM] Set killstreak to: %d", n);
   return Plugin_Handled;
}
