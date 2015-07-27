#include <sourcemod>
#include <admin_print>

#pragma semicolon 1

public Plugin:myinfo =
{
   name = "Show Activity Toggle",
   author = "Forth",
   description = "Temporarily modifies sm_show_activity",
   version = "0.1"
}

new Handle:g_CvarShowActivity;
new Handle:g_ResetTimer;

new g_ShowActivityOrig;

public OnPluginStart()
{
   RegAdminCmd("sm_silent", Command_Silent, ADMFLAG_BAN,
      "Temporarily disable player notifications for admin commands");

   RegAdminCmd("sm_zilent", Command_Silent, ADMFLAG_ROOT,
      "Temporarily disable all notifications for admin commands");

   g_CvarShowActivity = FindConVar("sm_show_activity");
   g_ShowActivityOrig = GetConVarInt(g_CvarShowActivity);
}

public OnPluginEnd()
{
   if (g_ResetTimer != INVALID_HANDLE)
      SetConVarInt(g_CvarShowActivity, g_ShowActivityOrig);
}

public OnMapEnd()
{
   if (g_ResetTimer != INVALID_HANDLE) {
      KillTimer(g_ResetTimer);
      g_ResetTimer = INVALID_HANDLE;

      SetConVarInt(g_CvarShowActivity, g_ShowActivityOrig);
   }
}

public Action:Command_Silent(client, args)
{
   new String:cmd[16];
   GetCmdArg(0, cmd, sizeof(cmd));

   new bool:zilent = (strcmp(cmd, "sm_zilent") == 0) ? true : false;

   new Float:duration = 30.0;
   if (args > 0) {
      new String:arg[16];
      GetCmdArg(1, arg, sizeof(arg));

      duration = StringToFloat(arg);
   }

   new current = GetConVarInt(g_CvarShowActivity);

   /*
    * If invoked as sm_silent, and the current sm_show_activity
    * lacks the show-to-admins bit, fail.
    */
   if (!zilent && (current & 4) == 0) {
      ReplyToCommand(client, "[SM] Command notification settings are locked.");
      return Plugin_Handled;
   }

   if (g_ResetTimer != INVALID_HANDLE) {
      KillTimer(g_ResetTimer);
      g_ResetTimer = INVALID_HANDLE;
   }

   new bool:reset = (duration < 1.0) ? true : false;
   new AdminFlag:flag = (zilent) ? Admin_Root : Admin_Generic;
   if (reset) {
      SetConVarInt(g_CvarShowActivity, g_ShowActivityOrig);
      PrintToChatAdmins(flag, "[SM] %N restored command notifications to normal.", client);
      return Plugin_Handled;
   }

   if (zilent) {
      SetConVarInt(g_CvarShowActivity, 0);
      PrintToChatAdmins(flag, "[SM] %N disabled all command notifications for %.1f seconds.",
         client, duration);
   }
   else {
      SetConVarInt(g_CvarShowActivity, g_ShowActivityOrig &~ 1);
      PrintToChatAdmins(flag, "[SM] %N disabled player command notifications for %.1f seconds.",
         client, duration);
   }

   g_ResetTimer = CreateTimer(duration, Timer_ResetShowActivity);

   return Plugin_Handled;
}

public Action:Timer_ResetShowActivity(Handle:timer)
{
   g_ResetTimer = INVALID_HANDLE;

   new AdminFlag:flag = (GetConVarInt(g_CvarShowActivity) == 0) ? Admin_Root : Admin_Generic;
   SetConVarInt(g_CvarShowActivity, g_ShowActivityOrig);
   PrintToChatAdmins(flag, "[SM] Notification settings have been restored to normal.");

   return Plugin_Stop;
}
