#include <sourcemod>
#include <geoip>

#pragma semicolon 1

public Plugin:myinfo =
{
   name = "[TF2] Player Info",
   author = "Forth",
   description = "Displays basic information about players",
   version = "1.0"
}

new g_RPS[MAXPLAYERS+1][2];

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
   if (GetEngineVersion() != Engine_TF2) {
      strcopy(error, err_max, "Plugin only works on Team Fortress 2.");
      return APLRes_Failure;
   }

   return APLRes_Success;
}

public OnPluginStart()
{
   LoadTranslations("common.phrases");

   RegConsoleCmd("sm_playerinfo", Command_PlayerInfo, "sm_playerinfo <#userid|name>");
   RegConsoleCmd("sm_rps", Command_RPS, "sm_rps <#userid|name>");
   HookEvent("rps_taunt_event", Event_RPS, EventHookMode_Post);
}

public OnClientPutInServer(client)
{
   g_RPS[client] = {0, 0};
}

public Event_RPS(Handle:event, const String:name[], bool:dontBroadcast)
{
   new client = GetEventInt(event, "winner");
   g_RPS[client][0]++;

   client = GetEventInt(event, "loser");
   g_RPS[client][1]++;
}

public Action:Command_PlayerInfo(client, args)
{
   if (args < 1) {
      ReplyToCommand(client, "[SM] Usage: sm_playerinfo <#userid|name>");
      return Plugin_Handled;
   }

   new String:arg[64];
   GetCmdArg(1, arg, sizeof(arg));

   decl String:target_name[MAX_TARGET_LENGTH];
   decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;

   if ((target_count = ProcessTargetString(
      arg,
      client,
      target_list,
      MAXPLAYERS,
      COMMAND_FILTER_NO_IMMUNITY|COMMAND_FILTER_NO_BOTS,
      target_name,
      sizeof(target_name),
      tn_is_ml)) <= 0)
   {
      ReplyToTargetError(client, target_count);
      return Plugin_Handled;
   }

   decl String:auth[32], String:ip[17], String:country[45];
   new target;

   new bool:is_admin;
   if (client == 0)
      is_admin = true;
   else {
      new AdminId:id = GetUserAdmin(client);
      is_admin = (id != INVALID_ADMIN_ID && GetAdminFlag(id, Admin_Generic));
   }

   for (new i = 0; i < target_count; i++) {
      target = target_list[i];

      GetClientAuthString(target, auth, sizeof(auth));
      ReplyToCommand(client, "\x04%N\x01 %s", target, auth);

      if (is_admin && CanUserTarget(client, target)) {
         GetClientIP(target, ip, sizeof(ip));
         GeoipCountry(ip, country, sizeof(country));

         if (strlen(country))
            ReplyToCommand(client, "  %s", country);
      }

      ReplyToCommand(client, "  Kills: %8d Assists: %4d",
         GetEntProp(target, Prop_Send, "m_iKills"),
         GetEntProp(target, Prop_Send, "m_iKillAssists"));
      ReplyToCommand(client, "  Deaths: %7d Damage: %5d",
         GetEntProp(target, Prop_Send, "m_iDeaths"),
         GetEntProp(target, Prop_Send, "m_iDamageDone"));
      ReplyToCommand(client, "  Dominations: %2d Revenge: %4d",
         GetEntProp(target, Prop_Send, "m_iDominations"),
         GetEntProp(target, Prop_Send, "m_iRevenge"));
      ReplyToCommand(client, "  Headshots: %4d Backstabs: %2d",
         GetEntProp(target, Prop_Send, "m_iHeadshots"),
         GetEntProp(target, Prop_Send, "m_iBackstabs"));
   }

   return Plugin_Handled;
}

public Action:Command_RPS(client, args)
{
   if (args < 1) {
      ShowRPS(client, client);
      return Plugin_Handled;
   }

   new String:arg[64];
   GetCmdArg(1, arg, sizeof(arg));

   decl String:target_name[MAX_TARGET_LENGTH];
   decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;

   if ((target_count = ProcessTargetString(
      arg,
      client,
      target_list,
      MAXPLAYERS,
      COMMAND_FILTER_NO_IMMUNITY|COMMAND_FILTER_NO_BOTS,
      target_name,
      sizeof(target_name),
      tn_is_ml)) <= 0)
   {
      ReplyToTargetError(client, target_count);
      return Plugin_Handled;
   }

   for (new i = 0; i < target_count; i++)
      ShowRPS(client, target_list[i]);

   return Plugin_Handled;
}

ShowRPS(client, target)
{
   ReplyToCommand(client, "[SM] RPS: %N has %d win%s and %d loss%s", target,
      g_RPS[target][0], (g_RPS[target][0] == 1) ? "" : "s",
      g_RPS[target][1], (g_RPS[target][1] == 1) ? "" : "es");
}
