#if defined _notarget_included
  #endinput
#endif
#define _notarget_included

native bool:Notarget_GetClientNotarget(client);
native bool:Notarget_SetClientNotarget(client, bool:enable);

public SharedPlugin:__pl_notarget =
{
  name = "notarget",
  file = "notarget.smx",
#if defined REQUIRE_PLUGIN
  required = 1,
#else
  required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_notarget_SetNTVOptional()
{
  MarkNativeAsOptional("Notarget_GetClientNotarget");
  MarkNativeAsOptional("Notarget_SetClientNotarget");
}
#endif
