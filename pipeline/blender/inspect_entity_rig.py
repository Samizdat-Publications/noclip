"""Inspect rigged GLB + merged animation GLB: bones, bbox/origin, clips. Run: blender -b -P this.py -- <rigged.glb> <merged.glb>"""
import bpy, sys
from mathutils import Vector
args = sys.argv[sys.argv.index("--") + 1:]
for path in args:
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=path)
    print("=====", path)
    for o in bpy.data.objects:
        print("OBJ", o.type, o.name, tuple(round(v, 3) for v in o.location), "parent", o.parent.name if o.parent else None)
        if o.type == "MESH":
            pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
            print("  bbox min", [round(min(p[i] for p in pts), 3) for i in range(3)], "max", [round(max(p[i] for p in pts), 3) for i in range(3)], "tris", sum(len(p.vertices) - 2 for p in o.data.polygons))
        if o.type == "ARMATURE":
            print("  bones", len(o.data.bones), [b.name for b in o.data.bones])
    for a in bpy.data.actions:
        print("ACTION", a.name, [round(v, 2) for v in a.frame_range], "fps", bpy.context.scene.render.fps)
