#include <sourcemod>
#include <sdkhooks>
#include <tf2_stocks>

#pragma semicolon 1

public Plugin:myinfo =
{
   name = "No Target",
   author = "Forth",
   description = "Disables sentry targeting, airblasting and some other actions for a player",
   version = "1.0"
}

new bool:g_NoTarget[MAXPLAYERS+1] = { false, ... };
new bool:g_NoTargetBuilding[MAXPLAYERS+1] = { false, ... };

public OnPluginStart()
{
   LoadTranslations("common.phrases");

   RegAdminCmd("sm_notarget", Command_NoTarget, ADMFLAG_SLAY,
      "sm_notarget <#userid|name> <0|1>");
   RegAdminCmd("sm_notargetb", Command_NoTargetBuilding, ADMFLAG_SLAY,
      "sm_notargetb <#userid|name> <0|1>");
   RegAdminCmd("sm_listnotarget", Command_ListNoTarget, ADMFLAG_SLAY,
      "sm_listnotarget");

   HookEvent("player_builtobject", Object_Built);
   HookEvent("player_spawn", Player_Spawned);
}

public OnClientPutInServer(client)
{
   g_NoTarget[client] = false;
   g_NoTargetBuilding[client] = false;
}

public SetNoTarget(entity, enable)
{
   new flags = GetEntityFlags(entity);
   if (enable)
      SetEntityFlags(entity, flags |  FL_NOTARGET);
   else
      SetEntityFlags(entity, flags &~ FL_NOTARGET);
}

public Action:Command_NoTarget(client, args)
{
   if (args < 2) {
      ReplyToCommand(client, "[SM] Usage: sm_notarget <#userid|name> <0|1>");
      return Plugin_Handled;
   }

   new String:arg[64];
   GetCmdArg(1, arg, sizeof(arg));

   new String:arg2[16];
   GetCmdArg(2, arg2, sizeof(arg2));

   new bool:enable = bool:StringToInt(arg2);

   decl String:target_name[MAX_TARGET_LENGTH];
   decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;

   if ((target_count = ProcessTargetString(
      arg,
      client,
      target_list,
      MAXPLAYERS,
      COMMAND_FILTER_CONNECTED,
      target_name,
      sizeof(target_name),
      tn_is_ml)) <= 0)
   {
      ReplyToTargetError(client, target_count);
      return Plugin_Handled;
   }

   new String:action[] = "disabled";
   if (enable)
      action = "enabled";

   ShowActivity2(client, "[SM] ", "No Target %s on %s", action, target_name);

   for (new i = 0; i < target_count; i++) {
      g_NoTarget[ target_list[i] ] = enable;
      SetNoTarget(target_list[i], enable);

      LogAction(client, target_list[i], "\"%L\" %s no target on \"%L\"",
         client, action, target_list[i]);
   }

   return Plugin_Handled;
}

public Action:Command_NoTargetBuilding(client, args)
{
   if (args < 2) {
      ReplyToCommand(client, "[SM] Usage: sm_notargetb <#userid|name> <0|1>");
      return Plugin_Handled;
   }

   new String:arg[64];
   GetCmdArg(1, arg, sizeof(arg));

   new String:arg2[16];
   GetCmdArg(2, arg2, sizeof(arg2));

   new bool:enable = bool:StringToInt(arg2);

   decl String:target_name[MAX_TARGET_LENGTH];
   decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;

   if ((target_count = ProcessTargetString(
      arg,
      client,
      target_list,
      MAXPLAYERS,
      COMMAND_FILTER_CONNECTED,
      target_name,
      sizeof(target_name),
      tn_is_ml)) <= 0)
   {
      ReplyToTargetError(client, target_count);
      return Plugin_Handled;
   }

   new String:action[] = "disabled";
   if (enable)
      action = "enabled";

   ShowActivity2(client, "[SM] ", "Building No Target %s on %s", action,
      target_name);

   new ent = -1;
   for (new i = 0; i < target_count; i++) {
      g_NoTargetBuilding[ target_list[i] ] = enable;
      while ((ent = FindEntityByClassname(ent, "obj_*")) != INVALID_ENT_REFERENCE)
         if (GetEntPropEnt(ent, Prop_Send, "m_hBuilder") == target_list[i])
            SetNoTarget(ent, enable);

      LogAction(client, target_list[i], "\"%L\" %s building no target on \"%L\"", client,
         action, target_list[i]);
   }

   return Plugin_Handled;
}

public Action:Command_ListNoTarget(client, args)
{
   for (new i = 1; i <= MaxClients; i++) {
      if (!IsClientInGame(i) || IsFakeClient(i))
            continue;

      new flags = GetEntityFlags(i);
      ReplyToCommand(client, "%40L (Player: %d | Expected: %d | Buildings: %d)",
         i, (flags & FL_NOTARGET) ? 1 : 0, g_NoTarget[i], g_NoTargetBuilding[i]);
   }

   return Plugin_Handled;
}

public Action:Object_Built(Handle:event, const String:name[], bool:dontBroadcast)
{
   new client = GetClientOfUserId(GetEventInt(event, "userid"));
   if (!IsClientInGame(client))
      return Plugin_Continue;

   new ent = GetEventInt(event, "index");
   if (g_NoTargetBuilding[client])
      SetNoTarget(ent, true);

   return Plugin_Continue;
}

public Action:Player_Spawned(Handle:event, const String:name[], bool:dontBroadcast)
{
   new client = GetClientOfUserId(GetEventInt(event, "userid"));
   if (g_NoTarget[client])
      SetNoTarget(client, true);

   return Plugin_Continue;
}
