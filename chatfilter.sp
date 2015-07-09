#include <sourcemod>
#include <regex>
#include <tf2_stocks>
#include <sdktools>

#define REQUIRE_PLUGIN
#include <scp>

#define CONFIG_PATH "configs/chatfilter.txt"

/* Array of regex strings to match messages with. */
new Handle:g_FilterStrings;

/* Array of compiled regexes. */
new Handle:g_Regexes;

/* Array of punishment bitmasks for each regex. */
new Handle:g_FilterMasks;

/* Array of arrays with punishment data for each pattern (length, damage) */
new Handle:g_FilterData;

new g_nFilters;

new Handle:g_LastTrigger[MAXPLAYERS+1];

new String:g_Actions[][] = {
  "suppress",
  "bleed",
  "ignite",
  "kick",
  "slay",
  "stun",
  "slap",
  "milk",
  "jarate",
  "markfordeath",
  "markfordeathsilent"
};

enum actionIndexes {
  IND_SUPPRESS = 0,
  IND_BLEED,
  IND_IGNITE,
  IND_KICK,
  IND_SLAY,
  IND_STUN,
  IND_SLAP,
  IND_MILK,
  IND_JARATE,
  IND_MARKFORDEATH,
  IND_MARKFORDEATHSILENT
};

#define ACTION_SUPPRESS (1 << 0)
#define ACTION_BLEED    (1 << 1)
#define ACTION_IGNITE   (1 << 2)
#define ACTION_KICK     (1 << 3)
#define ACTION_SLAY     (1 << 4)
#define ACTION_STUN     (1 << 5)
#define ACTION_SLAP     (1 << 6)
#define ACTION_MILK     (1 << 7)
#define ACTION_JARATE   (1 << 8)
#define ACTION_MARKFORDEATH (1 << 9)
#define ACTION_MARKFORDEATHSILENT (1 << 10)

#define ACTION_HASDATA (1 << 31)

public Plugin:myinfo =
{
  name        = "Chat Filter",
  author      = "Forth",
  description = "Filters and optionally punishes based on chat messages.",
  version     = "0.1",
};

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
  RegAdminCmd("sm_chatfilter_reload", Command_Reload, ADMFLAG_ROOT, "sm_chatfilter_reload");
  ParseConfig();
}

public OnLibraryRemoved(const String:name[])
{
  if (strcmp(name, "scp") == 0)
    SetFailState("Simple Chat Processor unloaded, plugin disabled");
}

public OnClientDisconnect_Post(client)
{
  if (g_LastTrigger[client] != INVALID_HANDLE) {
    CloseHandle(g_LastTrigger[client]);
    g_LastTrigger[client] = INVALID_HANDLE;
  }
}

public Action:OnChatMessage(&author, Handle:recipients, String:name[], String:message[])
{
  new bool:suppress = false;
  decl String:error[256];
  new RegexError:iError;

  new tick = GetGameTickCount();

  for (new i=0; i<g_nFilters; i++) {
    new Handle:regex = GetArrayCell(g_Regexes, i);
    new found = MatchRegex(regex, message, iError);
    if (iError != REGEX_ERROR_NONE)
      LogError(error);
    else if (found > 0) {
      new mask = GetArrayCell(g_FilterMasks, i);

      if (mask & ACTION_SUPPRESS)
        suppress = RestrictToSelf(author, recipients);

      if (g_LastTrigger[author] == INVALID_HANDLE) {
        g_LastTrigger[author] = CreateArray(_, g_nFilters);
        for (new j=0; j<g_nFilters;j++)
          SetArrayCell(g_LastTrigger[author], j, 0);
      }

      /* Ensure that each regex only triggers once per message. */
      if (GetArrayCell(g_LastTrigger[author], i) != tick) {
        decl String:buf[MAXLENGTH_INPUT];
        GetArrayString(g_FilterStrings, i, buf, sizeof(buf));

        LogMessage("\"%L\" triggered filter \"%s\" with \"%s\"",
          author, buf, message);

        new Handle:data;
        if (mask & ACTION_HASDATA)
          data = GetArrayCell(g_FilterData, i);

        PunishPlayer(author, mask, data);

        SetArrayCell(g_LastTrigger[author], i, tick);
      }
    }
  }

  if (suppress)
    return Plugin_Stop;

  return Plugin_Continue;
}

public Action:Command_Reload(client, args)
{
  ParseConfig();
  LogAction(client, -1, "\"%L\" reloaded the chat filters", client);
  ReplyToCommand(client, "[SM] Parsed %d filters.", g_nFilters);

  return Plugin_Handled;
}

// Returns whether the message should be suppressed, and if the player
// is in the recipients list, the recipient list will be truncated to
// only include the sender.
bool:RestrictToSelf(client, Handle:recipients)
{
  new recipient;
  for (new i=0; i<GetArraySize(recipients); i++) {
    recipient = GetArrayCell(recipients, i);
    if (client == recipient) {
      ClearArray(recipients);
      PushArrayCell(recipients, client);
      return false;
    }
  }

  return true;
}

bool:PunishPlayer(client, mask, Handle:data)
{
  new bool:hasdata = false;
  new Float:fv;
  new iv;

  if (data != INVALID_HANDLE)
    hasdata = true;

  if (mask & ACTION_BLEED) {
    if (!hasdata || (fv = GetFloatValue(data, IND_BLEED)) == -1.0)
      fv = 5.0;

    TF2_MakeBleed(client, client, 5.0);
  }

  if (mask & ACTION_IGNITE)
    TF2_IgnitePlayer(client, client);

  if (mask & ACTION_STUN) {
    if (!hasdata || (fv = GetFloatValue(data, IND_BLEED)) == -1.0)
      fv = 5.0;

    TF2_StunPlayer(client, fv, 0.5, TF_STUNFLAG_THIRDPERSON|TF_STUNFLAG_NOSOUNDOREFFECT, 0);
  }

  if (mask & ACTION_SLAP) {
    if (hasdata && (iv = GetValue(data, IND_SLAP)) != -1)
      SlapPlayer(client, iv, _);
    else
      SlapPlayer(client, _, _);
  }

  if (mask & ACTION_MILK) {
    if (!hasdata || (fv = GetFloatValue(data, IND_MILK)) == -1.0)
      fv = 30.0;

    TF2_AddCondition(client, TFCond_Milked, fv);
  }

  if (mask & ACTION_JARATE) {
    if (!hasdata || (fv = GetFloatValue(data, IND_JARATE)) == -1.0)
      fv = 30.0;

    TF2_AddCondition(client, TFCond_Jarated, fv);
  }

  if (mask & ACTION_MARKFORDEATH) {
    if (!hasdata || (fv = GetFloatValue(data, IND_MARKFORDEATH)) == -1.0)
      fv = 30.0;

    TF2_AddCondition(client, TFCond_MarkedForDeath, fv);
  }

  if (mask & ACTION_MARKFORDEATHSILENT) {
    if (!hasdata || (fv = GetFloatValue(data, IND_MARKFORDEATHSILENT)) == -1.0)
      fv = 30.0;

    TF2_AddCondition(client, TFCond_MarkedForDeathSilent, fv);
  }

  if (mask & ACTION_SLAY)
    ForcePlayerSuicide(client);

  if (mask & ACTION_KICK)
    KickClient(client, "Client %d overflowed reliable channel", client);
}

Float:GetFloatValue(Handle:data, action)
{
  if (data == INVALID_HANDLE)
    return -1.0;

  return Float:GetArrayCell(data, action);
}

GetValue(Handle:data, action)
{
  if (data == INVALID_HANDLE)
    return -1;

  return RoundFloat(Float:GetArrayCell(data, action));
}

ParseConfig()
{
  decl String:buffer[256];
  new Handle:hKeyValues;

  if (g_FilterStrings != INVALID_HANDLE)
    CloseHandle(g_FilterStrings);

  if (g_Regexes != INVALID_HANDLE) {
    for (new i = 0; i < GetArraySize(g_Regexes); i++)
      CloseHandle(GetArrayCell(g_Regexes, i));

    CloseHandle(g_Regexes);
  }

  if (g_FilterMasks != INVALID_HANDLE)
    CloseHandle(g_FilterMasks);

  if (g_FilterData != INVALID_HANDLE) {
    for (new i=0; i<GetArraySize(g_FilterData); i++) {
      new Handle:data = GetArrayCell(g_FilterData, i);
      if (data != INVALID_HANDLE)
        CloseHandle(data);
    }

    CloseHandle(g_FilterData);
  }

  for (new i=0; i<g_nFilters; i++) {
    if (g_LastTrigger[i] != INVALID_HANDLE) {
      CloseHandle(g_LastTrigger[i]);
      g_LastTrigger[i] = INVALID_HANDLE;
    }
  }

  BuildPath(Path_SM, buffer, sizeof(buffer), CONFIG_PATH);
  hKeyValues = CreateKeyValues("Chat Filter");
  if (FileToKeyValues(hKeyValues, buffer) == false)
    SetFailState("Failed to read config file: %s", buffer);

  KvGetSectionName(hKeyValues, buffer, sizeof(buffer));
  if (strcmp(buffer, "chat_filter") != 0)
    SetFailState("%s structure corrupt or did not begin with \"chat_filter\"", CONFIG_PATH);

  g_FilterStrings = CreateArray(MAXLENGTH_INPUT);
  g_Regexes = CreateArray();
  g_FilterMasks = CreateArray();
  g_FilterData = CreateArray();

  if (KvGotoFirstSubKey(hKeyValues)) {
    do {
      /* Get the title. */
      KvGetSectionName(hKeyValues, buffer, sizeof(buffer));

      /* Get the regex. */
      decl String:regexstr[256];
      KvGetString(hKeyValues, "pattern", regexstr, sizeof(regexstr));

      if (regexstr[0] == '\0') {
        LogError("No pattern key found for \"%s\"", buffer);
        continue;
      }

      decl String:error[256];
      new RegexError:iError;
      new Handle:regex = CompileRegex(regexstr, PCRE_CASELESS, error, sizeof(error), iError);
      if (iError != REGEX_ERROR_NONE) {
        LogError(error);
        continue;
      }
      else
        PushArrayCell(g_Regexes, regex);

      PushArrayString(g_FilterStrings, buffer);
      ParsePunishments(buffer, hKeyValues);
      
    } while (KvGotoNextKey(hKeyValues));
    KvGoBack(hKeyValues);
  }

  CloseHandle(hKeyValues);
  g_nFilters = GetArraySize(g_FilterStrings);
}

ParsePunishments(const String:filtertext[], Handle:hKeyValues)
{
  new mask, attr;
  decl String:buffer[32], String:name[8];

  new Handle:data;

  mask = 0;
  attr = 0;

  for (;;) {
    /* Format attribute name. */
    Format(name, sizeof(name), "%i", attr + 1);
    
    /* Get attribute value. */
    KvGetString(hKeyValues, name, buffer, sizeof(buffer));

    /* Stop parsing if not found. */
    if (buffer[0] == '\0')
      break;

    new bool:found = false;
    for (new i=0; i<sizeof(g_Actions); i++) {
      decl String:type[32];
      new ind = SplitString(buffer, ":", type, sizeof(type));
      if (ind == -1)
        type = buffer;

      if (strcmp(type, g_Actions[i]) == 0) {
        mask |= (1 << i);
        found = true;

        /* Create data array if set. */
        if (ind != -1) {
          if (data == INVALID_HANDLE) {
            mask |= ACTION_HASDATA;

            data = CreateArray(_, sizeof(g_Actions));
            for (new j=0; j<sizeof(g_Actions); j++)
              SetArrayCell(data, j, -1.0);
          }

          SetArrayCell(data, i, Float:StringToFloat(buffer[ind]));
        }

        break;
      }
    }

    if (!found) {
      LogError("Action \"%s\" in filter \"%s\" did not match any known actions.",
        buffer, filtertext);
    }
    attr++;
  }

  PushArrayCell(g_FilterMasks, mask);
  PushArrayCell(g_FilterData, data);
}
