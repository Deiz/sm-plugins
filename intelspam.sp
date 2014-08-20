#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>

public Plugin:myinfo =
{
	name = "TF2 Intel Spam Punishment",
	author = "Forth",
	description = "Kills players who deliberately drop the intel too often in a specified time.",
	version = "1.0"
};

new Handle:g_hCvarDuration = INVALID_HANDLE;

const g_maxDrops = 3;
new g_Duration;
new g_IntelDrops[MAXPLAYERS + 1][g_maxDrops];

public OnPluginStart ()
{
	g_hCvarDuration = CreateConVar("sm_intelspam_duration", "10",
		"Maximum duration to store intel drops for.");

	AutoExecConfig(true, "plugin.intelspam");
	HookEvent("teamplay_flag_event", Event_Intel, EventHookMode_Pre);

	HookConVarChange(g_hCvarDuration, CVar_Duration_Changed);
	g_Duration = GetConVarInt(g_hCvarDuration);
}

public CVar_Duration_Changed (Handle:cvar, const String:oldVal[], const String:newVal[])
{
	g_Duration = StringToInt(newVal);
}

public OnClientDisconnect (client)
{
	g_IntelDrops[client] = {0, 0, 0};
}

public Action:Event_Intel(Handle:event,  const String:name[], bool:dontBroadcast)
{
	// Fetch the client who triggered the event.
	new iClient = GetEventInt(event, "player");
	
	// Make sure the client is valid.
	if (iClient == 0 || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
		return Plugin_Continue;
	
	new iEventType = GetEventInt(event, "eventtype");

	//Make sure this is a pickup or drop event, otherwise we do nothing.
	if (iEventType != TF_FLAGEVENT_DROPPED)
		return Plugin_Continue;

	for (new i=0; i<g_maxDrops; ++i) {
		if ((GetTime() - g_IntelDrops[iClient][i]) > g_Duration) {
			g_IntelDrops[iClient][i] = GetTime();
			return Plugin_Continue;
		}
	}

	LogAction(iClient, -1, "\"%L\" was slain for dropping the intel excessively", iClient);
	ForcePlayerSuicide(iClient);
	return Plugin_Continue;
}
