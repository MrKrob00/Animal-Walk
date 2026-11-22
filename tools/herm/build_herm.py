"""Builds Herm (Channel Islands) for the game from open data, at 1:4 (the player chose Herm and
a scale that keeps it a phone game). Inputs:
  - OpenStreetMap (ODbL, (c) OpenStreetMap contributors): the coast, paths and tracks, walls,
    buildings, beaches, woods, meadows, named places.
      curl -o herm.osm "https://api.openstreetmap.org/api/0.6/map?bbox=-2.465,49.462,-2.435,49.484"
  - Copernicus DEM GLO-30 (heights; (c) DLR e.V. 2010-2014 and (c) Airbus Defence and Space GmbH
    2014-2018, provided under COPERNICUS by the European Union and ESA):
      curl -o dem.tif "https://copernicus-dem-30m.s3.amazonaws.com/Copernicus_DSM_COG_10_N49_00_W003_00_DEM/Copernicus_DSM_COG_10_N49_00_W003_00_DEM.tif"
Run: python3 tools/herm/build_herm.py herm.osm dem.tif assets/herm   (needs numpy, tifffile)
Then: godot --headless --path . --script tools/herm/make_herm.gd   (packs it into assets/herm/herm.res)
Game axes: x east, z south (north is -z), metres; y up. Water level 0.
"""
import sys, json, math, struct
import xml.etree.ElementTree as ET
import numpy as np
import tifffile

SCALE = 4.0          # real metres per game metre
CELL = 2.0           # game metres per grid cell
MARGIN = 40.0        # game metres of sea round the land
BEACH_SLOPE = 0.035  # as the old island: the beach rises this much per metre from the waterline
SHELF_SLOPE = 0.045
SIMPLIFY = 0.6       # game metres: lines kept this close to OSM

osm_path, dem_path, out_dir = sys.argv[1], sys.argv[2], sys.argv[3]
root = ET.parse(osm_path).getroot()
nodes, ntags = {}, {}
for n in root.iter('node'):
    nodes[n.get('id')] = (float(n.get('lat')), float(n.get('lon')))
    t = {x.get('k'): x.get('v') for x in n.findall('tag')}
    if t:
        ntags[n.get('id')] = t
ways = []
for w in root.iter('way'):
    t = {x.get('k'): x.get('v') for x in w.findall('tag')}
    refs = [nd.get('ref') for nd in w.findall('nd')]
    pts = [nodes[r] for r in refs if r in nodes]
    if len(pts) >= 2:
        ways.append((t, pts, refs))

# --- coast rings (land on the left of coastline ways) ---
coast = [list(zip(r, p)) for t, p, r in ways if t.get('natural') == 'coastline']
rings = []
segs = [c[:] for c in coast]
while segs:
    r = segs.pop(0)
    grown = True
    while grown and r[0][0] != r[-1][0]:
        grown = False
        for i, sg in enumerate(segs):
            if sg[0][0] == r[-1][0]:
                r += sg[1:]; segs.pop(i); grown = True; break
    if r[0][0] == r[-1][0] and len(r) > 3:
        rings.append([q for _, q in r])
lat0 = sum(q[0] for r in rings for q in r) / sum(len(r) for r in rings)
lon0 = sum(q[1] for r in rings for q in r) / sum(len(r) for r in rings)
KX = 111320.0 * math.cos(math.radians(lat0)) / SCALE
KY = 110540.0 / SCALE
def g(q):  # lat, lon -> game x, z
    return ((q[1] - lon0) * KX, -(q[0] - lat0) * KY)
grings = [np.array([g(q) for q in r]) for r in rings]
allp = np.vstack(grings)
x0 = math.floor((allp[:, 0].min() - MARGIN) / CELL) * CELL
z0 = math.floor((allp[:, 1].min() - MARGIN) / CELL) * CELL
nx = int(math.ceil((allp[:, 0].max() + MARGIN - x0) / CELL)) + 1
nz = int(math.ceil((allp[:, 1].max() + MARGIN - z0) / CELL)) + 1
gx, gz = np.meshgrid(x0 + np.arange(nx) * CELL, z0 + np.arange(nz) * CELL)
P = np.stack([gx.ravel(), gz.ravel()], 1)
print("grid", nx, "x", nz, "cells of", CELL, "m; land rings", len(grings), "lat0 lon0", lat0, lon0)

def inside(poly, pts):
    x, z = pts[:, 0], pts[:, 1]
    res = np.zeros(len(pts), bool)
    a = poly; b = np.roll(poly, -1, 0)
    for (ax, az), (bx, bz) in zip(a, b):
        c = ((az > z) != (bz > z)) & (x < (bx - ax) * (z - az) / (bz - az + 1e-12) + ax)
        res ^= c
    return res

def seg_dist(polys, pts, closed=True):
    d = np.full(len(pts), 1e9)
    for poly in polys:
        a = poly[:-1] if not closed else poly
        b = poly[1:] if not closed else np.roll(poly, -1, 0)
        for i in range(0, len(a), 64):
            A = a[i:i + 64][None]; B = b[i:i + 64][None]; Q = pts[:, None]
            AB = B - A
            t = np.clip(((Q - A) * AB).sum(-1) / np.maximum((AB * AB).sum(-1), 1e-12), 0, 1)
            D = np.linalg.norm(Q - (A + AB * t[..., None]), axis=-1).min(1)
            d = np.minimum(d, D)
    return d

land = np.zeros(len(P), bool)
for r in grings:
    land ^= inside(r, P)
dist = seg_dist(grings, P)
shore = np.where(land, dist, -dist).reshape(nz, nx)   # + inland, - out at sea (game metres)

# --- heights from the DEM (a surface model: smoothed, trees and roofs soften into the hills) ---
dem = tifffile.imread(dem_path).astype(np.float64)
H, W = dem.shape   # the tile covers lat 50..49 top to bottom, lon -3..-2
def dem_at(lat, lon):
    fy = (50.0 - lat) * H - 0.5; fx = (lon + 3.0) * W - 0.5
    iy = np.clip(np.floor(fy).astype(int), 0, H - 2); ix = np.clip(np.floor(fx).astype(int), 0, W - 2)
    ty = fy - iy; tx = fx - ix
    return (dem[iy, ix] * (1 - tx) * (1 - ty) + dem[iy, ix + 1] * tx * (1 - ty)
            + dem[iy + 1, ix] * (1 - tx) * ty + dem[iy + 1, ix + 1] * tx * ty)
lat = lat0 - P[:, 1] / KY; lon = lon0 + P[:, 0] / KX
base = np.maximum(dem_at(lat, lon), 0.0).reshape(nz, nx) / SCALE
k = np.array([1, 4, 6, 4, 1], float); k /= k.sum()   # a gentle blur: 30 m samples, no steps
for _ in range(2):
    base = np.apply_along_axis(lambda v: np.convolve(v, k, 'same'), 1, base)
    base = np.apply_along_axis(lambda v: np.convolve(v, k, 'same'), 0, base)
inl = np.maximum(shore, 0.0); out = np.maximum(-shore, 0.0)
def smoothstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1); return t * t * (3 - 2 * t)
height = np.where(shore >= 0,
                  BEACH_SLOPE * np.minimum(inl, 14.0) + np.maximum(base - 0.3, 0.0) * smoothstep(1.0, 10.0, inl),
                  -SHELF_SLOPE * out - 2.6 * smoothstep(3.0, 25.0, out))

# --- what the ground is: 0 sea, 1 grass, 2 sand (beach), 3 wood, 4 scrub, 5 village ---
kind = np.where(land, 1, 0).astype(np.uint8)
def area(pred, val):
    for t, p, r in ways:
        if pred(t) and len(p) > 3 and r[0] == r[-1]:
            poly = np.array([g(q) for q in p])
            lo = poly.min(0); hi = poly.max(0)
            m = (P[:, 0] >= lo[0]) & (P[:, 0] <= hi[0]) & (P[:, 1] >= lo[1]) & (P[:, 1] <= hi[1])
            idx = np.where(m)[0]
            if len(idx):
                kf = kind.reshape(-1)
                kf[idx[inside(poly, P[idx])]] = val
area(lambda t: t.get('landuse') == 'residential', 5)
area(lambda t: t.get('natural') in ('scrub', 'heath'), 4)
area(lambda t: t.get('natural') == 'wood' or t.get('landuse') == 'forest', 3)
area(lambda t: t.get('natural') in ('beach', 'sand'), 2)
kind = kind.reshape(nz, nx)
kind[(shore >= 0) & (shore < 3.0) & (kind == 1) & (height < 0.6)] = 2   # a strip of sand at the waterline
kind[shore < 0] = 0

# --- lines: paths, walls; buildings; places ---
def simplify(pts, tol):
    pts = np.asarray(pts)
    if len(pts) < 3: return pts
    a, b = pts[0], pts[-1]; ab = b - a; L = np.hypot(*ab)
    rel = pts - a
    d = np.abs(ab[0] * rel[:, 1] - ab[1] * rel[:, 0]) / L if L > 1e-9 else np.hypot(rel[:, 0], rel[:, 1])
    i = int(np.argmax(d))
    if d[i] > tol:
        return np.vstack([simplify(pts[:i + 1], tol)[:-1], simplify(pts[i:], tol)])
    return np.array([a, b])
def r2(a): return [[round(float(x), 2), round(float(z), 2)] for x, z in a]
paths, walls, buildings = [], [], []
for t, p, r in ways:
    gp = simplify([g(q) for q in p], SIMPLIFY)
    h = t.get('highway')
    if h in ('footway', 'path', 'steps', 'track', 'pedestrian', 'service', 'unclassified', 'residential', 'bridleway', 'cycleway'):
        paths.append({"kind": h, "surface": t.get('surface', ''), "name": t.get('name', ''), "pts": r2(gp)})
    elif t.get('barrier') in ('wall', 'fence', 'hedge', 'retaining_wall'):
        walls.append({"kind": t['barrier'], "pts": r2(gp)})
    elif 'building' in t and r[0] == r[-1]:
        buildings.append({"name": t.get('name', ''), "kind": t.get('building'), "levels": t.get('building:levels', ''), "pts": r2(gp[:-1])})
places = []
seen = set()
def add_place(name, kinds, xz):
    if not name or name in seen: return
    seen.add(name)
    places.append({"name": name, "kind": kinds, "x": round(float(xz[0]), 2), "z": round(float(xz[1]), 2)})
for nid, t in ntags.items():
    k_ = next((t[k] for k in ('natural', 'tourism', 'historic', 'place', 'man_made', 'leisure', 'amenity') if k in t), None)
    if k_ and 'name' in t:
        add_place(t['name'], k_, g(nodes[nid]))
for t, p, r in ways:
    k_ = next((t[k] for k in ('natural', 'tourism', 'historic', 'place', 'man_made', 'leisure', 'amenity', 'landuse') if k in t), None)
    if k_ and 'name' in t and 'highway' not in t:
        gp = np.array([g(q) for q in p]); add_place(t['name'], k_, gp.mean(0))
coast_out = [r2(simplify(np.vstack([r, r[:1]]), SIMPLIFY)) for r in grings]

meta = {"scale": SCALE, "cell": CELL, "x0": x0, "z0": z0, "nx": nx, "nz": nz, "lat0": lat0, "lon0": lon0,
        "coast": coast_out, "paths": paths, "walls": walls, "buildings": buildings, "places": places}
with open(f"{out_dir}/herm.json", "w") as f:
    json.dump(meta, f, ensure_ascii=False, separators=(",", ":"))
height.astype('<f4').tofile(f"{out_dir}/herm_height.bin")
shore.astype('<f4').tofile(f"{out_dir}/herm_shore.bin")
kind.astype(np.uint8).tofile(f"{out_dir}/herm_kind.bin")
land_area = (shore >= 0).sum() * CELL * CELL
print("land %.0f m^2 (game), max height %.1f m, paths %d (%.0f m), walls %d, buildings %d, places %d" % (
    land_area, height.max(), len(paths), sum(np.hypot(*np.diff(np.array(p['pts']), axis=0).T).sum() for p in paths),
    len(walls), len(buildings), len(places)))
