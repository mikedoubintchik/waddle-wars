#!/usr/bin/env python3
"""Fresh unrigged rear-shape study; run inside Blender 5.2.0, no renders.

blender --background --factory-startup --python tools/art/build_penguin_rear_blockout.py
Editable parameters: art_src/characters/penguin_rear_blockout_v1/config.json.
The old penguin mesh, skeleton, animation and source generators are not inputs.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import struct
import sys

import bmesh
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
DESTINATION = ROOT / "art_src/characters/penguin_rear_blockout_v1"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def smooth(a, b, x):
    t = max(0.0, min(1.0, (x - a) / (b - a)))
    return t * t * (3.0 - 2.0 * t)


def curve(rows, x):
    """Shape-preserving cubic interpolation, without overshoot at profile extrema."""
    count = len(rows)
    x = min(max(x, rows[0][0]), rows[-1][0])
    i = next((j for j in range(count - 1) if x <= rows[j + 1][0]), count - 2)
    h = rows[i + 1][0] - rows[i][0]
    t = (x - rows[i][0]) / h
    result = []
    for k in range(1, len(rows[0])):
        slopes = [(rows[j + 1][k] - rows[j][k]) / (rows[j + 1][0] - rows[j][0]) for j in range(count - 1)]
        def tangent(j):
            if j == 0:
                return slopes[0]
            if j == count - 1:
                return slopes[-1]
            a, b = slopes[j - 1], slopes[j]
            return 0.0 if a * b <= 0.0 else 2.0 * a * b / (a + b)
        value = ((2*t**3 - 3*t*t + 1) * rows[i][k] + (t**3 - 2*t*t + t) * h * tangent(i)
                 + (-2*t**3 + 3*t*t) * rows[i + 1][k] + (t**3 - t*t) * h * tangent(i + 1))
        result.append(value)
    return tuple(result)


class Geometry:
    def __init__(self):
        self.vertices, self.faces, self.colors, self.parts = [], [], [], {}

    def vertex(self, p, color):
        self.vertices.append(tuple(p))
        self.colors.append((*color, 1.0))
        return len(self.vertices) - 1

    def ring(self, points, colors):
        return [self.vertex(p, color) for p, color in zip(points, colors)]

    def bridge(self, a, b):
        for i in range(len(a)):
            n = (i + 1) % len(a)
            self.faces.append((a[i], a[n], b[n], b[i]))

    def cap(self, ring, p, color):
        center = self.vertex(p, color)
        for i in range(len(ring)):
            self.faces.append((center, ring[i], ring[(i + 1) % len(ring)]))


def linear_color(value):
    rgb = [int(value.lstrip("#")[i:i+2], 16) / 255.0 for i in (0, 2, 4)]
    return tuple(x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in rgb)


def add_body(g, config, palette):
    profile = config["body_profile_z_rx_ry_center_y"]
    wrap = config["rear_color_wrap"]
    bottom, top = profile[0][0], profile[-1][0]
    rings, segments = config["body_rings"], config["body_segments"]
    previous = None
    for row in range(1, rings):
        # Cosine spacing rounds both caps with small, deliberate quad loops.
        z = bottom + (top - bottom) * (0.5 - 0.5 * math.cos(math.pi * row / rings))
        rx, ry, cy = curve(profile, z)
        points, colors = [], []
        for i in range(segments):
            theta = math.tau * i / segments
            c, s = math.cos(theta), math.sin(theta)
            points.append((rx*c, cy + ry*s, z))
            color = mix(palette["rump"], palette["back"], smooth(0.22, 0.7, z))
            color = mix(color, palette["crown"], smooth(1.05, 1.45, z))
            # Front ivory wraps just around the lower side; rear stays charcoal.
            threshold = (wrap["ivory_lower_sin_cutoff"] +
                         (wrap["ivory_mid_sin_cutoff"]-wrap["ivory_lower_sin_cutoff"])*smooth(0.22,0.78,z) +
                         wrap["ivory_upper_sin_shift"]*smooth(0.88,1.32,z))
            belly = smooth(threshold - 0.065, threshold + 0.065, s)
            belly *= 1.0 - smooth(1.5, 1.65, z)
            color = mix(color, palette["ivory"], belly)
            angle = wrap["gold_rear_angle_radians"]
            side_angle = min(abs(math.atan2(math.sin(theta + angle), math.cos(theta + angle))),
                             abs(math.atan2(math.sin(theta - math.pi - angle), math.cos(theta - math.pi - angle))))
            patch_height = (z-wrap["gold_center_z"])/wrap["gold_height_radius"]
            patch_width = wrap["gold_angular_radius"]*(1.0-0.18*max(-1.0,min(1.0,patch_height)))
            patch = (side_angle / patch_width) ** 2 + patch_height ** 2
            color = mix(color, palette["neck_gold"], 1.0 - smooth(0.78, 1.13, patch))
            colors.append(color)
        current = g.ring(points, colors)
        if previous is None:
            g.cap(current, (0.0, profile[0][3], bottom), palette["rump"])
        else:
            g.bridge(previous, current)
        previous = current
    g.cap(previous, (0.0, profile[-1][3], top), palette["crown"])


def add_flipper(g, config, palette, side):
    rows = config["flipper_profile_t_x_y_z_half_width_half_thickness"]
    previous = None
    rings = config.get("flipper_rings", 20)
    # Extra end rings resolve the rounded paddle tip, without changing the span.
    samples = sorted(set([row / float(rings) for row in range(rings)] + [0.97, 0.989]))
    for t in samples:
        x, y, z, width, thickness = curve(rows, t)
        before, after = curve(rows, max(0.0, t - 0.015)), curve(rows, min(1.0, t + 0.015))
        dx, dz = after[0] - before[0], after[2] - before[2]
        length = math.hypot(dx, dz)
        nx, nz = -dz / length, dx / length
        points = [(side*(x + nx*width*math.cos(a)), y + thickness*math.sin(a),
                   z + nz*width*math.cos(a)) for a in [math.tau*i/12 for i in range(12)]]
        color = mix(palette["flipper"], palette["crown"], 0.35*t)
        ring = g.ring(points, [color]*12)
        if previous is None:
            g.cap(ring, (side*x, y, z), color)
        else:
            g.bridge(previous, ring)
        previous = ring
    tip = rows[-1]
    g.cap(previous, (side*tip[1], tip[2], tip[3]), palette["crown"])


def closed_outline(points, t):
    u = (t % 1.0) * len(points)
    i, f = int(u), u % 1.0
    p0, p1, p2, p3 = [points[j % len(points)] for j in (i-1, i, i+1, i+2)]
    return tuple(0.5*((2*b) + (-a+c)*f + (2*a-5*b+4*c-d)*f*f + (-a+3*b-3*c+d)*f*f*f)
                 for a, b, c, d in zip(p0, p1, p2, p3))


def add_foot(g, config, palette, side):
    # Broad rounded web with three modest toe lobes, a full heel and an ankle dome.
    outline = [(0,-.148),(-.087,-.132),(-.137,-.061),(-.165,.105),(-.17,.176),
               (-.133,.205),(-.073,.194),(-.038,.247),(.012,.267),(.064,.232),
               (.087,.181),(.14,.192),(.173,.151),(.157,.074),(.125,-.068),(.071,-.134)]
    yaw = math.radians(config["foot_splay_degrees"])
    def world(x, y, z):
        return (side*(config["foot_centers_x"] + x*math.cos(yaw) + y*math.sin(yaw)),
                config["foot_center_y"] + y*math.cos(yaw) - x*math.sin(yaw), z)
    previous = None
    # Last loops pull toward the heel, where the ankle disappears into the body.
    layers = [(.6,0.0,0.0),(.9,.008,0.0),(1.0,.027,0.0),(.96,.063,-.005),
              (.75,.112,-.022),(.43,.16,-.038),(.18,.194,-.044)]
    for scale,z,cy in layers:
        points = []
        for i in range(48):
            x, y = closed_outline(outline, i/48.0)
            points.append(world(x*config["foot_width_scale"]*scale, y*scale+cy, z))
        color = mix(palette["foot"], palette["neck_gold"], 0.08*smooth(0.03,0.17,z))
        ring = g.ring(points,[color]*48)
        if previous is None:
            g.cap(ring,world(0.0,0.0,0.0),color)
        else:
            g.bridge(previous,ring)
        previous=ring
    g.cap(previous,world(0,-.044,.202),palette["foot"])


def add_tail(g, palette):
    # A single short fan, not stacked feather scales or an elongated duck tail.
    layers = []
    for sign in (1,-1):
        grid = []
        for row in range(9):
            t = row/8.0
            values = []
            for column in range(17):
                u = -1.0 + 2.0*column/16.0
                # Broad buried attachment rounds into a shallow fan; its center
                # reaches lower than the sides, without a pasted-on straight rim.
                x = u*(.10 + .036*math.sin(math.pi*t) - .045*t*t)
                y = -.205 - .15*t - .021*math.sin(math.pi*t)*(1-u*u)
                z = .49 - .28*t + .055*u*u*t
                thickness = .009 + .025*math.sin(math.pi*t)*(1-u*u)
                values.append(g.vertex((x,y-sign*thickness*.8,z+sign*thickness*.6),palette["tail"]))
            grid.append(values)
        for row in range(8):
            for column in range(16):
                g.faces.append((grid[row][column],grid[row][column+1],grid[row+1][column+1],grid[row+1][column]))
        layers.append(grid)
    top,bottom=layers
    boundary=[(0,c) for c in range(17)]+[(r,16) for r in range(1,9)]+[(8,c) for c in range(15,-1,-1)]+[(r,0) for r in range(7,0,-1)]
    g.bridge([top[r][c] for r,c in boundary],[bottom[r][c] for r,c in boundary])


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config",type=Path,default=DESTINATION/"config.json")
    parser.add_argument("--output-dir",type=Path,default=DESTINATION)
    args=parser.parse_args(sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else [])
    if tuple(bpy.app.version[:3])!=(5,2,0):
        raise RuntimeError("This builder requires Blender 5.2.0")
    output=args.output_dir.resolve()
    output.relative_to(DESTINATION.resolve())
    output.mkdir(parents=True,exist_ok=True)
    config=json.loads(args.config.read_text())
    palette={key:linear_color(value) for key,value in config["palette_srgb"].items()}
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    g=Geometry()
    for label,build in [("continuous_body_head",lambda:add_body(g,config,palette)),
                        ("flipper_L",lambda:add_flipper(g,config,palette,-1)),
                        ("flipper_R",lambda:add_flipper(g,config,palette,1)),
                        ("foot_L",lambda:add_foot(g,config,palette,-1)),
                        ("foot_R",lambda:add_foot(g,config,palette,1)),
                        ("short_tail_fan",lambda:add_tail(g,palette))]:
        start=len(g.vertices);build();g.parts[label]=[start,len(g.vertices)]
    mesh=bpy.data.meshes.new("PenguinRearBlockoutMesh")
    mesh.from_pydata(g.vertices,[],g.faces);mesh.update()
    if mesh.validate(verbose=True):raise RuntimeError("Invalid source topology required repair")
    bm=bmesh.new();bm.from_mesh(mesh)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    nonmanifold=sum(not edge.is_manifold for edge in bm.edges)
    zero_area=sum(face.calc_area()<1e-12 for face in bm.faces)
    volume=bm.calc_volume(signed=True)
    if nonmanifold or zero_area or volume<=0:raise RuntimeError(f"Invalid geometry: {nonmanifold=}, {zero_area=}, {volume=}")
    bm.to_mesh(mesh);bm.free();mesh.update();mesh.calc_loop_triangles()
    # Color assignment below uses original vertex indices: prove bmesh retained them.
    color_position_error=max((vertex.co-Vector(g.vertices[i])).length for i,vertex in enumerate(mesh.vertices))
    if color_position_error>1e-6:raise RuntimeError("bmesh reordered source vertices before COLOR_0 assignment")
    color=mesh.color_attributes.new(name="COLOR_0",type="FLOAT_COLOR",domain="POINT")
    for i,value in enumerate(g.colors):color.data[i].color=value
    mesh.color_attributes.active_color=color
    mesh.color_attributes.render_color_index=0
    for polygon in mesh.polygons:polygon.use_smooth=True
    material=bpy.data.materials.new("RearBlockoutPlainMatte")
    material.use_nodes=True
    shader=material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value=(1,1,1,1)
    shader.inputs["Metallic"].default_value=config["metallic"]
    shader.inputs["Roughness"].default_value=config["roughness"]
    vertex=material.node_tree.nodes.new("ShaderNodeVertexColor");vertex.layer_name="COLOR_0"
    material.node_tree.links.new(vertex.outputs["Color"],shader.inputs["Base Color"])
    mesh.materials.append(material)
    obj=bpy.data.objects.new("RearBlockout",mesh);bpy.context.scene.collection.objects.link(obj)
    for name,(start,end) in g.parts.items():obj.vertex_groups.new(name=name).add(list(range(start,end)),1.0,"REPLACE")
    obj["gate"]="rear-shape-v1";obj["unrigged"]=True;obj["production_ready"]=False
    bpy.context.view_layer.objects.active=obj;obj.select_set(True)
    scene=bpy.context.scene;scene.unit_settings.system="METRIC";scene.unit_settings.scale_length=1.0
    scene.render.fps=30
    triangles=len(mesh.loop_triangles)
    if triangles>=10000:raise RuntimeError(f"Blockout exceeds deliberate 10k target: {triangles}")
    bounds_min=[min(v.co[i] for v in mesh.vertices) for i in range(3)]
    bounds_max=[max(v.co[i] for v in mesh.vertices) for i in range(3)]
    height=bounds_max[2]-bounds_min[2]
    blend=output/"source.blend";glb=output/"candidate.glb"
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(blend),check_existing=False)
    bpy.ops.export_scene.gltf(filepath=str(glb),check_existing=False,export_format="GLB",use_selection=True,
        export_yup=True,export_apply=False,export_materials="EXPORT",export_normals=True,export_texcoords=False,
        export_vertex_color="MATERIAL",export_all_vertex_colors=True,export_skins=False,export_animations=False,
        export_morph=False,export_cameras=False,export_lights=False,export_extras=False)
    raw=glb.read_bytes();length,kind=struct.unpack_from("<II",raw,12);document=json.loads(raw[20:20+length])
    if document.get("skins") or document.get("animations") or document.get("textures") or document.get("images"):
        raise RuntimeError("Unrigged plain-color export unexpectedly includes rig, motion or textures")
    primitives=[p for m in document["meshes"] for p in m["primitives"]]
    if len(primitives)!=1 or any(not {"NORMAL","COLOR_0"}.issubset(p["attributes"]) for p in primitives):
        raise RuntimeError("Expected exactly one normal+literal-color surface")
    if any(any(k.startswith(("JOINTS_","WEIGHTS_")) for k in p["attributes"]) for p in primitives):
        raise RuntimeError("Unexpected skin attributes")
    exported_triangles=sum(document["accessors"][p["indices"]]["count"]//3 for p in primitives)
    if triangles!=exported_triangles:raise RuntimeError("Export triangle count changed")
    metadata={"schema_version":1,"gate":"rear-shape-v1","unrigged":True,"production_ready":False,
        "animation_ready":False,"visual_approval":"pending human Gate1 review",
        "shape_revision":config.get("revision","v1"),
        "material_contract":"plain-literal-COLOR_0","glb_sha256":sha(glb),"source_sha256":sha(blend),
        "builder_sha256":sha(__file__),"config_sha256":sha(args.config),
        "reference_file":config["reference"],"reference_sha256":sha(ROOT/config["reference"]),
        "source_height_m":height,"gameplay_height_m":config["gameplay_height_m"],
        "gameplay_scale":config["gameplay_height_m"]/height,
        "author_axes":"Blender +Z up, +Y forward; exporter converts to glTF/Godot +Y up, -Z forward",
        "bounds_author_m":{"min":bounds_min,"max":bounds_max},"root_transform":"identity",
        "vertices":len(mesh.vertices),"triangles":triangles,"surfaces":len(primitives),
        "material":{"name":material.name,"roughness":config["roughness"],"metallic":config["metallic"],
                    "color_space":"COLOR_0 linear RGBA from explicit sRGB palette; multiply imported baseColorFactor white","textures":[]},
        "parts_vertex_ranges":g.parts,"geometry_validation":{"nonmanifold_edges":nonmanifold,"zero_area_faces":zero_area,"signed_volume_m3":volume,"color_position_index_max_error_m":color_position_error},
        "intentional_overlaps":"Flipper roots, upper feet and tail root bury into continuous body; six closed components in one mesh",
        "deferred":["rig and skinning","all animation","front face detail","UVs and surface textures","LOD and species","runtime promotion"],
        "old_mesh_skeleton_or_animation_used":False,"rendered_frames":0}
    (output/"metadata.json").write_text(json.dumps(metadata,indent=2)+"\n")
    print("BLOCKOUT_METADATA "+json.dumps(metadata,sort_keys=True))


if __name__=="__main__":main()
