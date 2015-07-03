/*
**
** Server Hop (c) 2009, 2010 [GRAVE] rig0r
**       www.gravedigger-company.nl
**
*/

#include <sourcemod>
#include <steamtools>

#define PLUGIN_VERSION "0.8.1"
#define MAX_SERVERS 10
#define REFRESH_TIME 30.0
#define SERVER_TIMEOUT 10.0
#define MAX_STR_LEN 160
#define MAX_INFO_LEN 200
//#define DEBUG

new serverCount = 0;
new advertCount = 0;
new lastAdvert = 0;
new String:serverName[MAX_SERVERS][MAX_STR_LEN];
new String:serverAddress[MAX_SERVERS][MAX_STR_LEN];
new serverPort[MAX_SERVERS];
new String:serverInfo[MAX_SERVERS][MAX_INFO_LEN];
new g_PlayerCount[MAX_SERVERS];

new Handle:g_DB;
new Handle:g_Timer;
new String:g_IP[32];

new Handle:cv_hoptrigger = INVALID_HANDLE
new Handle:cv_serverformat = INVALID_HANDLE
new Handle:cv_broadcasthops = INVALID_HANDLE
new Handle:cv_advert = INVALID_HANDLE
new Handle:cv_advert_interval = INVALID_HANDLE

public Plugin:myinfo =
{
  name = "Server Hop",
  author = "[GRAVE] rig0r",
  description = "Provides live server info with join option",
  version = PLUGIN_VERSION,
  url = "http://www.gravedigger-company.nl"
};

public OnPluginStart()
{
  LoadTranslations( "serverhop.phrases" );

  // convar setup
  cv_hoptrigger = CreateConVar( "sm_hop_trigger",
                                "servers",
                                "What players have to type in chat to activate the plugin (besides !hop)" );
  cv_serverformat = CreateConVar( "sm_hop_serverformat",
                                  "%name - %map (%numplayers/%maxplayers)",
                                  "Defines how the server info should be presented" );
  cv_broadcasthops = CreateConVar( "sm_hop_broadcasthops",
                                   "1",
                                   "Set to 1 if you want a broadcast message when a player hops to another server" );
  cv_advert = CreateConVar( "sm_hop_advertise",
                            "1",
                            "Set to 1 to enable server advertisements" );
  cv_advert_interval = CreateConVar( "sm_hop_advertisement_interval",
                                     "1",
                                     "Advertisement interval: advertise a server every x minute(s)" );

  AutoExecConfig( true, "plugin.serverhop" );
  
  CreateTimer(REFRESH_TIME, RefreshServerInfo, _, TIMER_REPEAT);

  RegConsoleCmd("hop", Command_Hop);

  new String:trigger[256];
  GetConVarString(cv_hoptrigger, trigger, sizeof(trigger))
  if (strcmp(trigger, "") != 0)
    RegConsoleCmd(trigger, Command_Hop)

  new String:path[MAX_STR_LEN];
  new Handle:kv;

  BuildPath( Path_SM, path, sizeof( path ), "configs/serverhop.cfg" );
  kv = CreateKeyValues( "Servers" );

  if ( !FileToKeyValues( kv, path ) )
    LogToGame( "Error loading server list" );

  new i;
  KvRewind( kv );
  KvGotoFirstSubKey( kv );
  do {
    KvGetSectionName( kv, serverName[i], MAX_STR_LEN );
    KvGetString( kv, "address", serverAddress[i], MAX_STR_LEN );
    serverPort[i] = KvGetNum( kv, "port", 27015 );
    i++;
  } while ( KvGotoNextKey( kv ) );
  serverCount = i;

  if (Steam_IsConnected())
    UpdateIP();
}

public Action:Command_Hop(client, args)
{
  ServerMenu(client);
  return Plugin_Handled;
}

public Action:ServerMenu( client )
{
  new Handle:menu = CreateMenu( MenuHandler );
  new String:serverNumStr[MAX_STR_LEN];
  new String:menuTitle[MAX_STR_LEN];
  Format( menuTitle, sizeof( menuTitle ), "%T", "SelectServer", client );
  SetMenuTitle( menu, menuTitle );

  for ( new i = 0; i < serverCount; i++ ) {
    if (serverInfo[i][0] != '\0') {
      #if defined DEBUG then
        PrintToConsole( client, serverInfo[i] );
      #endif
      IntToString( i, serverNumStr, sizeof( serverNumStr ) );
      AddMenuItem( menu, serverNumStr, serverInfo[i] );
    }
  } 
  DisplayMenu( menu, client, 20 );
}

public MenuHandler( Handle:menu, MenuAction:action, param1, param2 )
{
  if ( action == MenuAction_Select ) {
    new String:infobuf[MAX_STR_LEN];
    new String:address[MAX_STR_LEN];

    GetMenuItem( menu, param2, infobuf, sizeof( infobuf ) );
    new serverNum = StringToInt( infobuf );

    // header
    new Handle:kvheader = CreateKeyValues( "header" );
    new String:menuTitle[MAX_STR_LEN];
    Format( menuTitle, sizeof( menuTitle ), "%T", "AboutToJoinServer", param1 );
    KvSetString( kvheader, "title", menuTitle );
    KvSetNum( kvheader, "level", 1 );
    KvSetString( kvheader, "time", "10" );
    CreateDialog( param1, kvheader, DialogType_Msg );
    CloseHandle( kvheader );
    
    // join confirmation dialog
    new Handle:kv = CreateKeyValues( "menu" );
    KvSetString( kv, "time", "10" );
    Format( address, MAX_STR_LEN, "%s:%i", serverAddress[serverNum], serverPort[serverNum] );
    KvSetString( kv, "title", address );
    CreateDialog( param1, kv, DialogType_AskConnect );
    CloseHandle( kv );

    // broadcast to all
    if ( GetConVarBool( cv_broadcasthops ) ) {
      new String:clientName[MAX_NAME_LENGTH];
      GetClientName( param1, clientName, sizeof( clientName ) );
      PrintToChatAll( "\x04[\x03hop\x04]\x01 %t", "HopNotification", clientName, serverInfo[serverNum] );
    }
  }
}

public Action:CleanUp( Handle:timer )
{
  // all server info is up to date: advertise
  if (GetConVarBool(cv_advert)) {
    if (GetTime() >= (lastAdvert + GetConVarInt(cv_advert_interval) * 60)) {
      Advertise();
      lastAdvert = GetTime();
    }
  }
}

public Action:Advertise()
{
  new String:trigger[MAX_STR_LEN];
  GetConVarString( cv_hoptrigger, trigger, sizeof( trigger ) );
  Format(trigger, sizeof(trigger), "!%s", trigger);

  // skip servers being marked as down
  new max = serverCount;

  while (serverInfo[advertCount][0] == '\0' || g_PlayerCount[advertCount] == 0) {
    #if defined DEBUG then
      LogError( "Not advertising down server %i", advertCount );
    #endif
    advertCount++;
    if ( advertCount >= serverCount )
      advertCount = 0;

    if (max-- < 0)
      break;
  }

  if (serverInfo[advertCount][0] != '\0') {
    PrintToChatAll( "\x04[\x03hop\x04]\x01 %t", "Advert", serverInfo[advertCount], trigger );
    #if defined DEBUG then
      LogError( "Advertising server %i (%s)", advertCount, serverInfo[advertCount] );
    #endif

    advertCount++;
    if ( advertCount >= serverCount ) {
      advertCount = 0;
    }
  }
}

public OnMapStart()
{ 
  DatabaseConnect(INVALID_HANDLE);
}

public Action:RefreshServerInfo(Handle:timer)
{ 
  for (new i=0; i<serverCount; i++)
    serverInfo[i][0] = '\0';
  
  decl String:map[128];
  decl String:query[512];
  new players;
  
  if (g_DB == INVALID_HANDLE)
    return Plugin_Continue;

  if (g_IP[0] == '\0') {
    LogError("Could not get public IP, trying to parse status output");

    new String:buf[512];
    ServerCommandEx(buf, sizeof(buf), "status");

    new String:fragment[] = "(public ip: ";

    new idx = StrContains(buf, fragment, true);
    if (idx != -1) {
      new start = idx + strlen(fragment);

      new i = start;
      while (i < sizeof(buf) && buf[i] != '\0' && buf[i] != ')')
        i++;

      if (i - start < sizeof(g_IP)) {
        strcopy(g_IP, i - start + 1, buf[start]);
        Format(buf, sizeof(buf), "%s:%d", g_IP, GetConVarInt(FindConVar("hostport")));
        strcopy(g_IP, sizeof(g_IP), buf);
        LogMessage("Got public IP from status: %s", g_IP);
      }
    }
    else
      LogError("Could not get public IP from status output");
  }

  if (g_IP[0] != '\0') {
    GetCurrentMap(map, sizeof(map));
    players = GetPlayerCount();

    new maxplayers;
    new visiblemax = GetConVarInt(FindConVar("sv_visiblemaxplayers"));
    if (visiblemax != -1)
      maxplayers = visiblemax;
    else
      maxplayers = GetMaxHumanPlayers(); 

    Format(query, sizeof(query), "INSERT INTO `server_info` (server_ip, update_time, numplayers, maxplayers, map) VALUES ('%s', %d, %d, %d, '%s') ON DUPLICATE KEY UPDATE update_time = VALUES(update_time), numplayers = VALUES(numplayers), maxplayers = VALUES(maxplayers), map = VALUES(map)",
      g_IP, GetTime(), players, maxplayers, map);
    SQL_TQuery(g_DB, OnInfoPushed, query);
  }
  
  new String:hostnames[MAX_SERVERS * 32];
  new written = 0;

  // Build a list of server hostnames, e.g. (x, y, z)
  for (new i=0; i<serverCount; i++) {
    decl String:hostname[32];
    Format(hostname, sizeof(hostname), "%s:%d", serverAddress[i], serverPort[i]);
    
    written += Format(hostnames[written], sizeof(hostnames) - written, "'%s',", hostname);
  }

  if (written)
    hostnames[written - 1] = '\0';
  
  Format(query, sizeof(query), "SELECT server_ip, update_time, numplayers, maxplayers, map FROM `server_info` WHERE server_ip IN (%s)",
    hostnames);
  
  SQL_TQuery(g_DB, OnInfoRetrieved, query);

  CreateTimer(5.0, CleanUp, _, TIMER_FLAG_NO_MAPCHANGE);
  return Plugin_Continue;
}

public Steam_SteamServersConnected()
{ 
  UpdateIP();
}

public Action:DatabaseConnect(Handle:timer)
{ 
  if (g_DB == INVALID_HANDLE) {
    if (SQL_CheckConfig("server_hop"))
      SQL_TConnect(OnDatabaseConnected, "server_hop");
    else
      SQL_TConnect(OnDatabaseConnected, "default");
  }
  
  g_Timer = INVALID_HANDLE;
}

UpdateIP()
{ 
  new octets[4];
  Steam_GetPublicIP(octets);
  
  Format(g_IP, sizeof(g_IP), "%d.%d.%d.%d:%d", octets[0], octets[1], octets[2], octets[3],
    GetConVarInt(FindConVar("hostport")));
}

public OnDatabaseConnected(Handle:owner, Handle:hndl, const String:error[], any:data)
{ 
  if (hndl == INVALID_HANDLE) { 
    LogError("Database failure: %s", error);
    if (g_Timer == INVALID_HANDLE) 
      g_Timer = CreateTimer(120.0, DatabaseConnect, _, TIMER_FLAG_NO_MAPCHANGE);
    
    return;
  }
  
  g_DB = hndl;
  SQL_TQuery(g_DB, OnTableCreated, "CREATE TABLE IF NOT EXISTS `server_info` (server_ip varchar(32) NOT NULL, update_time int(11) NOT NULL, numplayers tinyint(4) NOT NULL, maxplayers tinyint(4) NOT NULL, map varchar(128) NOT NULL, PRIMARY KEY (server_ip)) ENGINE=InnoDB DEFAULT CHARSET=utf8");
}

public OnTableCreated(Handle:owner, Handle:hndl, const String:error[], any:data)
{ 
  if (hndl == INVALID_HANDLE)
    SetFailState("Unable to create table: %s", error);
  
  RefreshServerInfo(INVALID_HANDLE);
}

public OnInfoPushed(Handle:owner, Handle:hndl, const String:error[], any:data)
{ 
  if (hndl == INVALID_HANDLE) {
    LogError("Failed to push server info: %s", error);
    return;
  }
}

public OnInfoRetrieved(Handle:owner, Handle:hndl, const String:error[], any:data)
{
  if (hndl == INVALID_HANDLE) {
    LogError("Failed to retrieve server info: %s", error);
    return;
  }

  decl String:hostname[32];
  decl String:fmt[160], String:formatted[160];
  decl String:buf[32];
  decl String:map[128];
  new update_time, numplayers, maxplayers;

  GetConVarString(cv_serverformat, fmt, sizeof(fmt));

  new bool:seen[MAX_SERVERS] = { false, ... };

  while (SQL_FetchRow(hndl)) {
    SQL_FetchString(hndl, 0, hostname, sizeof(hostname));

    new matched = -1;
    for (new i=0; i<serverCount; i++) {
      Format(buf, sizeof(buf), "%s:%d", serverAddress[i], serverPort[i]);
      if (strcmp(hostname, buf) == 0) {
        seen[i] = true;
        matched = i;
        break;
      }
    }

    if (matched < 0) {
      LogError("Got hostname \"%s\" that did not match anything configured",
        hostname);

      continue;
    }

    update_time = SQL_FetchInt(hndl, 1);

    if (update_time < (GetTime() - 60)) {
      LogMessage("Data for \"%s\" is stale, server may be down", hostname);
      continue;
    }
    numplayers = SQL_FetchInt(hndl, 2);
    maxplayers = SQL_FetchInt(hndl, 3);

    g_PlayerCount[matched] = numplayers;

    SQL_FetchString(hndl, 4, map, sizeof(map));

    strcopy(formatted, sizeof(formatted), fmt);
    ReplaceString(formatted, sizeof(formatted), "%name", serverName[matched], false);
    ReplaceString(formatted, sizeof(formatted), "%map", map, false);

    Format(buf, sizeof(buf), "%d", numplayers);
    ReplaceString(formatted, sizeof(formatted), "%numplayers", buf, false);

    Format(buf, sizeof(buf), "%d", maxplayers);
    ReplaceString(formatted, sizeof(formatted), "%maxplayers", buf, false);
    serverInfo[matched] = formatted;
  }

  for (new i=0; i<serverCount; i++)
    if (!seen[i])
      LogMessage("No entry for server \"%s\" was found in the database", serverName[i]);
}

GetPlayerCount()
{
  new players = 0;
  for (new i=1; i<=MaxClients; i++)
    if (IsClientConnected(i) && !IsFakeClient(i))
      players++;

  return players;
}
