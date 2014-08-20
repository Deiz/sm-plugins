#include <sourcemod>
#include <tf2>
#include <tf2_stocks>
#include <sdktools>
#include <basecomm>

#pragma semicolon 1

public Plugin:myinfo =
{
  name = "Round Start",
  author = "Forth",
  version = "1.0"
}

new g_lastRoundStart;

public OnPluginStart()
{
  RegConsoleCmd("sm_roundstart", Command_RoundStart,  "sm_roundstart");
  RegConsoleCmd("sm_score", Command_RoundScore,  "sm_score");
  HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_PostNoCopy);
}

public Action:Command_RoundStart(client, args)
{
  PrintRoundStart(client, false);
  return Plugin_Handled;
}

public Action:Command_RoundScore(client, args)
{
  new redIndex  = -1;
  new blueIndex = -1;
  new iTeam     = -1;
  new iTeamNum;

  while ((iTeam = FindEntityByClassname2(iTeam, "tf_team")) != -1) {
    iTeamNum = GetEntProp(iTeam, Prop_Send, "m_iTeamNum");

    switch (TFTeam:iTeamNum) {
      case TFTeam_Red:
        redIndex = iTeam;
      case TFTeam_Blue:
        blueIndex = iTeam;
    }
  }

  new redCaps  = GetEntProp(redIndex,  Prop_Send, "m_nFlagCaptures");
  new blueCaps = GetEntProp(blueIndex, Prop_Send, "m_nFlagCaptures");

  ReplyToCommand(client, "[SM] Overall: RED %2d, BLU %2d | Current Captures: RED %2d, BLUE %2d",
    GetTeamScore(2), GetTeamScore(3), redCaps, blueCaps);
  return Plugin_Handled;
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
  g_lastRoundStart = GetTime();
}

public OnClientSayCommand_Post(client, const String:command[], const String:sArgs[])
{
  if (strcmp(sArgs, "roundstart", false) == 0)
    PrintRoundStart(client, true);
}

public PrintRoundStart(client, all)
{
  decl String:reply[128] = "[SM] No round start has occurred";

  if (g_lastRoundStart) {
    new delta =  GetTime() - g_lastRoundStart;

    new days    = delta / 86400;
    new hours   = (delta / 3600) % 24;
    new minutes = (delta / 60) % 60;
    new seconds = delta % 60;
    
    decl String:since[64];
    if (days > 0)
      Format(since, sizeof(since), "%dd %dh %dm %ds", days, hours, minutes, seconds);
    else if (hours > 0)
      Format(since, sizeof(since), "%dh %dm %ds", hours, minutes, seconds);
    else if (minutes > 0)
      Format(since, sizeof(since), "%dm %ds", minutes, seconds);
    else
      Format(since, sizeof(since), "%ds", seconds);

    decl String:time[64];
    FormatTime(time, sizeof(time), "%F %T %Z", g_lastRoundStart);

    Format(reply, sizeof(reply), "[SM] Round started at %s (%s ago)", time, since);
  }

  if (all)
    PrintToChatAll(reply);
  else if (client)
    PrintToChat(client, reply);
  else
    ReplyToCommand(client, reply);
}

stock FindEntityByClassname2(startEnt, const String:classname[])
{
  /* If startEnt isn't valid shifting it back to the nearest valid one */
  while (startEnt > -1 && !IsValidEntity(startEnt)) startEnt--;
  return FindEntityByClassname(startEnt, classname);
}
