#include <sourcemod>
#include <sdktools>
#include "dbi.inc"

public Plugin:myinfo =
{
	name = "Player-Teleport by Dr. HyperKiLLeR",
	author = "Dr. HyperKiLLeR",
	description = "Go to a player or teleport a player to you",
	version = "1.2.0.0",
	url = ""
};

//Plugin-Start
public OnPluginStart()
{
	LoadTranslations("common.phrases");
	RegAdminCmd("sm_goto", Command_Goto, ADMFLAG_SLAY,"Go to a player");
	RegAdminCmd("sm_bring", Command_Bring, ADMFLAG_SLAY,"Teleport a player to you");

	CreateConVar("goto_version", "1.2", "Dr. HyperKiLLeRs Player Teleport",FCVAR_PLUGIN|FCVAR_SPONLY|FCVAR_UNLOGGED|FCVAR_DONTRECORD|FCVAR_REPLICATED|FCVAR_NOTIFY);

}

public Action:Command_Goto(Client,args)
{
    //Error:
	if(args < 1)
	{

		//Print:
		PrintToConsole(Client, "Usage: sm_goto <name>");
		PrintToChat(Client, "Usage:\x04 sm_goto <name>");

		//Return:
		return Plugin_Handled;
	}

	//Declare:
	decl String:arg[32];
	new Float:TeleportOrigin[3];
	new Float:PlayerOrigin[3];
	decl String:Name[32];

	new target = FindTarget(Client, arg, true, false);
	if (target == -1)
	{
		return Plugin_Handled;
	}

	//Initialize
	GetClientName(target, Name, sizeof(Name));
	GetClientAbsOrigin(target, PlayerOrigin);

	//Math
	TeleportOrigin[0] = PlayerOrigin[0];
	TeleportOrigin[1] = PlayerOrigin[1];
	TeleportOrigin[2] = (PlayerOrigin[2] + 73);

	LogAction(Client, target, "\"%L\" teleported to \"%L\"", Client, target);

	//Teleport
	TeleportEntity(Client, TeleportOrigin, NULL_VECTOR, NULL_VECTOR);

	return Plugin_Handled;
}

public Action:Command_Bring(client,args)
{
    //Error:
	if(args < 1)
	{

		//Print:
		PrintToConsole(client, "Usage: sm_bring <name>");
		PrintToChat(client, "Usage:\x04 sm_bring <name>");

		//Return:
		return Plugin_Handled;
	}

	//Declare:
	decl String:PlayerName[32];

	//Initialize:
	GetCmdArg(1, PlayerName, sizeof(PlayerName));

	decl String:target_name[MAX_TARGET_LENGTH];
	decl target_list[MAXPLAYERS], target_count, bool:tn_is_ml;

	if ((target_count = ProcessTargetString(
		PlayerName,
		client,
		target_list,
		MAXPLAYERS,
		COMMAND_FILTER_ALIVE,
		target_name,
		sizeof(target_name),
		tn_is_ml)) <= 0)
	{
		ReplyToTargetError(client, target_count);
		return Plugin_Handled;
	}

	new Float:TeleportOrigin[3];
	new Float:PlayerOrigin[3];


	//Initialize
	GetCollisionPoint(client, PlayerOrigin);

	//Math
	TeleportOrigin[0] = PlayerOrigin[0];
	TeleportOrigin[1] = PlayerOrigin[1];
	TeleportOrigin[2] = (PlayerOrigin[2] + 4);

	for (new i = 0; i < target_count; i++)
	{
		LogAction(client, target_list[i], "\"%L\" brought \"%L\"",
			client, target_list[i]);
		TeleportEntity(target_list[i], TeleportOrigin, NULL_VECTOR, NULL_VECTOR);
	}

	return Plugin_Handled;
}

// Trace

stock GetCollisionPoint(client, Float:pos[3])
{
	decl Float:vOrigin[3], Float:vAngles[3];

	GetClientEyePosition(client, vOrigin);
	GetClientEyeAngles(client, vAngles);

	new Handle:trace = TR_TraceRayFilterEx(vOrigin, vAngles, MASK_SOLID, RayType_Infinite, TraceEntityFilterPlayer);

	if(TR_DidHit(trace))
	{
		TR_GetEndPosition(pos, trace);
		CloseHandle(trace);

		return;
	}

	CloseHandle(trace);
}

public bool:TraceEntityFilterPlayer(entity, contentsMask)
{
	return entity > MaxClients;
}

