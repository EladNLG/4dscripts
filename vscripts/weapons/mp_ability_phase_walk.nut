global function MpAbilityPhaseWalk_Init

global function OnWeaponActivate_ability_phase_walk
global function OnWeaponDeactivate_ability_phase_walk
global function OnWeaponPrimaryAttack_ability_phase_walk
global function OnWeaponChargeBegin_ability_phase_walk
global function OnWeaponChargeEnd_ability_phase_walk
#if SERVER
global function MoveToPlayerRealm
global function CycleRealms
#endif
const float PHASE_WALK_PRE_TELL_TIME = 1.5
const asset PHASE_WALK_APPEAR_PRE_FX = $"P_phase_dash_pre_end_mdl"

const array<int> realmCycle = [0, 1]

struct
{
	table<entity, int> playerRealmIndexes
} file
#if SERVER
// just an alias for AddToUltimateRealm, just... makes more sense called like this.
void function MoveToPlayerRealm(entity ent, entity player) 
{
	AddToUltimateRealm(player, ent)
}
#endif

void function MpAbilityPhaseWalk_Init()
{
	#if SERVER
	AddCallback_OnClientConnected( OnPlayerConnected )
	#endif
	PrecacheParticleSystem( PHASE_WALK_APPEAR_PRE_FX )
}

#if SERVER
void function OnPlayerConnected( entity player )
{
	player.RemoveFromAllRealms()
	player.AddToRealm(1)
}
#endif

void function OnWeaponActivate_ability_phase_walk( entity weapon )
{
	#if SERVER
		entity player = weapon.GetWeaponOwner()
		EmitSoundOnEntityExceptToPlayer( player, player, "pilot_phaseshift_armraise_3p" )

		if ( player.GetActiveWeapon( eActiveInventorySlot.mainHand ) != player.GetOffhandWeapon( OFFHAND_INVENTORY ) )
			PlayBattleChatterLineToSpeakerAndTeam( player, "bc_tactical" )
	#endif
}

void function OnWeaponDeactivate_ability_phase_walk( entity weapon )
{
	#if SERVER
	#endif
}

var function OnWeaponPrimaryAttack_ability_phase_walk( entity weapon, WeaponPrimaryAttackParams attackParams )
{
	entity player = weapon.GetWeaponOwner()
	return weapon.GetWeaponSettingInt( eWeaponVar.ammo_per_shot )
}

bool function OnWeaponChargeBegin_ability_phase_walk( entity weapon )
{
	entity player = weapon.GetWeaponOwner()
	float chargeTime = weapon.GetWeaponSettingFloat( eWeaponVar.charge_time )
	#if SERVER
		LockWeaponsAndMelee( player )

		if ( weapon.HasMod( "ult_active" ) )
		{
			weapon.w.statusEffects.append( StatusEffect_AddTimed( player, eStatusEffect.speed_boost, 0.35, chargeTime, 0 ) )
		}
		if ( weapon.HasMod( "phase_travel" ) )
		{
			CycleRealms(player)
		}

		thread PhaseWalkUnphaseTell( player, chargeTime )
		PlayerUsedOffhand( player, weapon )
	StatsHook_Tactical_TimeSpentInPhase( player, chargeTime )
	#endif
	PhaseShift( player, 0, chargeTime, eShiftStyle.Balance )
	return true
}


#if SERVER
void function CycleRealms(entity player)
{
	if (!(player in file.playerRealmIndexes)) {
		player.RemoveFromAllRealms()
		player.AddToRealm(realmCycle[0])
		file.playerRealmIndexes[player] <- 0
	}
	else
	{
		int nextRealmIndex = file.playerRealmIndexes[player] + 1
		if (nextRealmIndex >= realmCycle.len()) nextRealmIndex = 0
		player.RemoveFromAllRealms()
		player.AddToRealm(realmCycle[nextRealmIndex])
		file.playerRealmIndexes[player] = nextRealmIndex
	}
}

void function PhaseWalkUnphaseTell( entity player, float chargeTime )
{
	player.EndSignal( "OnDeath" )
	player.EndSignal( "ForceStopPhaseShift" )

	TrackingVision_CreatePOI( eTrackingVisionNetworkedPOITypes.PLAYER_ABILITIES_PHASE_DASH_START, player, player.GetOrigin(), player.GetTeam(), player )

	wait PHASE_WALK_PRE_TELL_TIME

	asset fxAsset = PHASE_WALK_APPEAR_PRE_FX
	int fxid     = GetParticleSystemIndex( fxAsset )
	int attachId = player.LookupAttachment( "ORIGIN" )

	entity dashFX = StartParticleEffectOnEntity_ReturnEntity( player, fxid, FX_PATTACH_POINT_FOLLOW, attachId )
	dashFX.kv.VisibilityFlags = (ENTITY_VISIBLE_TO_FRIENDLY | ENTITY_VISIBLE_TO_ENEMY)	// everyone but owner
	dashFX.SetOwner( player )

	OnThreadEnd(
	function() : ( player, dashFX )
		{
			if ( IsValid( player ) )
				TrackingVision_CreatePOI( eTrackingVisionNetworkedPOITypes.PLAYER_ABILITIES_PHASE_DASH_STOP, player, player.GetOrigin(), player.GetTeam(), player )
			EffectStop( dashFX )
		}
	)
	wait chargeTime - PHASE_WALK_PRE_TELL_TIME
}
#endif

void function OnWeaponChargeEnd_ability_phase_walk( entity weapon )
{
	entity player = weapon.GetWeaponOwner()
	#if SERVER
		UnlockWeaponsAndMelee( player )
		EnableMantle(player)
		foreach ( effect in weapon.w.statusEffects )
		{
			StatusEffect_Stop( player, effect )
		}
		if ( player.IsMantling() || player.IsWallRunning() || player.p.isSkydiving )
			weapon.SetWeaponPrimaryClipCount( 0 ) //Defensive fix for the fact that primary fire isn't triggered when climbing.
	#endif
}