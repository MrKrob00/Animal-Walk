class_name Wardrobe
extends RefCounted
## The bunny's clothes (the player asked for outfits and a dressing room): items, the slot each
## goes in (one item per slot), the ready sets, and the player's choice kept in user://.
## Items are nodes of scenes/bunny.tscn: her own top and shorts, and Agnes' blouse and sundress
## (tools/fit_outfit.gd fitted them to her; no shoes: the player). Top and bottom are never
## left empty.

const SAVE := "user://wardrobe.cfg"
const ITEMS := {
	"top": {"slot": "upper", "node": "Object_670", "name": "Топ"},
	"blouse": {"slot": "upper", "node": "Blouse", "name": "Блузка"},
	"shorts": {"slot": "lower", "node": "Object_672", "name": "Шорты"},
	"sundress": {"slot": "lower", "node": "Sundress", "name": "Сарафан"},
}
const SLOTS := {"upper": "Верх", "lower": "Низ"}
const MAY_BE_EMPTY := []
const SETS := {
	"Свой": {"upper": "top", "lower": "shorts"},
	"Agnes": {"upper": "blouse", "lower": "sundress"},
}
const DEFAULT := {"upper": "top", "lower": "shorts"}


static func load_choice() -> Dictionary:
	var cfg := ConfigFile.new()
	var out := DEFAULT.duplicate()
	if cfg.load(SAVE) == OK:
		for s in SLOTS:
			var v: String = cfg.get_value("outfit", s, out[s])
			if v == "" and not (s in MAY_BE_EMPTY):
				continue
			if v == "" or (ITEMS.has(v) and ITEMS[v].slot == s):
				out[s] = v
	return out


static func save_choice(choice: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for s in SLOTS:
		cfg.set_value("outfit", s, choice.get(s, ""))
	cfg.save(SAVE)


## The items in a slot (with "" first where it may be empty).
static func items_for(slot: String) -> Array:
	var out := [""] if slot in MAY_BE_EMPTY else []
	for k in ITEMS:
		if ITEMS[k].slot == slot:
			out.append(k)
	return out


## Shows the chosen items under `model` (the bunny's scene) and hides the rest.
static func apply(model: Node, choice: Dictionary) -> void:
	for k in ITEMS:
		var n := model.find_child(ITEMS[k].node, true, false)
		if n is Node3D:
			(n as Node3D).visible = choice.get(ITEMS[k].slot, "") == k
