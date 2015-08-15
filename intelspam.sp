#include <sourcemod>
#include <sdktools>
#include <tf2_stocks>

public Plugin:myinfo =
{
	name = "TF2 Intel Spam Punishment",
	author = "Forth",
	description = "Kills players who deliberately drop the intel too often",
	version = "1.0"
};

new Handle:g_hCvarDuration = INVALID_HANDLE;

/*
 * The last few intel drops (3 by default) are stored for each player.
 * If all of those drops are more recent than g_Duration seconds ago and
 * the player drops the intel again, they will be slain.
 *
 * When a lone player drops the intel, it takes three seconds for it to
 * automatically be picked back up. The default value of 8 seconds makes
 * it impossible for a player to be slain unless they have a spam partner.
 */
#define MAX_DROPS 3

new g_Duration;
new g_IntelDrops[MAXPLAYERS + 1][MAX_DROPS];

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
	g_hCvarDuration = CreateConVar("sm_intelspam_duration", "8",
		"Seconds to track intel drops for. Players who drop the intel more than 3 times within the time will be slain.");

	HookEvent("teamplay_flag_event", Event_Intel, EventHookMode_Pre);

	AutoExecConfig(true, "plugin.intelspam");

	g_Duration = GetConVarInt(g_hCvarDuration);
	HookConVarChange(g_hCvarDuration, CVar_Duration_Changed);
}

public CVar_Duration_Changed(Handle:cvar, const String:oldVal[], const String:newVal[])
{
	g_Duration = StringToInt(newVal);
}

public OnClientPutInServer(client)
{
	ResetDrops(client);
}

public Action:Event_Intel(Handle:event, const String:name[], bool:dontBroadcast)
{
	new iClient = GetEventInt(event, "player");
	
	// Ensure the client is valid and alive
	if (iClient == 0 || !IsClientInGame(iClient) || !IsPlayerAlive(iClient))
		return Plugin_Continue;
	
	new iEventType = GetEventInt(event, "eventtype");

	// Ignore non-drop events
	if (iEventType != TF_FLAGEVENT_DROPPED)
		return Plugin_Continue;

	// Replace the first event older than g_Duration, or slay the player.
	for (new i=0; i<MAX_DROPS; ++i) {
		if ((GetTime() - g_IntelDrops[iClient][i]) > g_Duration) {
			g_IntelDrops[iClient][i] = GetTime();
			return Plugin_Continue;
		}
	}

	PrintToChatAll("[SM] %N was slain for dropping the intel excessively", iClient);
	LogAction(iClient, -1, "\"%L\" was slain for dropping the intel excessively", iClient);
	ForcePlayerSuicide(iClient);
	ResetDrops(iClient);

	return Plugin_Continue;
}

ResetDrops(client)
{
	for (new i=0; i<MAX_DROPS; ++i)
		g_IntelDrops[client][i] = 0;
}
