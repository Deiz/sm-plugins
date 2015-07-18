#pragma semicolon 1

#include <sourcemod>

public Plugin:myinfo = 
{
   name = "MvM Player Limit",
   author = "Forth",
   description = "Prevents players from joining when an MvM server is full",
   version = "1.0",
};

/* Handles to convars used by plugin */
new Handle:sm_playerlimit;

new g_PlayerLimit;
new bool:g_Enabled;

public OnPluginStart()
{
   LoadTranslations("reservedslots.phrases");
   
   sm_playerlimit = CreateConVar("sm_playerlimit", "6",
      "Maximum number of human players", 0, true, 0.0);

   HookConVarChange(sm_playerlimit, OnPlayerLimitChanged);

   g_PlayerLimit = GetConVarInt(sm_playerlimit);
}

public OnMapStart()
{
   decl String:mapname[128];
   GetCurrentMap(mapname, sizeof(mapname));

   if (strncmp(mapname, "mvm_",  4, false) == 0)
      g_Enabled = true;
   else
      g_Enabled = false;
}

public OnPlayerLimitChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
   g_PlayerLimit = GetConVarInt(sm_playerlimit);
}

public OnClientPostAdminCheck(client)
{
   if (!g_Enabled)
      return;

   if (g_PlayerLimit > 0) {
      new clients = GetHumanPlayers();
      new flags = GetUserFlagBits(client);

      if (clients <= g_PlayerLimit || IsFakeClient(client) ||
            flags & ADMFLAG_ROOT || flags & ADMFLAG_RESERVATION)
         return;
      
      /* Kick player because there are no public slots left */
      CreateTimer(0.1, OnTimedKick, client);
   }
}

public Action:OnTimedKick(Handle:timer, any:client)
{   
   if (!client || !IsClientInGame(client))
      return Plugin_Handled;
   
   LogMessage("Kicking \"%L\", server has %d players", client, GetHumanPlayers());
   KickClient(client, "%T", "Slot reserved", client);
   
   return Plugin_Handled;
}

GetHumanPlayers()
{
   new players = 0;
   for (new i=1; i<MaxClients; i++)
   if (IsClientInGame(i) && !IsFakeClient(i))
      players++;

   return players;
}
