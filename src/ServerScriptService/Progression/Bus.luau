--!strict
--[[
	Bus - a tiny in-server event bus so systems can report what players do without requiring each
	other. Salvage, stations, combat credit and the rest emit; QuestService and stats listen.

	Events (payload fields):
	  Salvage   { method, region, contest }       a junk pile was processed
	  Recycle   { item, count }                   items sorted at a Recycling Station
	  Sell      { item, count }                   items sold at a Fence
	  Craft     { recipe, count }                 a Workbench recipe
	  Process   { recipe }                        Purify or Smelt
	  Consume   { item, food, water }             an item was used
	  Defeat    { kind, victim }                  Smogling | JunkRam | Rival | Player
	  Visit     { region }                        entered a region
	  Talk      { npc }                           spoke to an NPC
	  Upgrade   { tier }                          Blacksmith upgrade
	  Faction   { faction }                       joined a faction
	  Roll      { id, rarity }                    rolled a Relic
	  Contest   { site, faction }                 salvaged during an open Sky Dump
	  Buy       { item, count }                   bought at a store
	  Level     { level }                         levelled up
]]

local Bus = {}

local listeners: { [string]: { (Player, any) -> () } } = {}

function Bus.on(kind: string, fn: (Player, any) -> ())
	listeners[kind] = listeners[kind] or {}
	table.insert(listeners[kind], fn)
end

function Bus.emit(player: Player, kind: string, payload: any?)
	for _, fn in listeners[kind] or {} do
		task.spawn(fn, player, payload or {})
	end
end

return Bus
