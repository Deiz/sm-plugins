
#if defined _admin_print_included
 #endinput
#endif
#define _admin_print_included

new Handle:_hCvarShowActivity = INVALID_HANDLE;
new _ShowActivityOriginal;

stock PrintToChatAdmins(AdminFlag:flag=Admin_Generic, const String:format[], any:...)
{
   decl String:buffer[192];

   new AdminId:adminId;
   for (new i = 1; i <= MaxClients; i++) {
      if (IsClientInGame(i)) {
         adminId = GetUserAdmin(i);
         if (adminId != INVALID_ADMIN_ID && GetAdminFlag(adminId, flag)) {
            SetGlobalTransTarget(i);
            VFormat(buffer, sizeof(buffer), format, 3);
            PrintToChat(i, "%s", buffer);
         }
      }
   }
}

stock DisablePlayerNotifications()
{
   if (_hCvarShowActivity == INVALID_HANDLE)
      _hCvarShowActivity = FindConVar("sm_show_activity");

   _ShowActivityOriginal = GetConVarInt(_hCvarShowActivity);
   if (_ShowActivityOriginal & 1)
      SetConVarInt(_hCvarShowActivity, _ShowActivityOriginal & ~1);

}

stock EnablePlayerNotifications()
{
   if (_hCvarShowActivity == INVALID_HANDLE)
      _hCvarShowActivity = FindConVar("sm_show_activity");

   if (_ShowActivityOriginal & 1)
      SetConVarInt(_hCvarShowActivity, _ShowActivityOriginal);
}
