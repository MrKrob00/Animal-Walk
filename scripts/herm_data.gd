class_name HermData
extends Resource
## Herm (Channel Islands) for the game at 1:4, from open data (tools/herm/build_herm.py packs it,
## tools/herm/make_herm.gd saves it): OpenStreetMap ((c) OpenStreetMap contributors, ODbL) for the
## coast, paths, walls, buildings, beaches, woods and named places; Copernicus DEM GLO-30 for the
## heights. Grids are nx by nz cells of `cell` metres from (x0, z0); x east, z south.

@export var meta := {}                         ## scale, cell, x0, z0, nx, nz, coast, paths, walls, buildings, places
@export var height := PackedFloat32Array()     ## ground height, metres (water level 0)
@export var shore := PackedFloat32Array()      ## signed distance to the coast: + inland, - out at sea
@export var kind := PackedByteArray()          ## 0 sea, 1 grass, 2 sand, 3 wood, 4 scrub, 5 village
