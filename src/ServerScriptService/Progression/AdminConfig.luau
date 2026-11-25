--!strict
-- Server-only owner identity and admin limits. See TASK-007-Admin-Panel.
return {
	OWNER_ID = 972305119,
	ACCESS_STORE = "TRASH_AdminAccess_v1",
	ACCESS_TOPIC = "TRASH_AdminAccess_v1",
	ACCESS_TTL = 30,
	REQUEST_GAP = 0.25,
	MAX_AMOUNT = 1000000,
	DEFAULT_ITEMS = 100,
	MAX_COORDINATE = 100000,
	TELEPORT_HEIGHT = 5,
	GROUND_TOP = 1600,
	MAX_TEXT = 64,
}
