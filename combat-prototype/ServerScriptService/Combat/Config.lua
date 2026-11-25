-- Provisional medium-sword values from the combat design vault.
local Config = {
	Health = 100, MaxPosture = 100, GuardAngle = 120,
	ParryWindow = 0.16, ParryCooldown = 0.75, ParryRecovery = 0.12,
	ParriedOffense = 0.30, ParriedDefense = 0.12,
	ParryRelief = 25, ParryPressure = 10,
	PostureDelay = 1.25, PostureRate = 20,
	GuardBreak = 0.70, ResetPosture = 35, BreakImmunity = 1.25,
	ResetProtection = 0.35, ControlCap = 1.00, ActionableReset = 0.20,
	GuardReaction = 0.08, GuardRelease = 0.08,
	FeintFraction = 0.60, FeintCooldown = 0.70,
	FeintOffense = 0.18, FeintDefense = 0.10,
	DodgeDuration = 0.45, DodgeInvulnerability = 0.16, DodgeCooldown = 1.00,
	DodgeCancelWindow = 0.15, DodgeCancelDefense = 0.25,
	DodgeSpeed = 38, DodgeTravelTime = 0.20,
	ChaseWindow = 0.35, ChaseAttackDelay = 0.30,
	ChaseHorizontal = 10, ChaseVertical = 12, ChaseTravelTime = 0.20,
	LaunchHeight = 12, AirHeightCap = 18, AirDuration = 2.00,
	AirGravityScale = 0.40,
	AirHits = 2, AirFinalReaction = 0.15, RelaunchGroundTime = 0.20,
	Reach = 6, HitboxWidth = 1.5, HitboxHeight = 4, SweepAngle = 120,
	SequenceTimeout = 1.00, FlourishSpeed = 16,
	RequestRate = 30, RequestBurst = 20, MaxStep = 0.15,
	Attacks = {
		M1 = {Startup=0.24, Active=0.08, Recovery=0.28, Damage=10, Posture=18, Reaction=0.18},
		AirM1 = {Startup=0.22, Active=0.08, Recovery=0.30, Damage=10, Posture=18, Reaction=0.16},
		SprintAttack = {Startup=0.30, Active=0.08, Recovery=0.37, Damage=10, Posture=20, Reaction=0.18, Cooldown=1.20},
		Critical = {Startup=0.48, Active=0.10, Recovery=0.42, Damage=18, Posture=38, Reaction=0.24, Cooldown=3.00},
		Uppercut = {Startup=0.42, Active=0.08, Recovery=0.50, Damage=12, Posture=24, Reaction=0.24, Cooldown=6.00},
		Downslam = {Startup=0.30, Active=0.08, Recovery=0.42, Damage=12, Posture=24, Reaction=0.15},
	},
}
for _, attack in Config.Attacks do table.freeze(attack) end
table.freeze(Config.Attacks)
return table.freeze(Config)
