#include <sourcemod>

#pragma semicolon 1

new Handle:g_SearchResults;
new Handle:g_MapList;

#define SEARCHPATH  "../steamapps/workshop/content/440"

public Plugin:myinfo =
{
   name = "Workshop Map Search/Switch",
   author = "Forth",
   description = "Allows searching and switching to workshop maps without the suffix",
   version = "1.0"
}

public OnPluginStart()
{
   LoadTranslations("common.phrases");

   RegAdminCmd("sm_search", Command_MapSearch, ADMFLAG_CHANGEMAP, "sm_search <name>");
   RegAdminCmd("sm_wsearch", Command_MapSearch, ADMFLAG_CHANGEMAP, "sm_wsearch <name>");
   RegAdminCmd("sm_wmap", Command_WorkshopMap, ADMFLAG_CHANGEMAP, "sm_wmap <name>");
   g_SearchResults = CreateArray(80);
   g_MapList = CreateArray(80);
}

StripSuffix(String:out[], outlen, String:str[], String:suffix[])
{
   new pos = StrContains(str, suffix);
   if (pos == -1)
      strcopy(out, outlen, str);

   strcopy(out, pos+1, str);
}

Search(client, String:name[], String:path[])
{
   new Handle:dirh = INVALID_HANDLE;
   decl String:dirname[128], String:subpath[128];
   decl String:filename[128], String:buffer[128];
   decl String:tmp[128];
   new FileType:type = FileType_Unknown;
   new results;

   if (!DirExists(path)) {
      ReplyToCommand(client, "[SM] Directory %s does not exist", path);
      return 0;
   }

   dirh = OpenDirectory(path);
   while (ReadDirEntry(dirh, dirname, sizeof(dirname), type)) {
      if (type != FileType_Directory)
         continue;

      Format(subpath, sizeof(subpath), "%s/%s", SEARCHPATH, dirname);
      new Handle:subdirh = OpenDirectory(subpath);
      while (ReadDirEntry(subdirh, filename, sizeof(filename), type)) {
         if (type != FileType_File || !MapContainsStr(filename, name, ".bsp"))
            continue;

         /* Hack off trailing .bsp */
         StripSuffix(tmp, sizeof(tmp), filename, ".bsp");

         Format(buffer, sizeof(buffer), "%s.ugc%s", tmp, dirname);
         PushArrayString(g_SearchResults, buffer);
         results++;
      }
      if (subdirh != INVALID_HANDLE)
        CloseHandle(subdirh);
   }
   if (dirh != INVALID_HANDLE)
	    CloseHandle(dirh);

   SortADTArray(g_SearchResults, Sort_Ascending, Sort_String);
   return results;
}

SearchMapList(String:name[])
{
   decl String:buffer[128];
   new results, serial;

   results = 0;
   serial = -1;

   ReadMapList(g_MapList, serial, "maps on disk",
      MAPLIST_FLAG_NO_DEFAULT|MAPLIST_FLAG_MAPSFOLDER);

   for (new i=0; i<GetArraySize(g_MapList); i++) {
      GetArrayString(g_MapList, i, buffer, sizeof(buffer));
      if (!MapContainsStr(buffer, name, ""))
         continue;

      PushArrayString(g_SearchResults, buffer);
      results++;
   }

   ClearArray(g_MapList);
   return results;
}

bool:MapContainsStr(String:map[], String:str[], String:suffix[])
{
   decl String:tmp[128];
   new maplen, suffixlen;

   maplen = strlen(map);
   if (strlen(map) < 4)
      return false;

   suffixlen = strlen(suffix);
   if (suffixlen > 0) {
      if (strcmp(map[maplen - suffixlen], suffix) == 0) {
         /* Hack off suffix */
         map[maplen - suffixlen] = '\0';
      }
      else
         return false;
   }

   /* Hack off trailing .ugc\d+ */
   StripSuffix(tmp, sizeof(tmp), map, ".ugc");
   if (StrContains(tmp, str, false) == -1)
      return false;

   return true;
}

ChangeMap(client, String:name[])
{
   decl String:tmp[80];
   StripSuffix(tmp, sizeof(tmp), name, ".ugc");

   ShowActivity2(client, "[SM] ", "%t", "Changing map", tmp);
   LogAction(client, -1, "\"%L\" changed map to \"%s\"", client, name);

   new Handle:dp;
   CreateDataTimer(3.0, Timer_ChangeMap, dp);
   WritePackString(dp, name);
}

public Action:Command_MapSearch(client, args)
{
   decl String:cmd[16];
   GetCmdArg(0, cmd, sizeof(cmd));

   decl String:tmp[65], String:buffer[80];
   new results;

   if (args < 1) {
      ReplyToCommand(client, "[SM] Usage: %s <name>", cmd);
      return Plugin_Handled;
   }

   new String:arg[64];
   GetCmdArg(1, arg, sizeof(arg));

   if (strcmp(cmd, "sm_search") == 0)
      results = SearchMapList(arg);
   else
      results = Search(client, arg, SEARCHPATH);

   ReplyToCommand(client, "[SM] Search for \"%s\" returned %d result%s",
      arg, results, results != 1 ? "s" : "");

   for (new i=0; i<results; i++) {
      GetArrayString(g_SearchResults, i, buffer, sizeof(buffer));

      StripSuffix(tmp, sizeof(tmp), buffer, ".ugc");
      ReplyToCommand(client, "   %s", tmp);
   }

   ClearArray(g_SearchResults);
   return Plugin_Handled;
}

public Action:Command_WorkshopMap(client, args)
{
   decl String:tmp[96], String:buffer[80];
   new results;

   if (args < 1) {
      ReplyToCommand(client, "[SM] Usage: sm_wmap <name>");
      return Plugin_Handled;
   }

   new String:arg[64];
   GetCmdArg(1, arg, sizeof(arg));
   results = Search(client, arg, SEARCHPATH);

   if (results > 1 || results < 1) {
      /* Search for an exact match (to disambiguate between e.g.
       * plr_hightower and plr_hightower_event)
       */
      for (new i=0; i<results; i++) {
         GetArrayString(g_SearchResults, i, buffer, sizeof(buffer));
         StripSuffix(tmp, sizeof(tmp), buffer, ".ugc");
         if (strcmp(tmp, arg, false) == 0) {
            ChangeMap(client, buffer);
            return Plugin_Handled;
         }
      }

      if (results < 1)
         ReplyToCommand(client, "[SM] Search for \"%s\" matched no maps.", arg);
      else {
         ReplyToCommand(client,
            "[SM] Search for \"%s\" returned %d results, search string must be unique.",
            arg, results);
      }

      ClearArray(g_SearchResults);
      return Plugin_Handled;
   }

   GetArrayString(g_SearchResults, 0, buffer, sizeof(buffer));
   ClearArray(g_SearchResults);

   Format(tmp, sizeof(tmp), "workshop/%s", buffer);
   if (!IsMapValid(tmp)) {
      LogError("Map %s was found, but is not valid", tmp);
      return Plugin_Handled;
   }

   ChangeMap(client, tmp);
   return Plugin_Handled;
}

public Action:Timer_ChangeMap(Handle:timer, Handle:dp)
{
   decl String:map[80];

   ResetPack(dp);
   ReadPackString(dp, map, sizeof(map));

   ForceChangeLevel(map, "sm_wmap Command");

   return Plugin_Stop;
}
