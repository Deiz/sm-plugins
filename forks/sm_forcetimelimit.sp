/*
This program is free software; you can redistribute it and/or
modify it under the terms of the GNU General Public License
as published by the Free Software Foundation; either version 2
of the License, or (at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program; if not, write to the Free Software
Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
*/
//
// SourceMod Script
//
// Developed by <eVa>Dog
// December 2008
// http://www.theville.org
//

#include <sourcemod>
#include <sdktools>
#include <tf2>

// Plugin Version
#define PLUGIN_VERSION "1.1.203"

// Handles
new Handle:g_Enable 	= INVALID_HANDLE;
new Handle:g_MapTimer	= INVALID_HANDLE;

public Plugin:myinfo = 
{
	name = "Force Timelimit",
	author = "<eVa>Dog",
	description = "Forces a map to end at the correct timelimit",
	version = PLUGIN_VERSION,
	url = "http://www.theville.org"
};

public OnPluginStart()
{
	CreateConVar("sm_forcetimelimit_version", PLUGIN_VERSION, "Version of Force Timelimit", FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_REPLICATED|FCVAR_NOTIFY);
	
	g_Enable  = CreateConVar("sm_forcetimelimit_enable", "0", "- enables/disables the plugin", _, true, 0.0, true, 1.0);
}

public OnMapEnd()
{
	g_MapTimer = INVALID_HANDLE;
}

public OnConfigsExecuted()
{
	if (GetConVarInt(g_Enable) == 1 && FindConVar("sm_nextmap") == INVALID_HANDLE)
	{
		LogError("FATAL: Cannot find sm_nextmap cvar. sm_forcetimelimit.smx not loaded");
		SetFailState("sm_nextmap not found");
	}
	SetupTimer();
}

public OnMapTimeLeftChanged()
{
	if (GetConVarInt(g_Enable) == 1)
	{
		SetupTimer();
	}
}

SetupTimer()
{
	if (g_MapTimer != INVALID_HANDLE)
	{
		KillTimer(g_MapTimer);
		g_MapTimer = INVALID_HANDLE;
	}

	new timeleft;
	GetMapTimeLeft(timeleft);

	// mp_timelimit 0 is unlimited
	if (timeleft == -1)
		return;

	new warndelay   = timeleft - 61;
	new changedelay = 60;
	if (timeleft <= changedelay)
	{
		// Too little time to warn normally. Warn immediately and change soon
		changedelay = timeleft - 1;

		// The map should've ended but didn't, so attempt a a graceful switch
		if (timeleft < 1)
			changedelay = 5;

		PrintWarning(float(changedelay));
		g_MapTimer = CreateTimer(float(changedelay), MapChanger, _, TIMER_FLAG_NO_MAPCHANGE);
		return;
	}
	else if (timeleft <= 61 + changedelay)
	{
		// Time left is shorter than (warning period + change delay),
		// shorten the warning period and use a standard change delay
		warndelay = timeleft - changedelay - 1;
	}

	g_MapTimer = CreateTimer(float(warndelay), WarnMapChange, float(changedelay), TIMER_FLAG_NO_MAPCHANGE);
}

PrintWarning(Float:timedelay)
{
	new String:newmap[65];
	GetNextMap(newmap, sizeof(newmap));

	PrintToChatAll("[SM] Map will change to %s in %.0f secs", newmap, timedelay);
	PrintToServer("[SM] Map will change to %s in %.0f secs", newmap, timedelay);
}

public Action:WarnMapChange(Handle:timer, any:timedelay)
{
	PrintWarning(timedelay);
	g_MapTimer = CreateTimer(timedelay, MapChanger, _, TIMER_FLAG_NO_MAPCHANGE);
}

public Action:MapChanger(Handle:timer)
{
	g_MapTimer = INVALID_HANDLE;

	//Routine by Tsunami to end the map
	new iGameEnd  = FindEntityByClassname(-1, "game_end");
	if (iGameEnd == -1 && (iGameEnd = CreateEntityByName("game_end")) == -1) 
	{     
		LogError("Unable to create entity \"game_end\"!");
	} 
	else 
	{     
		AcceptEntityInput(iGameEnd, "EndGame");
	}
}
