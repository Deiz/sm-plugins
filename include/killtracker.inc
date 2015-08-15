#if defined _killtracker_included
  #endinput
#endif
#define _killtracker_included

native KillTracker_UniqueVictims(client);
native KillTracker_FirstKill(client);

forward void OnUniqueVictimAdded(client, nvictims);

public SharedPlugin:__pl_killtracker =
{
  name = "killtracker",
  file = "killtracker.smx",
#if defined REQUIRE_PLUGIN
  required = 1,
#else
  required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_killtracker_SetNTVOptional()
{
  MarkNativeAsOptional("KillTracker_UniqueVictims");
  MarkNativeAsOptional("KillTracker_FirstKill");
}
#endif
