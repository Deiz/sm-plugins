#pragma semicolon 1

#include <sdktools>
#include <tf2_stocks>
#include <tf2attributes>
#include <clientprefs>

new Handle:g_Cookie_Enabled;

new bool:g_Enabled[MAXPLAYERS+1];

public void OnPluginStart()
{
	HookEvent("player_spawn", Event_PlayerSpawn);
	HookEvent("post_inventory_application", Event_PlayerSpawn);

	RegConsoleCmd("sm_inspectall", Command_InspectAll, "Toggles inspect all on weapons");

	g_Cookie_Enabled = RegClientCookie("inspectall_enabled", "Enable inspect on all weapons", CookieAccess_Public);
	SetCookiePrefabMenu(g_Cookie_Enabled, CookieMenu_OnOff_Int, "Inspect all weapons");
}

public OnClientDisconnect_Post(client)
{
	g_Enabled[client] = true;
}

public void Event_PlayerSpawn(Handle event, const char[] name, bool dontBroadcast)
{
	int client = GetClientOfUserId(GetEventInt(event, "userid"));
	if (!g_Enabled[client])
		return;

	SetInspect(client, true);
}

public Action:Command_InspectAll(client, args)
{
	if (!AreClientCookiesCached(client)) {
		ReplyToCommand(client, "[SM] Currently unavailable.");
		return Plugin_Handled;
	}

	if (g_Enabled[client]) {
		SetInspect(client, false);
		SetClientCookie(client, g_Cookie_Enabled, "0");
		g_Enabled[client] = false;
	}
	else {
		SetInspect(client, true);
		SetClientCookie(client, g_Cookie_Enabled, "1");
		g_Enabled[client] = true;
	}

	ReplyToCommand(client, "[SM] %s inspect all weapons", g_Enabled[client] ? "Enabled" : "Disabled");

	return Plugin_Handled;
}

public OnClientCookiesCached(client)
{
	decl String:enabled[2]; 
	GetClientCookie(client, g_Cookie_Enabled, enabled, sizeof(enabled));
	g_Enabled[client] = bool:StringToInt(enabled);
}


SetInspect(client, bool:enable)
{
	new Float:value = 1.0;
	if (!enable)
		value = 0.0;

	int Weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Primary);
	if(IsValidEntity(Weapon))
	{
		TF2Attrib_SetByName(Weapon, "weapon_allow_inspect", value);
	}
	
	Weapon = GetPlayerWeaponSlot(client, TFWeaponSlot_Secondary);
	if(IsValidEntity(Weapon))
	{
		TF2Attrib_SetByName(Weapon, "weapon_allow_inspect", value);
	}
}
