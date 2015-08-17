#pragma semicolon 1

#include <sourcemod>

public Plugin:myinfo =
{
  name = "Votekick Unban",
  author = "Forth",
  description = "Allows non-RCON admins to list and remove temporary bans.",
  version = "1.0"
};

new g_BanID;

new String:g_VoteAuth[4][32];
new String:g_VoteName[4][MAX_NAME_LENGTH];

new Handle:g_Kicks; // Array of kicked Steam IDs
new Handle:g_BanIDs; // Array of currently-active ban IDs
new Handle:g_NameCache; // Hash of Steam IDs and their last-used names

new Handle:g_CvarVoteKickBan;

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
  g_CvarVoteKickBan = FindConVar("sv_vote_kick_ban_duration");
  if (g_CvarVoteKickBan == INVALID_HANDLE) {
    strcopy(error, err_max, "sv_vote_kick_ban_duration not found");
    return APLRes_Failure;
  }

  return APLRes_Success;
}

public OnPluginStart()
{
  RegAdminCmd("sm_getbans", Command_GetBans, ADMFLAG_BAN, "sm_getbans");
  RegAdminCmd("sm_clearban", Command_ClearBan, ADMFLAG_BAN, "sm_clearban <id>");
  RegAdminCmd("sm_clearbans", Command_ClearBans, ADMFLAG_BAN, "sm_clearbans");

  HookUserMessage(GetUserMessageId("VoteStart"), VoteStart);
  HookUserMessage(GetUserMessageId("VotePass"), VotePass);

  g_Kicks = CreateArray(32);
  g_BanIDs = CreateArray();
  g_NameCache = CreateTrie();
}

public Action:VoteStart(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
  new team = BfReadByte(bf);
  if (team > 3) {
    LogError("Expected team value 0-3, got \"%d\"", team);
    team %= 4;
  }

  // Store the vote caller client ID
  new caller = BfReadByte(bf);

  // Ignore votes started via RCON
  if (caller == 99)
    return Plugin_Continue;

  decl String:msg[64];
  BfReadString(bf, msg, sizeof(msg), true);

  // Ignore non-kick votes.
  if (strncmp("#TF_vote_kick_player", msg, 20) != 0)
    return Plugin_Continue;

  decl String:name[MAX_NAME_LENGTH];
  BfReadString(bf, name, sizeof(name), true);

  for (new i=1; i<=MaxClients; i++) {
    decl String:clientname[MAX_NAME_LENGTH];
    if (IsClientConnected(i)) {
      GetClientName(i, clientname, sizeof(clientname));
      if (strcmp(name, clientname) != 0)
        continue;

      strcopy(g_VoteName[team], sizeof(g_VoteName[]), clientname);
      GetClientAuthId(i, AuthId_Steam3, g_VoteAuth[team], sizeof(g_VoteAuth[]));
      return Plugin_Continue;
    }
  }

  LogError("Kick vote started by \"%L\" has name \"%s\" that matched no players",
    caller, name);
  return Plugin_Continue;
}

public Action:VotePass(UserMsg:msg_id, Handle:bf, const players[], playersNum, bool:reliable, bool:init)
{
  new duration = GetConVarInt(g_CvarVoteKickBan);
  if (duration == 0)
    return Plugin_Continue;

  new team = BfReadByte(bf);
  if (team > 3) {
    LogError("Expected team value 0-3, got \"%d\"", team);
    team %= 4;
  }

  if (!g_VoteAuth[team][0]) {
    LogError("No stored votekick target for team \"%d\"", team);
    return Plugin_Continue;
  }

  PushArrayString(g_Kicks, g_VoteAuth[team]);

  if (g_VoteName[team][0]) {
    SetTrieString(g_NameCache, g_VoteAuth[team], g_VoteName[team]);
  }

  PushArrayCell(g_BanIDs, ++g_BanID);
  CreateTimer(duration * 60.0, ExpireBan, g_BanID);

  return Plugin_Handled;
}

public Action:ExpireBan(Handle:timer, any:data)
{
  RemoveVotekickBan(data, _, 1, 0);

  return Plugin_Handled;
}

public Action:Command_GetBans(client, args)
{
  decl String:auth[32], String:name[MAX_NAME_LENGTH];
  new nbans, bid;

  nbans = GetArraySize(g_Kicks);
  ReplyToCommand(client, "[SM] %d active votekick ban%s",
    nbans, (nbans != 1) ? "s" : "");

  for (new i=0; i<GetArraySize(g_Kicks); i++) {
    GetArrayString(g_Kicks, i, auth, sizeof(auth));
    GetTrieString(g_NameCache, auth, name, sizeof(name));
    bid = GetArrayCell(g_BanIDs, i);

    ReplyToCommand(client, "  %2d %16s %s", bid, auth, name);
  }
}

public Action:Command_ClearBan(client, args)
{
  if (args < 1) {
    ReplyToCommand(client, "[SM] Usage: sm_clearban <id>");
    return Plugin_Handled;
  }

  decl String:arg[16];
  GetCmdArg(1, arg, sizeof(arg));

  new id = StringToInt(arg);
  new index = FindValueInArray(g_BanIDs, id);
  if (index == -1) {
    ReplyToCommand(client, "[SM] No bans found with ID %s", arg);
    return Plugin_Handled;
  }

  decl String:auth[32];
  GetArrayString(g_Kicks, index, auth, sizeof(auth));

  decl String:name[MAX_NAME_LENGTH];
  GetTrieString(g_NameCache, auth, name, sizeof(name));

  new bool:ret = RemoveVotekickBan(id);
  if (ret)
    ReplyToCommand(client, "[SM] Successfully removed ban on %s", name);
  else
    ReplyToCommand(client, "[SM] Successfully removed ban on %s", name);

  LogAction(client, -1, "\"%L\" removed votekick ban on \"%s\" (%s)", client, name, auth);
  return Plugin_Handled;
}

public Action:Command_ClearBans(client, args)
{
  new removed, id;

  while (GetArraySize(g_BanIDs) > 0) {
    id = GetArrayCell(g_BanIDs, 0);
    if (RemoveVotekickBan(id))
      removed++;
  }

  ReplyToCommand(client, "[SM] Removed %d votekick ban%s",
    removed, (removed != 1) ? "s" : "");
  LogAction(client, -1, "\"%L\" removed all votekick bans", client);
}

bool:RemoveVotekickBan(banid=0, const String:auth[]="", silent=0, remove=1)
{
  new index;
  decl String:key[32];

  if (banid) {
    index = FindValueInArray(g_BanIDs, banid);
    if (index == -1) {
      if (!silent)
        LogError("Could not find ban with ban ID \"%d\"", banid);

      return false;
    }

    GetArrayString(g_Kicks, index, key, sizeof(key));
  }
  else if (auth[0]) {
    index = FindStringInArray(g_Kicks, auth);
    if (index == -1) {
      if (!silent)
        LogError("Could not find ban with Steam ID \"%s\"", auth);

      return false;
    }

    strcopy(key, sizeof(key), auth);
  }
  else {
    LogError("Cannot remove ban when neither a ban ID or Steam ID are specified");
    return false;
  }

  RemoveFromArray(g_Kicks, index);
  RemoveFromArray(g_BanIDs, index);

  index = FindStringInArray(g_Kicks, key);
  if (index == -1) {
    RemoveFromTrie(g_NameCache, key);

    if (remove)
      RemoveBan(key, BANFLAG_AUTHID);
  }

  return true;
}
