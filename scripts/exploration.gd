class_name Exploration
extends RefCounted
## What the walkers have seen of Herm (the player: a map with its paths, unknown ones dashed;
## the goals are its named places): each path in pieces of PIECE metres, walked once either walker
## comes within NEAR of it; each place found once one comes within FOUND_AT. Kept in
## user://explore.cfg.

signal found(find: Dictionary)

const SAVE := "user://explore.cfg"
const PIECE := 3.0      ## metres of path per piece
const NEAR := 3.0       ## a piece is walked when a walker passes this close
const FOUND_AT := 7.0   ## a place is found when a walker comes this close

var pieces := []                 ## [[a: Vector2, b: Vector2, path index]]
var walked := PackedByteArray()
var finds := []                  ## Landmarks' finds: [{"name", "kind", "pos", "has"}]
var found_names := {}            ## name -> true
var _grid := {}                  ## Vector2i (8 m) -> piece indices


func _init(the_finds: Array) -> void:
	finds = the_finds
	var paths: Array = Terrain.data().meta.paths
	for pi in paths.size():
		var pts: Array = Trails.resample(paths[pi].pts, PIECE)
		for i in pts.size() - 1:
			var a: Vector2 = pts[i]
			var b: Vector2 = pts[i + 1]
			var m := (a + b) * 0.5
			if not Terrain.reachable(m.x, m.y):
				continue   # the causeway and the pier, out in the sea
			var k := Vector2i(floori(m.x / 8.0), floori(m.y / 8.0))
			if not _grid.has(k):
				_grid[k] = []
			_grid[k].append(pieces.size())
			pieces.append([a, b, pi])
	walked.resize(pieces.size())
	load_state()


## The walkers are at `ps` (x, z): marks what they pass and what they find; true when anything new.
func visit(ps: Array) -> bool:
	var changed := false
	for p: Vector2 in ps:
		var c := Vector2i(floori(p.x / 8.0), floori(p.y / 8.0))
		for dj in [-1, 0, 1]:
			for di in [-1, 0, 1]:
				for i in _grid.get(c + Vector2i(di, dj), []):
					if walked[i] == 0 and Geometry2D.get_closest_point_to_segment(p, pieces[i][0], pieces[i][1]).distance_to(p) < NEAR:
						walked[i] = 1
						changed = true
		for f in finds:
			if not found_names.has(f.name) and (f.pos as Vector2).distance_to(p) < FOUND_AT:
				found_names[f.name] = true
				changed = true
				found.emit(f)
	return changed


func walked_share() -> float:
	var n := 0
	for w in walked:
		n += w
	return float(n) / maxf(walked.size(), 1.0)


func save_state() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("map", "walked", Marshalls.raw_to_base64(walked))
	cfg.set_value("map", "found", found_names.keys())
	cfg.save(SAVE)


func load_state() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE) != OK:
		return
	var w := Marshalls.base64_to_raw(String(cfg.get_value("map", "walked", "")))
	if w.size() == walked.size():
		walked = w   # the island changed since: start the map afresh
	for n in cfg.get_value("map", "found", []):
		found_names[n] = true


## Forgets everything (tests).
func reset() -> void:
	walked.fill(0)
	found_names.clear()
