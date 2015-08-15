#if defined _mirrordamage_included
  #endinput
#endif
#define _mirrordamage_included

enum MirrorType {
   MirrorDealt = 0, /* Reflects dealt damage back to target */
   MirrorTaken,     /* Reflects taken damage back to target's attacker */
   MirrorLocked     /* Prevents dealt being changed via sm_mirrorme */
}

native bool:MirrorDamage_Status(client, MirrorType:mType=MirrorDealt);
native MirrorDamage_Enable(client, MirrorType:mType=MirrorDealt, bool:enable=true);

public SharedPlugin:__pl_mirrordamage =
{
  name = "Mirror Damage",
  file = "mirrordamage.smx",
#if defined REQUIRE_PLUGIN
  required = 1,
#else
  required = 0,
#endif
};

#if !defined REQUIRE_PLUGIN
public __pl_mirrordamage_SetNTVOptional()
{
  MarkNativeAsOptional("MirrorDamage_Status");
  MarkNativeAsOptional("MirrorDamage_Enable");
}
#endif
