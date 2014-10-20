
#include <sourcemod>
#include <tf2_stocks>

#pragma semicolon 1

public Plugin:myinfo =
{
   name = "Timer Control",
   author = "Forth",
   description = "Disables setup and round timers",
   version = "0.1",
};

new Handle:g_CvarSetupOverride = INVALID_HANDLE;
new Handle:g_CvarDisableRound  = INVALID_HANDLE;

new bool:g_WaitingForPlayers, bool:g_SetupTime, bool:g_RoundStarted;

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
   RegAdminCmd("sm_enabletimer", Command_EnableTimer, ADMFLAG_SLAY);

   g_CvarSetupOverride = CreateConVar("sm_timer_setupoverride", "1",
      "Duration of the setup period, in seconds (0 uses the map default)", _, true, 0.0, true, 60.0);

   g_CvarDisableRound = CreateConVar("sm_timer_disableround", "1",
      "Whether the round timer should be disabled", _, true, 0.0, true, 1.0);

   HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
   HookEntityOutput("team_round_timer", "OnSetupStart", Event_SetupStart);
   HookEntityOutput("team_round_timer", "OnSetupFinished", Event_SetupEnded);
}

public OnMapStart()
{
   g_WaitingForPlayers = false;
   g_SetupTime         = false;
   g_RoundStarted      = false;
}

public TF2_OnWaitingForPlayersStart()
{
   g_WaitingForPlayers = true;
}

public TF2_OnWaitingForPlayersEnd()
{
   g_WaitingForPlayers = false;
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
   g_RoundStarted = true;

   /*
    * For CTF, KOTH, and 5CP, disable the timer if there is no setup period
    * and the waiting for players period has ended.
    */
   if (!g_WaitingForPlayers && !g_SetupTime && GetConVarBool(g_CvarDisableRound))
      EnableTimer(false);
}

public Event_SetupStart(const String:output[], caller, activator, Float:delay)
{
   g_SetupTime = true;

   if (!g_WaitingForPlayers) {
      new time = GetConVarInt(g_CvarSetupOverride);

      // A timer set to 0 will never elapse, so 0 is used as a 'do nothing' value.
      if (time > 0) {
         SetVariantInt(time);
         AcceptEntityInput(caller, "SetSetupTime");
      }
   }
   else
     LogMessage("Setup time not set: Round started? %d, Waiting for players? %d",
        g_RoundStarted ? 1 : 0, g_WaitingForPlayers ? 1 : 0);
}

public Event_SetupEnded(const String:output[], caller, activator, Float:delay)
{
   g_SetupTime = false;

   /*
    * For PL, PLR, A/D, and any other mode that has a setup period, disable
    * the timer when setup ends, as this occurs after the round starts.
    */
   if (GetConVarBool(g_CvarDisableRound)) {
      AcceptEntityInput(caller, "Disable");
   }
}

public EnableTimer(bool:enable)
{
   new String:action[] = "Disable";
   if (enable)
      action = "Enable";

   new entityTimer = MaxClients + 1;
   while((entityTimer = FindEntityByClassname(entityTimer, "team_round_timer"))!=-1) {
      AcceptEntityInput(entityTimer, action);
   }
}

public Action:Command_EnableTimer(client, args)
{
   if (args < 1) {
      ReplyToCommand(client, "[SM] Usage: sm_enabletimer <0|1>");
      return Plugin_Handled;
   }

   decl String:cmdArg[8];
   GetCmdArg(1, cmdArg, sizeof(cmdArg));
   new bool:enable = bool:StringToInt(cmdArg);

   EnableTimer(enable);
   return Plugin_Handled;
}
