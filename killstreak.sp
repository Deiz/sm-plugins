#include <sourcemod>

#pragma semicolon 1

public Plugin:myinfo =
{
   name = "Killstreak Setter",
   author = "Forth",
   description = "Sets a player's killstreak to an arbitrary value",
   version = "1.1"
}

new Handle:g_hCvarKSMin;
new Handle:g_hCvarKSMax;
new Handle:g_hCvarKSDefault;

public OnPluginStart()
{
   RegConsoleCmd("sm_ks", Command_Killstreak);
   RegConsoleCmd("sm_kson", Command_KillstreakOn);
   RegConsoleCmd("sm_ksoff", Command_KillstreakOff);

   g_hCvarKSMin = CreateConVar("sm_ks_min", "0",
      "Minimum killstreak value that can be set, -1 for no limit.");
   g_hCvarKSMax = CreateConVar("sm_ks_max", "10",
      "Maximum killstreak value that can be set, -1 for no limit.");
   g_hCvarKSDefault = CreateConVar("sm_ks_default", "10",
      "Default killstreak value when no arguments are provided.");

   AutoExecConfig(true, "plugin.killstreak");
}

public Action:Command_Killstreak(client, args)
{
   if (!client || !IsPlayerAlive(client))
      return Plugin_Handled;

   new n;

   if (args > 0) {
      decl String:kills[16];

      GetCmdArg(1, kills, sizeof(kills));
      n = StringToInt(kills);
      new min = GetConVarInt(g_hCvarKSMin);
      new max = GetConVarInt(g_hCvarKSMax);

      if (min != -1 && n < min)
         n = min;
      else if (max != -1 && n > max)
         n = max;
   }
   else {
      new current = GetEntProp(client, Prop_Send, "m_nStreaks", _, 0);

      if (!current)
         n = GetConVarInt(g_hCvarKSDefault);
      else
         n = 0;
   }

   SetStreak(client, n);
   return Plugin_Handled;
}

public Action:Command_KillstreakOn(client, args)
{
   if (!client || !IsPlayerAlive(client))
      return Plugin_Handled;

   SetStreak(client, GetConVarInt(g_hCvarKSDefault));
   return Plugin_Handled;
}

public Action:Command_KillstreakOff(client, args)
{
   if (!client || !IsPlayerAlive(client))
      return Plugin_Handled;

   SetStreak(client, 0);
   return Plugin_Handled;
}

SetStreak(client, n)
{
   SetEntProp(client, Prop_Send, "m_nStreaks", n, _, 0);
   ReplyToCommand(client, "[SM] Set killstreak to: %d", n);
}
