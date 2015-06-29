#include <sourcemod>
#include <scp>
#include <regex>
#include <tf2_stocks>
#include <sdktools>

#define CONFIG_PATH "configs/chatfilter.txt"

/* Array of regex strings to match messages with. */
new Handle:g_FilterStrings;

/* Array of compiled regexes. */
new Handle:g_Regexes;

/* Array of punishment bitmasks for each regex. */
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
#define ACTION_MARKFORDEATHSILENT (1 << 9)

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
      new mask = GetArrayCell(g_FilterData, i);

      if (mask & ACTION_SUPPRESS)
        suppress = RestrictToSelf(author, recipients);

      if (g_LastTrigger[author] == INVALID_HANDLE) {
        g_LastTrigger[author] = CreateArray(_, g_nFilters);
        for (new j=0; j<g_nFilters;j++)
          SetArrayCell(g_LastTrigger[author], j, 0);
      }

      // Ensure that each regex only triggers once per message.
      if (GetArrayCell(g_LastTrigger[author], i) != tick) {
        decl String:buf[MAXLENGTH_INPUT];
        GetArrayString(g_FilterStrings, i, buf, sizeof(buf));

        LogMessage("\"%N\" triggered filter \"%s\" with \"%s\"",
          author, buf, message);

        PunishPlayer(author, mask);

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
  LogAction(client, -1, "\"%L\" reloaded the chat filters");
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

bool:PunishPlayer(client, mask)
{
  if (mask & ACTION_BLEED)
    TF2_MakeBleed(client, client, 5.0);

  if (mask & ACTION_IGNITE)
    TF2_IgnitePlayer(client, client);

  if (mask & ACTION_STUN)
    TF2_StunPlayer(client, 5.0, 0.1, TF_STUNFLAG_THIRDPERSON|TF_STUNFLAG_NOSOUNDOREFFECT, 0);

  if (mask & ACTION_SLAP)
    SlapPlayer(client, _, _);

  if (mask & ACTION_MILK)
    TF2_AddCondition(client, TFCond_Milked, 30.0);

  if (mask & ACTION_JARATE)
    TF2_AddCondition(client, TFCond_Jarated, 30.0);

  if (mask & ACTION_MARKFORDEATH)
    TF2_AddCondition(client, TFCond_PreventDeath, 30.0);

  if (mask & ACTION_MARKFORDEATHSILENT)
    TF2_AddCondition(client, TFCond_MarkedForDeathSilent, 30.0);

  if (mask & ACTION_SLAY)
    ForcePlayerSuicide(client);

  if (mask & ACTION_KICK)
    KickClient(client);
}

#if 0
public OnClientPutInServer(client)
{
}
#endif

ParseConfig()
{
  decl String:buffer[256];
  new Handle:hKeyValues;

  if (g_FilterStrings != INVALID_HANDLE)
    CloseHandle(g_FilterStrings);

  if (g_FilterData != INVALID_HANDLE)
    CloseHandle(g_FilterData);

  if (g_Regexes != INVALID_HANDLE) {
    for (new i = 0; i < GetArraySize(g_Regexes); i++)
      CloseHandle(GetArrayCell(g_Regexes, i));

    CloseHandle(g_Regexes);
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
  g_FilterData = CreateArray();

  if (KvGotoFirstSubKey(hKeyValues)) {
    do {
      /* Get the regex. */
      KvGetSectionName(hKeyValues, buffer, sizeof(buffer));

      decl String:error[256];
      new RegexError:iError;
      new Handle:regex = CompileRegex(buffer, PCRE_CASELESS, error, sizeof(error), iError);
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
      if (strcmp(buffer, g_Actions[i]) == 0) {
        mask |= (1 << i);
        found = true;
        break;
      }
    }

    if (!found) {
      LogError("Action \"%s\" in filter \"%s\" did not match any known actions.",
        buffer, filtertext);
    }
    attr++;
  }

  PushArrayCell(g_FilterData, mask);
}
