## Gives the TOFU model (static, many parts) one skeleton and one skinned mesh.
## blender -b --python tools/blender/rig_tofu.py -- assets/tofu_stylized_3d_fox_character.glb assets/tofu_rigged.glb
## Blender axes: Z up, the character faces -Y, its left is +X (bones *.L).
import bpy, sys, mathutils
from mathutils import Vector

argv = sys.argv[sys.argv.index("--") + 1:]
src, dst = argv[0], argv[1]
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=src)

# 1. Drop the showcase backdrop (sphere, ground disc) and bake every part to world space.
for o in list(bpy.data.objects):
    if o.type == 'MESH' and (o.name.startswith("Sphere") or o.name.startswith("DOWNPLACE")):
        bpy.data.objects.remove(o)
meshes = [o for o in bpy.data.objects if o.type == 'MESH']
for o in meshes:
    mw = o.matrix_world.copy()
    o.data = o.data.copy()
    o.data.transform(mw)
    o.parent = None
    o.matrix_world = mathutils.Matrix.Identity(4)
for o in list(bpy.data.objects):
    if o.type != 'MESH':
        bpy.data.objects.remove(o)

# 2. Skeleton. Tail joints follow the tail mesh: centroids of slices along its length.
tail_obj = next(o for o in meshes if o.name.startswith("Tail"))
tv = sorted((v.co.copy() for v in tail_obj.data.vertices), key=lambda c: c.y)
def centroid(vs): return sum(vs, Vector()) / len(vs)
n = len(tv)
tail_pts = [centroid(tv[int(n * a):max(int(n * b), int(n * a) + 1)]) for a, b in ((0, .08), (.25, .4), (.55, .7), (.9, 1))]

B = {  # name: (head, tail, parent)
    "hips": ((0, 0, 1.95), (0, 0, 2.35), None),
    "spine": ((0, 0, 2.35), (0, 0, 2.8), "hips"),
    "chest": ((0, 0, 2.8), (0, 0, 3.2), "spine"),
    "neck": ((0, 0, 3.2), (0, -0.05, 3.4), "chest"),
    "head": ((0, -0.05, 3.4), (0, -0.05, 4.1), "neck"),
    "tail1": (tuple(tail_pts[0]), tuple(tail_pts[1]), "hips"),
    "tail2": (tuple(tail_pts[1]), tuple(tail_pts[2]), "tail1"),
    "tail3": (tuple(tail_pts[2]), tuple(tail_pts[3]), "tail2"),
}
for s, sx in (("L", 1), ("R", -1)):
    B.update({
        f"thigh.{s}": ((0.22 * sx, 0, 1.95), (0.33 * sx, 0, 1.1), "hips"),
        f"shin.{s}": ((0.33 * sx, 0, 1.1), (0.38 * sx, 0, 0.3), f"thigh.{s}"),
        f"foot.{s}": ((0.38 * sx, 0, 0.3), (0.40 * sx, -0.45, 0.08), f"shin.{s}"),
        f"upper_arm.{s}": ((0.52 * sx, 0, 3.12), (0.60 * sx, 0, 2.45), "chest"),
        f"forearm.{s}": ((0.60 * sx, 0, 2.45), (0.63 * sx, 0, 1.78), f"upper_arm.{s}"),
        f"hand.{s}": ((0.63 * sx, 0, 1.78), (0.64 * sx, -0.02, 1.38), f"forearm.{s}"),
        # The paw's four fingers bend together at the knuckle line, the thumb (the big bean at
        # the front) on its own (the player asked for fingers that let the paw lie on things).
        f"fingers.{s}": ((0.70 * sx, -0.03, 1.56), (0.72 * sx, -0.03, 1.40), f"hand.{s}"),
        f"thumb.{s}": ((0.64 * sx, -0.17, 1.63), (0.675 * sx, -0.24, 1.47), f"hand.{s}"),
    })
arm_data = bpy.data.armatures.new("TofuRig")
arm = bpy.data.objects.new("TofuRig", arm_data)
bpy.context.scene.collection.objects.link(arm)
bpy.context.view_layer.objects.active = arm
bpy.ops.object.mode_set(mode='EDIT')
for name, (h, t, p) in B.items():
    eb = arm_data.edit_bones.new(name)
    eb.head, eb.tail = Vector(h), Vector(t)
    eb.roll = 0.0
for name, (h, t, p) in B.items():
    if p:
        eb = arm_data.edit_bones[name]
        eb.parent = arm_data.edit_bones[p]
        eb.use_connect = (Vector(arm_data.edit_bones[p].tail) - Vector(h)).length < 1e-4
bpy.ops.object.mode_set(mode='OBJECT')
segs = {name: (Vector(h), Vector(t)) for name, (h, t, p) in B.items()}

# 3. Weights: each part may only use the bones that make sense for it.
def side(name, x):
    return name.replace(".S", ".L" if x >= 0 else ".R")

RULES = [  # (name prefix, candidate bones or one rigid bone)
    ("Retopo_Pants.R_high.001", ["hips", "spine", "chest", "neck", "upper_arm.S"]),  # shirt
    ("Retopo_Pants.R_high.002", ["hips", "thigh.S", "shin.S"]),                      # trousers
    ("Retopo_Pants.R_high_", ["chest", "neck", "head"]),                             # head and neck
    ("HandLeft", ["upper_arm.S", "forearm.S", "hand.S"]),
    ("FingersB", ["hand.S"]), ("Claws", ["hand.S"]),
    ("Plane_PIC", ["spine", "chest"]),
    ("Plane.003", ["hips", "spine", "chest"]), ("Plane.005", ["hips", "spine", "chest"]),  # bag strap
    ("Bag", ["hips"]),
    ("LegsCilinders", ["shin.S", "foot.S"]),
    ("Boots", ["foot.S"]), ("Cube.013", ["foot.S"]),
    ("Tail", ["tail1", "tail2", "tail3"]),
    ("Belt", ["hips"]), ("Cube.007", ["hips"]), ("Plane.002", ["hips"]), ("Plane.018", ["hips"]),
    ("Plane.019", ["hips"]), ("Plane.021", ["hips"]),
    ("EarHair", ["head"]), ("ErHair", ["head"]), ("Eyes", ["head"]), ("Nose", ["head"]),
    ("Plane.006", ["head"]), ("Plane.009", ["head"]), ("Plane.017", ["head"]),
]

def seg_dist(p, a, b):
    ab = b - a
    t = max(0.0, min(1.0, (p - a).dot(ab) / ab.length_squared))
    return (a + ab * t - p).length

for name in B:
    pass
for o in meshes:
    cands = next((c for pre, c in RULES if o.name.startswith(pre)), list(B.keys()))
    for bn in B:
        o.vertex_groups.new(name=bn)
    for v in o.data.vertices:
        p = v.co
        names = [side(c, p.x) for c in cands]
        if len(names) == 1:
            o.vertex_groups[names[0]].add([v.index], 1.0, 'REPLACE')
            continue
        ds = sorted((seg_dist(p, *segs[n]), n) for n in names)[:2]
        ws = [1.0 / (d + 0.03) ** 4 for d, _ in ds]
        tot = sum(ws)
        for (d, n), w in zip(ds, ws):
            o.vertex_groups[n].add([v.index], w / tot, 'REPLACE')
    print("weighted", o.name, "->", cands)

# 3b. The paw: beans and claws ride their finger; the mitten bends below the knuckles.
def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)

KNUCKLE_HI, KNUCKLE_LO = 1.62, 1.50   # the mitten turns from the hand to the fingers over these heights
for o in meshes:
    if not any(o.name.startswith(pre) for pre in ("FingersB", "Claws", "HandLeft")):
        continue
    import bmesh
    bm = bmesh.new(); bm.from_mesh(o.data); bm.verts.ensure_lookup_table()
    part = {}
    for v in bm.verts:   # connected parts: a bean, a claw half, the mitten
        if v.index in part: continue
        stack = [v]; ids = [v.index]; part[v.index] = v.index
        while stack:
            x = stack.pop()
            for e in x.link_edges:
                y = e.other_vert(x)
                if y.index not in part:
                    part[y.index] = v.index; ids.append(y.index); stack.append(y)
        cen = sum((o.data.vertices[i].co for i in ids), Vector()) / len(ids)
        for i in ids:
            part[i] = (cen, len(ids))
    bm.free()
    for v in o.data.vertices:
        p = v.co
        s_ = ".L" if p.x >= 0 else ".R"
        cen, size = part[v.index]
        thumbish = cen.y < -0.2
        if o.name.startswith("FingersB") or o.name.startswith("Claws"):
            if o.name.startswith("FingersB") and size > 200:
                continue   # the palm's big bean stays on the hand
            for g in o.vertex_groups:
                g.remove([v.index])
            o.vertex_groups[("thumb" if thumbish else "fingers") + s_].add([v.index], 1.0, 'REPLACE')
            continue
        if p.z > KNUCKLE_HI + 0.02 or size < 150:
            continue   # the sleeve and the arm: as weighted
        h = next((g.weight for g in v.groups if o.vertex_groups[g.group].name == "hand" + s_), 0.0)
        if h <= 0.0:
            continue
        f = smooth(KNUCKLE_HI, KNUCKLE_LO, p.z)
        t = smooth(-0.15, -0.21, p.y) * smooth(1.68, 1.58, p.z)
        wf = h * f * (1.0 - t)
        wt = h * t
        o.vertex_groups["hand" + s_].add([v.index], h - wf - wt, 'REPLACE')
        if wf > 0.0:
            o.vertex_groups["fingers" + s_].add([v.index], wf, 'REPLACE')
        if wt > 0.0:
            o.vertex_groups["thumb" + s_].add([v.index], wt, 'REPLACE')
    print("paw weighted", o.name)

# 3c. The face rides on the head as one piece (the player saw the brows wrongly bound): weighted
# by distance, the face skin blended neck and head over the snout's whole height, while the eyes,
# brows and nose are rigid on the head, so a nod or a turn slid them off the face. Now all the
# head mesh above the collar is on the head; it turns into the neck's weights under the collar.
HEAD_LO, HEAD_HI = 3.24, 3.34   # the collar sits at about 3.28
for o in meshes:
    if not o.name.startswith("Retopo_Pants.R_high_"):
        continue
    gi = {g.index: g.name for g in o.vertex_groups}
    for v in o.data.vertices:
        wh = smooth(HEAD_LO, HEAD_HI, v.co.z)
        rest = {gi[g.group]: g.weight for g in v.groups if gi[g.group] != "head" and g.weight > 0.0}
        tot = sum(rest.values())
        for g in list(v.groups):
            o.vertex_groups[gi[g.group]].remove([v.index])
        if tot <= 0.0:
            rest = {"neck": 1.0}
            tot = 1.0
        if wh < 1.0:
            for n_, w_ in rest.items():
                o.vertex_groups[n_].add([v.index], w_ / tot * (1.0 - wh), 'REPLACE')
        if wh > 0.0:
            o.vertex_groups["head"].add([v.index], wh, 'REPLACE')
    print("face on the head", o.name)

# 4. One mesh, skinned to the rig.
bpy.ops.object.select_all(action='DESELECT')
for o in meshes:
    o.select_set(True)
bpy.context.view_layer.objects.active = meshes[0]
bpy.ops.object.join()
body = bpy.context.view_layer.objects.active
body.name = "Tofu"
body.parent = arm
mod = body.modifiers.new("Armature", 'ARMATURE')
mod.object = arm
print("BODY verts", len(body.data.vertices), "materials", [m.name for m in body.data.materials])

bpy.ops.export_scene.gltf(filepath=dst, export_format='GLB', export_animations=False, export_apply=False)
print("EXPORTED", dst)
