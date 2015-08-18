#include <sourcemod>
#include <tf2_stocks>
#include <killtracker>

#pragma semicolon 1

public Plugin:myinfo =
{
  name = "Kill Tracker",
  author = "Forth",
  description = "Stores unique victim information for each player",
  version = "1.1"
}

functag VictimCallback public(
  const String:killer[], const String:victim[], Handle:kills, &any:data
);

new Handle:g_UniqueVictimAddedForward;
new Handle:g_PlayerKilledForward;

new Handle:g_CvarEnabled;

new bool:g_bWaitingForPlayers;
new bool:g_bBonusRound;

// ( killer => { victim => [timestamp, timestamp2] } )
new Handle:g_KillData;

// Array of keys in the first level of g_KillData
new Handle:g_Killers;

// Array of arrays with keys for the second level of g_KillData
new Handle:g_Victims;

new String:g_CachedID[MAXPLAYERS+1][32];

new bool:g_bEnabled;
new bool:g_bLateLoad;

new g_LastPruned;
new g_RetentionTime;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
  if (GetEngineVersion() != Engine_TF2) { 
    strcopy(error, err_max, "Plugin only works on Team Fortress 2.");
    return APLRes_Failure;
  }

  CreateNative("KillTracker_UniqueVictims", Native_UniqueVictims);
  CreateNative("KillTracker_TotalKills", Native_TotalKills);
  CreateNative("KillTracker_FirstKill", Native_FirstKill);
  RegPluginLibrary("killtracker");

  g_bLateLoad = late;
  return APLRes_Success;
}

public OnPluginStart()
{
  LoadTranslations("common.phrases");

  g_CvarEnabled = CreateConVar("sm_killtracker_enabled", "1",
    "Whether kill tracking is enabled");

  HookConVarChange(g_CvarEnabled, OnEnabledChanged);
  g_bEnabled = GetConVarBool(g_CvarEnabled);

  RegConsoleCmd("sm_victims", Command_Victims, "sm_victims [#userid|name]");
  RegAdminCmd("sm_killprune", Command_KillPrune, ADMFLAG_ROOT);

  HookEvent("player_death", Event_PlayerDeath, EventHookMode_Post);
  HookEvent("teamplay_round_win", Event_RoundWin, EventHookMode_Post);
  HookEvent("teamplay_round_start", Event_RoundStart, EventHookMode_Post);

  g_KillData = CreateTrie();
  g_Killers = CreateArray(32);
  g_Victims = CreateArray();

  if (g_bLateLoad) {
    decl String:tmp[32];
    for (new i=1; i<=MaxClients; i++) {
      if (IsClientAuthorized(i)) {
        GetClientAuthId(i, AuthId_Steam3, tmp, sizeof(tmp));
        if (strcmp(tmp, "BOT") == 0)
          Format(g_CachedID[i], sizeof(g_CachedID[]), "BOT%d", i);
        else
          strcopy(g_CachedID[i], sizeof(g_CachedID[]), tmp);
      }
    }
  }

  g_UniqueVictimAddedForward = CreateGlobalForward("OnUniqueVictimAdded",
    ET_Ignore, Param_Cell, Param_Cell);
  g_PlayerKilledForward = CreateGlobalForward("OnPlayerKilled",
    ET_Ignore, Param_Cell, Param_Cell);

  g_RetentionTime = 2400;

  CreateTimer(300.0, PruneTimer, g_RetentionTime, TIMER_REPEAT);
}

public OnEnabledChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
  g_bEnabled = GetConVarBool(convar);
}

public OnClientAuthorized(client, const String:auth[])
{
  if (strcmp(auth, "BOT") == 0) {
    g_CachedID[client][0] = '\0';
    Format(g_CachedID[client], sizeof(g_CachedID[]), "%d", client);
  }
  else
    GetClientAuthId(client, AuthId_Steam3, g_CachedID[client], sizeof(g_CachedID[]));
}

public OnClientDisconnect_Post(client)
{
  g_CachedID[client][0] = '\0';
}

public TF2_OnWaitingForPlayersStart()
{
  g_bWaitingForPlayers = true;
}

public TF2_OnWaitingForPlayersEnd()
{
  g_bWaitingForPlayers = false;
}

public Event_PlayerDeath(Handle:event, const String:name[], bool:dontBroadcast)
{
  if (!g_bEnabled || g_bWaitingForPlayers || g_bBonusRound)
    return;

  new victim = GetClientOfUserId(GetEventInt(event, "userid"));
  new killer = GetClientOfUserId(GetEventInt(event, "attacker"));

  // Ignore environmental kills and suicides
  if (killer < 1 || killer > MaxClients || killer == victim)
    return;

  if (!g_CachedID[victim][0] || !g_CachedID[killer][0])
    return;

  if (GetEventInt(event, "death_flags") & TF_DEATHFLAG_DEADRINGER)
    return;

  // We need to maintain three parallel sets of data.
  // The first is a hash of hashes of arrays:
  //   g_KillData = ( killer => { victim1 => [timestamp, ...], ... }, ... );
  // The second is an array of keys to the g_KillData hash:
  //   g_Killers = [ killer, killer2, ... ];
  // The third is an array of arrays of keys to the g_KillData child hashes:
  //   g_Victims[killer] = [ victim, victim2, ... ];

  new Handle:killerhash, Handle:killvictimarray, Handle:victimarray;

  // Create g_KillData[killer] hash if not present
  if (!GetTrieValue(g_KillData, g_CachedID[killer], killerhash)) {
    killerhash = CreateTrie();
    SetTrieValue(g_KillData, g_CachedID[killer], killerhash);

    // Add killer Steam ID to key list
    PushArrayString(g_Killers, g_CachedID[killer]);

    // Add array for Steam IDs of victims of the killer
    victimarray = CreateArray(32);
    PushArrayCell(g_Victims, victimarray);
  }

  if (victimarray == INVALID_HANDLE) {
    new index = FindStringInArray(g_Killers, g_CachedID[killer]);
    if (index == -1) {
      LogError("Could not locate killer \"%L\" in killers array", killer);
      return;
    }

    victimarray = GetArrayCell(g_Victims, index);
  }

  // Create g_KillData[killer][victim] array if not present
  if (!GetTrieValue(killerhash, g_CachedID[victim], killvictimarray)) {
    killvictimarray = CreateArray();
    SetTrieValue(killerhash, g_CachedID[victim], killvictimarray);

    PushArrayString(victimarray, g_CachedID[victim]);

    Call_StartForward(g_UniqueVictimAddedForward);
    Call_PushCell(killer);
    Call_PushCell(GetTrieSize(killerhash));
    Call_Finish();
  }

  PushArrayCell(killvictimarray, GetTime());

  Call_StartForward(g_PlayerKilledForward);
  Call_PushCell(victim);
  Call_PushCell(killer);
  Call_Finish();
}

public Event_RoundStart(Handle:event, const String:name[], bool:dontBroadcast)
{
  g_bBonusRound = false;
}

public Event_RoundWin(Handle:event, const String:name[], bool:dontBroadcast)
{
  g_bBonusRound = true;
}

public Native_UniqueVictims(Handle:hPlugin, numParams)
{
  new client = GetNativeCell(1);
  if (client < 1 || client > MaxClients) {
    return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
  }

  if (!IsClientAuthorized(client)) {
    return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not authorized", client);
  }

  new newerthan = 0;
  if (numParams > 1)
    newerthan = GetNativeCell(2);

  return UniqueVictims(client, newerthan);
}

public Native_TotalKills(Handle:hPlugin, numParams)
{
  new client = GetNativeCell(1);
  if (client < 1 || client > MaxClients) {
    return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);
  }

  if (!IsClientAuthorized(client)) {
    return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not authorized", client);
  }

  if (!g_CachedID[client][0])
    return ThrowNativeError(SP_ERROR_NATIVE, "Client \"%L\" does not have a cached Steam ID", client);

  // A player with no kills will not have a key in the killers hash
  new index = FindStringInArray(g_Killers, g_CachedID[client]);
  if (index < 0)
    return 0;

  new newerthan = 0;
  if (numParams > 1)
    newerthan = GetNativeCell(2);

  return ScanVictims(client, TotalKills_Callback, newerthan);
}

public Native_FirstKill(Handle:hPlugin, numParams)
{
  new client = GetNativeCell(1);
  if (client < 1 || client > MaxClients)
    return ThrowNativeError(SP_ERROR_NATIVE, "Invalid client index %d", client);

  if (!IsClientAuthorized(client))
    return ThrowNativeError(SP_ERROR_NATIVE, "Client %d is not authorized", client);

  if (!g_CachedID[client][0])
    return ThrowNativeError(SP_ERROR_NATIVE, "Client \"%L\" does not have a cached Steam ID", client);

  // A player with no kills will not have a key in the killers hash
  new index = FindStringInArray(g_Killers, g_CachedID[client]);
  if (index < 0)
    return 0;

  new oldest = GetTime();
  ScanVictims(client, FirstKill_Callback, oldest);

  return oldest;
}

UniqueVictims(client, newerthan=0)
{
  if (!g_CachedID[client][0]) {
    LogError("Client \"%L\" does not have a cached Steam ID", client);
    return -1;
  }

  // A player with no kills will not have a key in the killers hash
  new index = FindStringInArray(g_Killers, g_CachedID[client]);
  if (index < 0)
    return 0;

  new Handle:victims = GetArrayCell(g_Victims, index);

  if (newerthan <= g_LastPruned - g_RetentionTime)
    return GetArraySize(victims);

  return ScanVictims(client, UniqueVictims_Callback, newerthan);
}

public Action:Command_Victims(client, args)
{
  if (args < 1) {
    for (new i=1; i<=MaxClients; i++)
      if (IsClientAuthorized(i))
        PrintVictims(client, i);

    return Plugin_Handled;
  }

  decl String:arg[MAX_TARGET_LENGTH];
  GetCmdArg(1, arg, sizeof(arg));

  decl String:target_name[MAX_TARGET_LENGTH];
  decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;

  if ((target_count = ProcessTargetString(
    arg,
    client,
    target_list,
    MAXPLAYERS,
    0,
    target_name,
    sizeof(target_name),
    tn_is_ml)) <= 0)
  {
    ReplyToTargetError(client, target_count);
    return Plugin_Handled;
  }

  new victims;
  for (new i=0; i<target_count; i++) {
    victims = PrintVictims(client, target_list[i]);
    if (!victims)
      ReplyToCommand(client, "[SM] %N has no victims", target_list[i]);
  }

  return Plugin_Handled;
}

PrintVictims(client, target)
{
  new Handle:killerdata, Handle:victimdata;
  new bool:ret;

  ret = GetTrieValue(g_KillData, g_CachedID[target], killerdata);
  if (!ret)
    return 0;

  new index = FindStringInArray(g_Killers, g_CachedID[target]);
  if (index < 0) {
    LogError("Client \"%L\" is present in g_KillData, but not g_Killers", target);
    return 0;
  }

  new printed;
  new nvictims = GetTrieSize(killerdata);

  new nkills = KillTracker_TotalKills(target);

  ReplyToCommand(client, "[SM] %N has %d unique victim%s, %d kill%s",
    target, nvictims, (nvictims == 1) ? "" : "s",
    nkills, (nkills == 1) ? "" : "s");

  for (new j=1; j<=MaxClients; j++) {
    if (IsClientAuthorized(j)) {
      ret = GetTrieValue(killerdata, g_CachedID[j], victimdata);
      if (ret) {
        ReplyToCommand(client, "  %2d %N", GetArraySize(victimdata), j);
        printed++;
      }
    }
  }

  if (printed < nvictims)
    ReplyToCommand(client, " + %d disconnected victim%s", nvictims - printed,
      (nvictims - printed) == 1 ? "" : "s");

  return nvictims;
}

public Action:Command_KillPrune(client, args)
{
  decl String:arg[16];
  new value = 3600;

  if (args) {
    GetCmdArg(1, arg, sizeof(arg));
    value = StringToInt(arg);
  }

  ReplyToCommand(client, "Pruning kills older than %d", value);
  PruneKills(value);

  return Plugin_Handled;
}

public Action:PruneTimer(Handle:timer, any:data)
{
  PruneKills(data);
  g_LastPruned = GetTime();

  return Plugin_Continue;
}

PruneKills(threshold)
{
  new Handle:victims, Handle:killerdata, Handle:victimdata;
  decl String:killer[32], String:victim[32];

  new time = GetTime();

  for (new i=0; i<GetArraySize(g_Killers); i++) {
    GetArrayString(g_Killers, i, killer, sizeof(killer));
    victims = GetArrayCell(g_Victims, i);

    GetTrieValue(g_KillData, killer, killerdata);

    for (new j=0; j<GetArraySize(victims); j++) {
      GetArrayString(victims, j, victim, sizeof(victim));
      GetTrieValue(killerdata, victim, victimdata);

      for (new k=0; k<GetArraySize(victimdata); k++) {
        new timestamp = GetArrayCell(victimdata, k);

        // Prune outdated kill
        if (timestamp < time - threshold)
          RemoveFromArray(victimdata, k--);
      }

      // No kills remain, remove victim
      if (!GetArraySize(victimdata)) {
        CloseHandle(victimdata);
        RemoveFromTrie(killerdata, victim);

        RemoveFromArray(victims, j--);
      }
    }

    // No victims remain, remove killer
    if (!GetArraySize(victims)) {
      CloseHandle(victims);
      CloseHandle(killerdata);

      RemoveFromTrie(g_KillData, killer);
      RemoveFromArray(g_Killers, i);
      RemoveFromArray(g_Victims, i--);
    }
  }
}

ScanVictims(client, VictimCallback:callback, &any:data)
{
  if (!g_CachedID[client][0]) {
    LogError("Client \"%L\" does not have a cached Steam ID", client);
    return -1;
  }

  // A player with no kills will not have a key in the killers hash
  new index = FindStringInArray(g_Killers, g_CachedID[client]);
  if (index < 0)
    return 0;

  new Handle:killerdata, Handle:victimdata;
  new bool:success;

  success = GetTrieValue(g_KillData, g_CachedID[client], killerdata);
  if (!success) {
    LogError("Could not get kill data for \"%L\"", client);
    return -1;
  }

  new ret, sum;
  decl String:victim[32];

  new Handle:victims = GetArrayCell(g_Victims, index);

  for (new i=0; i<GetArraySize(victims); i++) {
    GetArrayString(victims, i, victim, sizeof(victim));
    success = GetTrieValue(killerdata, victim, victimdata);
    if (!success) {
      LogError("Could not get victim data for \"%L\"", client);
      continue;
    }

    Call_StartFunction(INVALID_HANDLE, callback);
    Call_PushString(g_CachedID[client]);
    Call_PushString(victim);
    Call_PushCell(victimdata);
    Call_PushCellRef(data);
    Call_Finish(ret);

    sum += ret;
  }

  return sum;
}

public FirstKill_Callback(const String:killer[], const String:victim[],
  Handle:kills, &any:data)
{
  new time = GetArrayCell(kills, 0);
  if (time < data)
    data = time;

  return 0;
}

public TotalKills_Callback(const String:killer[], const String:victim[],
  Handle:kills, &any:data)
{
  if (data <= g_LastPruned - g_RetentionTime)
    return GetArraySize(kills);

  new sum;

  for (new i=0; i<GetArraySize(kills); i++)
    if (GetArrayCell(kills, i) > data)
      sum++;

  return sum;
}

public UniqueVictims_Callback(const String:killer[], const String:victim[],
  Handle:kills, &any:data)
{
  if (GetArrayCell(kills, GetArraySize(kills) - 1) > data)
    return 1;

  return 0;
}
