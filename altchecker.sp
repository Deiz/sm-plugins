#include <sourcemod>
#include <admin_print>

new Handle:g_DB;

new g_AltCount[MAXPLAYERS+1] = { 0, ... };

new const String:fmt[] =
	"SELECT \
		connect_time, auth, name \
	FROM \
		player_analytics AS t \
	INNER JOIN \
	( \
		SELECT \
			MAX(id) AS max \
		FROM \
			player_analytics \
		WHERE \
			ip = '%s' AND auth != '%s' \
		GROUP BY \
			auth \
	) AS pa \
	ON \
		t.id = pa.max";

public Plugin:myinfo = 
{
	name = "Alt Checker",
	author = "Forth",
	description = "Notifies admins of potential alternate accounts",
	version = "1.0"
};

public OnPluginStart()
{
	LoadTranslations("common.phrases");
	
	RegAdminCmd("sm_alts", Command_Alts, ADMFLAG_BAN, "sm_alts <#userid|name>");
	
	SQL_TConnect(OnDatabaseConnected, "player_analytics");
}

public OnDatabaseConnected(Handle:owner, Handle:hndl, const String:error[], any:data)
{
	if (hndl == INVALID_HANDLE)
		SetFailState("Failed to connect to Player Analytics db, %s", error);
	
	g_DB = hndl;
}

public OnClientPostAdminCheck(client)
{
	g_AltCount[client] = 0;

	if (g_DB == INVALID_HANDLE)
		return;

	new AdminId:adminId = GetUserAdmin(client);
	if (adminId != INVALID_ADMIN_ID && GetAdminFlag(adminId, Admin_Generic))
		return;

	decl String:auth[32];
	GetClientAuthId(client, AuthId_Steam2, auth, sizeof(auth));

	/* Do not check bots nor check player with lan steamid. */
	if(auth[0] == 'B' || auth[9] == 'L')
		return;
	
	decl String:query[512], String:ip[30];

	GetClientIP(client, ip, sizeof(ip));

	FormatEx(query, sizeof(query), fmt, ip, auth);

	SQL_TQuery(g_DB, OnConnectAltCheck, query, GetClientUserId(client), DBPrio_Low);
}

public OnConnectAltCheck(Handle:owner, Handle:hndl, const String:error[], any:userid)
{
	new client = GetClientOfUserId(userid);
	
	if (!client || hndl == INVALID_HANDLE || !SQL_FetchRow(hndl))
		return;
		
	new altcount = SQL_GetRowCount(hndl);
	g_AltCount[client] = altcount;

	if (altcount > 0)
	{
		PrintToChatAdmins(_, "[SM] Player \"%N\" has %d potential alternate account%s",
			client, altcount, (altcount > 1) ? "s" : "")
	}
}

public Action:Command_Alts(client, args)
{
	if (args < 1)
	{
		for (new i=1; i<=MaxClients; i++) {
			if (g_AltCount[i] > 0 && IsClientAuthorized(i))
				ReplyToCommand(client, "[SM] Player \"%N\" has %d potential alternate account%s",
					i, g_AltCount[i], (g_AltCount[i] > 1) ? "s" : "");
		}

		return Plugin_Handled;
	}
	
	if (g_DB == INVALID_HANDLE)
	{
		ReplyToCommand(client, "[SM] Not connected to database");
		return Plugin_Handled;
	}
	
	decl String:targetarg[64];
	GetCmdArg(1, targetarg, sizeof(targetarg));
	
	new target = FindTarget(client, targetarg, true, true);
	if (target == -1)
	{
		return Plugin_Handled;
	}
	
	decl String:auth[32];
	if (!GetClientAuthId(target, AuthId_Steam2, auth, sizeof(auth))
		|| auth[0] == 'B' || auth[9] == 'L')
	{
		ReplyToCommand(client, "[SM] Could not retrieve Steam ID for %N", target);
		return Plugin_Handled;
	}
	
	decl String:query[1024], String:ip[30];
	GetClientIP(target, ip, sizeof(ip));
	FormatEx(query, sizeof(query), fmt, ip, auth);
	
	decl String:targetName[MAX_NAME_LENGTH];
	GetClientName(target, targetName, sizeof(targetName));
	
	new Handle:pack = CreateDataPack();
	WritePackCell(pack, (client == 0) ? 0 : GetClientUserId(client));
	WritePackCell(pack, GetClientUserId(target));
	WritePackString(pack, targetName);
	
	SQL_TQuery(g_DB, OnListAlts, query, pack, DBPrio_Low);
	
	if (client == 0)
	{
		ReplyToCommand(client, "[SM] Note: If you are using this command through an RCON tool, you will not receive results");
	}
	else
	{
		ReplyToCommand(client, "[SM] Results for %N will be displayed in console", target);
	}
	
	return Plugin_Handled;
}

public OnListAlts(Handle:owner, Handle:hndl, const String:error[], any:pack)
{
	ResetPack(pack);
	new clientuid = ReadPackCell(pack);
	new client = GetClientOfUserId(clientuid);

	new targetuid = ReadPackCell(pack);
	new target = GetClientOfUserId(targetuid);

	decl String:targetName[MAX_NAME_LENGTH];
	ReadPackString(pack, targetName, sizeof(targetName));
	CloseHandle(pack);
	
	if (clientuid > 0 && client == 0)
		return;

	if (hndl == INVALID_HANDLE)
	{
		PrintToConsole(client, "[SM] Database error while retrieving bans for %s:\n%s", targetName, error);		
		return;
	}
	
	new altcount = SQL_GetRowCount(hndl);
	if (target != 0)
		g_AltCount[target] = altcount;

	// Do nothing but update the count when called via console
	if (client == 0)
		return;

	if (altcount == 0)
	{
		PrintToConsole(client, "[SM] No alternate accounts found for %s", targetName);
		return;
	}

	PrintToConsole(client, "[SM] Listing alternate accounts for %s", targetName);
	PrintToConsole(client, "Last Connected      Steam ID            Last Name");
	PrintToConsole(client, "------------------------------------------------------------------------");

	while (SQL_FetchRow(hndl))
	{
		decl String:time[20], String:auth[32], String:name[64];

	
		FormatTime(time, sizeof(time), "%Y-%m-%d %H:%M:%S", SQL_FetchInt(hndl, 0));
		SQL_FetchString(hndl, 1, auth, sizeof(auth));
		SQL_FetchString(hndl, 2, name, sizeof(name));

		PrintToConsole(client, "%19s %-19s %s", time, auth, name);
	}
}
