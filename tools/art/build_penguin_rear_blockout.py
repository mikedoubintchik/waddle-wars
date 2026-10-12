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
        self.foot_profile_receipts = {}
        self.semantic_features = {}
        self.semantic_landmarks = []
        self.foot_anatomy = {}

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
        points, colors, hem_tags = [], [], []
        for i in range(segments):
            theta = math.tau * i / segments
            c, s = math.cos(theta), math.sin(theta)
            x=rx*c
            hem=config["lower_hem_detail"]
            ankle_band=smooth(.075,.13,abs(x))*(1.0-smooth(.345,.405,abs(x)))
            lower_band=smooth(.104,.13,z)*(1.0-smooth(hem["fade_start_z_m"],hem["fade_end_z_m"],z))
            rear=smooth(.20,.75,-s)
            feather=.5+.5*math.cos(math.tau*(abs(x)-.035)/hem["spacing_m"])
            hem_weight=ankle_band*lower_band*feather
            lap_weight=ankle_band*lower_band*rear*(hem["rear_base_weight"]+hem["rear_scallop_weight"]*feather)
            displacement=math.hypot(hem["rear_overlap_m"]*lap_weight,hem["depth_m"]*hem_weight)
            points.append((x,cy+ry*s-hem["rear_overlap_m"]*lap_weight,z-hem["depth_m"]*hem_weight))
            hem_tags.append((max(hem_weight,lap_weight) if z<.285 else 0.0,displacement))
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
        for j,index in enumerate(current):
            if hem_tags[j][0]>.20:
                foot="left" if points[j][0]<0 else "right"
                feature=g.semantic_features.setdefault(foot+"_hem",{"foot":foot,"kind":"hem","source_vertex_indices":[],"max_displacement_m":0.0})
                feature["source_vertex_indices"].append(index)
                feature["max_displacement_m"]=max(feature["max_displacement_m"],hem_tags[j][1])
        if previous is None:
            g.cap(current, (0.0, profile[0][3], bottom), palette["rump"])
        else:
            g.bridge(previous, current)
        previous = current
    g.cap(previous, (0.0, profile[-1][3], top), palette["crown"])


def add_flipper(g, config, palette, side):
    rows = [list(row) for row in config["flipper_profile_t_x_y_z_half_width_half_thickness"]]
    length_scale=config["flipper_poses"]["L" if side<0 else "R"]["length_scale"]
    root_z=rows[0][3]
    for row in rows:row[3]=root_z-(root_z-row[3])*length_scale
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
        segments=config["flipper_cross_segments"]
        points=[]
        for i in range(segments):
            a=math.tau*i/segments
            c,s=math.cos(a),math.sin(a)
            # A shallow central camber gives the paddle volume and a soft edge,
            # without modeled feather scales or a sharp thin blade.
            camber=config["flipper_rear_camber_m"]*math.sin(math.pi*t)*max(0.0,-s)**4
            points.append((side*(x+nx*width*c),y+thickness*s-camber,z+nz*width*c))
        color = mix(palette["flipper"], palette["crown"], 0.35*t)
        ring = g.ring(points, [color]*segments)
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
    # A real rounded foot volume: broad low heel/dorsum, coherent forward web,
    # then a short tapered attachment. The loft is editable at each height;
    # it cannot collapse into a thin plate plus an isolated ankle peak.
    shape=config["foot_shape"]
    heel=shape["heel_depth_m"]
    front=shape["forefoot_length_m"]
    outline=[(0,-heel),(-.085,-heel*.92),(-.127,-heel*.54),(-.137,.025),
             (-.157,.141),(-.15,.187),(-.123,.21),(-.06,.151),
             (-.034,front*.94),(0,front),(.035,front*.94),(.062,.159),
             (.123,.21),(.154,.186),(.16,.137),(.138,.024),(.127,-heel*.54),(.085,-heel*.92)]
    profile=shape["loft_z_width_length_center_x_center_y"]
    pose=config["foot_poses"]["L" if side<0 else "R"]
    yaw=math.radians(config["foot_splay_degrees"]+pose["yaw_offset_degrees"])
    def world(x, y, z):
        # Static ankle lean changes exposure without sliding the planted sole.
        upper_factor=smooth(pose["upper_lean_start_z_m"],pose["upper_lean_full_z_m"],z)
        upper_lean=pose["upper_lean_y_m"]*upper_factor
        upper_lean+=pose["upper_bulge_y_m"]*smooth(.055,.16,z)*(1.0-smooth(.218,profile[-1][0],z))
        x+=pose["upper_lean_x_m"]*upper_factor
        return (side*(config["foot_centers_x"]+pose["center_x_offset_m"]+x*math.cos(yaw)+y*math.sin(yaw)),
                config["foot_center_y"]+pose["forward_offset_m"]+upper_lean+y*math.cos(yaw)-x*math.sin(yaw),z*pose["height_scale"])
    rings,segments=shape["height_rings"],shape["ring_segments"]
    height=profile[-1][0]
    sections=[]
    for row in range(rings):
        z=height*(.5-.5*math.cos(math.pi*row/rings))
        width,length,cx,cy=curve(profile,z)
        points=[]
        for i in range(segments):
            ox,oy=closed_outline(outline,i/float(segments))
            if side>0:ox*=1.0-(1.0-pose["heel_width_scale"])*(1.0-smooth(.01,.13,oy))
            x=cx+ox*config["foot_width_scale"]*pose["width_scale"]*width
            y=cy+oy*length
            points.append(world(x,y,z))
        sections.append([z,cx,cy,points])
    # Ankle lean must not leave a hollow rear shelf. Fill the lower heel to a
    # convex quarter-ellipse reaching the existing rear-most upper section.
    # Sole, forward toes, upper attachment and overall height stay untouched.
    rear_before=[min(p[1] for p in section[3]) for section in sections]
    peak=min(range(len(sections)),key=lambda j:rear_before[j])
    peak_z=sections[peak][0]
    rear_after=[]
    previous=None
    for row,(z,cx,cy,points) in enumerate(sections):
        if shape["convex_rear_heel"] and 0<z<peak_z:
            target=rear_before[0]+(rear_before[peak]-rear_before[0])*math.sqrt(max(0.0,1.0-((z-peak_z)/peak_z)**2))
            back=min(p[1] for p in points);front_y=max(p[1] for p in points)
            fill=target-back
            points=[(x,y+fill*smooth(.4,.96,(front_y-y)/(front_y-back)),pz) for x,y,pz in points]
        rear_after.append(min(p[1] for p in points))
        # Three broad load-bearing rear pads. Recessed valleys join shallow
        # contact notches; these are pad/scute divisions, never backward nails.
        detail=config["rear_pad_detail"]
        left_x,right_x=min(p[0] for p in points),max(p[0] for p in points)
        back_y,front_y=min(p[1] for p in points),max(p[1] for p in points)
        colors,tags,shaped=[],[],[]
        for x,y,pz in points:
            u=2.0*(x-left_x)/(right_x-left_x)-1.0
            rear=smooth(.62,.92,(front_y-y)/(front_y-back_y))
            fade=1.0-smooth(detail["valley_full_height_m"],detail["valley_end_height_m"],z)
            valleys=[math.exp(-.5*((u-center)/detail["valley_sigma_u"])**2) for center in detail["valley_centers_u"]]
            valleys=[v if v>.002 else 0.0 for v in valleys]
            if not pose.get("rear_pad_detail_enabled",True):valleys=[0.0,0.0]
            strength=max(valleys)*rear*fade
            recess=detail["valley_depth_m"]*strength
            notch=detail["contact_notch_m"]*max(valleys)*rear*(1.0-smooth(.012,.042,z))
            shaped.append((x,y+recess,pz+notch))
            darkening=.09*(1.0-smooth(0.0,.035,z))+detail["valley_linear_color_darken"]*strength
            colors.append(tuple(v*(1.0-darkening) for v in palette["foot"]))
            tags.append([j for j,v in enumerate(valleys) if v*rear*fade>.18])
        ring=g.ring(shaped,colors)
        foot_name="left" if side<0 else "right"
        for j in (range(2) if pose.get("rear_pad_detail_enabled",True) else []):
            name=f"{foot_name}_groove_{j+1}"
            feature=g.semantic_features.setdefault(name,{"foot":foot_name,"kind":"groove","source_vertex_indices":[],"max_recess_depth_m":0.0})
            for k,tag in enumerate(tags):
                if j in tag:
                    feature["source_vertex_indices"].append(ring[k])
                    feature["max_recess_depth_m"]=max(feature["max_recess_depth_m"],shaped[k][1]-points[k][1])
        if row==0:
            base_ring=ring
            for j,target_u in (enumerate((-.72,0.0,.72)) if pose.get("rear_pad_detail_enabled",True) else []):
                candidates=[k for k,p in enumerate(shaped) if p[2]==0.0 and p[1]<back_y+.12]
                k=min(candidates,key=lambda k:abs((2.0*(shaped[k][0]-left_x)/(right_x-left_x)-1.0)-target_u))
                g.semantic_landmarks.append({"name":f"{foot_name}_pad_{j+1}_contact","foot":foot_name,"source_vertex_index":ring[k]})
        if previous is None:g.cap(ring,world(cx,cy,0.0),palette["foot"])
        else:g.bridge(previous,ring)
        previous=ring
    g.cap(previous,world(profile[-1][3],profile[-1][4],height),palette["foot"])
    g.foot_anatomy[foot_name]={"rear_heel_source_index":base_ring[0],"forward_middle_toe_source_index":base_ring[segments//2],"ankle_cap_source_index":len(g.vertices)-1,"outward_splay_degrees":math.degrees(yaw),"heel_width_scale":pose.get("heel_width_scale",1.0),"rear_pad_detail_enabled":pose.get("rear_pad_detail_enabled",True)}
    if side>0:
        for label,index in [("rear_heel_contact",base_ring[0]),("forward_middle_toe",base_ring[segments//2]),("ankle_cap",len(g.vertices)-1)]:
            g.semantic_landmarks.append({"name":"right_"+label,"foot":"right","source_vertex_index":index})
    g.foot_profile_receipts["L" if side<0 else "R"]={"rear_section_z_m":[s[0] for s in sections],"rear_y_before_m":rear_before,"rear_y_after_m":rear_after,"peak_z_m":peak_z,"sole_preserved":rear_before[0]==rear_after[0],"method":"convex lower heel fill; no palette change or backward toe additions"}


def apply_forward_lean(g,config):
    angle=math.radians(config["forward_lean_degrees"])
    c,s=math.cos(angle),math.sin(angle)
    py,pz=config["lean_pivot_yz"]
    for name in ("continuous_body_head","flipper_L","flipper_R","short_tail_fan"):
        start,end=g.parts[name]
        for i in range(start,end):
            x,y,z=g.vertices[i]
            if name=="continuous_body_head":
                z-=config["right_hip_settle_m"]*smooth(0.0,.25,x)*(1.0-smooth(.18,.55,z))
            g.vertices[i]=(x,py+c*(y-py)+s*(z-pz),pz-s*(y-py)+c*(z-pz))
    return angle


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
    lean_angle=apply_forward_lean(g,config)
    # Top ankle caps must be inside the leaned body. Test in unpitched author
    # space against its ring envelope; the underside/heel remain outside it.
    attachment_checks=[]
    py,pz=config["lean_pivot_yz"]
    c,s=math.cos(lean_angle),math.sin(lean_angle)
    for part in ("foot_L","foot_R"):
        start,end=g.parts[part]
        x,y,z=g.vertices[end-1]
        uy=py+c*(y-py)-s*(z-pz)
        uz=pz+s*(y-py)+c*(z-pz)
        # Undo the monotonic local right-hip settle before testing the rest ring.
        low,high=uz,uz+config["right_hip_settle_m"]
        for _ in range(24):
            rest_z=(low+high)*.5
            settled_z=rest_z-config["right_hip_settle_m"]*smooth(0.0,.25,x)*(1.0-smooth(.18,.55,rest_z))
            if settled_z<uz:low=rest_z
            else:high=rest_z
        rx,ry,cy=curve(config["body_profile_z_rx_ry_center_y"],(low+high)*.5)
        ratio=(x/rx)**2+((uy-cy)/ry)**2
        sole_min=min(g.vertices[i][2] for i in range(start,end))
        if ratio>=1.0 or sole_min!=0.0:raise RuntimeError("Foot attachment or planted sole failed")
        attachment_checks.append({"part":part,"ankle_cap_body_ellipse_ratio":ratio,"sole_min_z_m":sole_min,"ankle_cap_m":[x,y,z]})
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
    if not 10000<=config["triangle_budget"]<=25000 or triangles>config["triangle_budget"]:raise RuntimeError(f"Candidate exceeds explicit triangle budget: {triangles}")
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
        "pose":{"body_forward_pitch_degrees":config["forward_lean_degrees"],
                "right_hip_settle_m":config["right_hip_settle_m"],
                "integrated_lower_hem":config["lower_hem_detail"],
                "pose_scope":"Static reference stance; shared anatomical foot loft, upper ankle lean and right lower-rump settle. No rig or animation.",
                "author_hip_pivot_yz_m":config["lean_pivot_yz"],
                "leaned_parts":["continuous_body_head","flipper_L","flipper_R","short_tail_fan"],
                "feet_rotated_with_body":False,"crown_forward_direction":"author +Y; exported Godot -Z",
                "static_reference_foot_poses":config["foot_poses"],"static_reference_flipper_poses":config["flipper_poses"],
                "attachment_checks":attachment_checks},
        "vertices":len(mesh.vertices),"triangles":triangles,"triangle_budget":config["triangle_budget"],"surfaces":len(primitives),
        "material":{"name":material.name,"roughness":config["roughness"],"metallic":config["metallic"],
                    "color_space":"COLOR_0 linear RGBA from explicit sRGB palette; multiply imported baseColorFactor white","textures":[]},
        "foot_geometry_diagnostics":g.foot_profile_receipts,"parts_vertex_ranges":g.parts,"geometry_validation":{"nonmanifold_edges":nonmanifold,"zero_area_faces":zero_area,"signed_volume_m3":volume,"color_position_index_max_error_m":color_position_error},
        "intentional_overlaps":"Flipper roots, upper feet and tail root bury into continuous body; six closed components in one mesh",
        "deferred":["rig and skinning","all animation","future front podium and face detail","UVs and surface textures","LOD and species","runtime promotion"],
        "old_mesh_skeleton_or_animation_used":False,"rendered_frames":0}
    # Bind semantic recess labels to the final GLB primitive triangle order.
    json_length=struct.unpack_from("<I",raw,12)[0]
    binary_start=20+json_length+8
    def exported_accessor(index):
        a=document["accessors"][index];v=document["bufferViews"][a["bufferView"]]
        code={5126:"f",5125:"I",5123:"H"}[a["componentType"]]
        width={"VEC3":3,"VEC4":4,"SCALAR":1}[a["type"]]
        size=struct.calcsize("<"+code*width);stride=v.get("byteStride",size)
        start=binary_start+v.get("byteOffset",0)+a.get("byteOffset",0)
        return [struct.unpack_from("<"+code*width,raw,start+i*stride) for i in range(a["count"])]
    primitive=primitives[0]
    positions=exported_accessor(primitive["attributes"]["POSITION"])
    indices=[v[0] for v in exported_accessor(primitive["indices"])]
    position_map={struct.pack("<3f",*v):i for i,v in enumerate(positions)}
    source_to_export={i:position_map[struct.pack("<3f",v.co.x,v.co.z,-v.co.y)] for i,v in enumerate(mesh.vertices)}
    features=[]
    for name,feature in g.semantic_features.items():
        selected={source_to_export[i] for i in feature["source_vertex_indices"]}
        tagged=[i//3 for i in range(0,len(indices),3) if sum(v in selected for v in indices[i:i+3])>=2]
        if not tagged or (feature["kind"]=="groove" and feature["max_recess_depth_m"]<.008):raise RuntimeError("Semantic detail has insufficient real geometry")
        item={"name":name,"foot":feature["foot"],"kind":feature["kind"],"triangle_indices":tagged}
        item.update({k:v for k,v in feature.items() if k.startswith("max_")})
        features.append(item)
    landmarks=[{"name":l["name"],"foot":l["foot"],"position":positions[source_to_export[l["source_vertex_index"]]]} for l in g.semantic_landmarks]
    anatomy={}
    for name,a in g.foot_anatomy.items():
        record={k:v for k,v in a.items() if not k.endswith("source_index")}
        for label,key in [("rear_heel","rear_heel_source_index"),("forward_middle_toe","forward_middle_toe_source_index"),("ankle_cap","ankle_cap_source_index")]:record[label]=positions[source_to_export[a[key]]]
        angle=math.radians(a["outward_splay_degrees"]);direction=Vector(((-1 if name=="left" else 1)*math.sin(angle),0,-math.cos(angle)))
        heel,toe,ankle=[Vector(record[k]) for k in ("rear_heel","forward_middle_toe","ankle_cap")]
        record["anatomical_forward_direction_godot"]=list(direction)
        record["ankle_to_toe_forward_m"]=(toe-ankle).dot(direction)
        record["ankle_to_heel_forward_m"]=(heel-ankle).dot(direction)
        record["forward_toe_axis_dot_body_forward"]=direction.dot(Vector((0,0,-1)))
        anatomy[name]=record
    metadata["anatomical_foot_direction"]=anatomy
    feature_tags={"schema_version":1,"candidate_sha256":metadata["glb_sha256"],"method":"Real rear sole-pad recesses and continuous lower-hem displacements tagged during mesh deformation, mapped by exact exported POSITION into final GLB primitive triangle order; not inferred from color.","features":features,"landmarks":landmarks,"detail_parameters":config["rear_pad_detail"],"foot_anatomy":anatomy}
    (output/"feature-tags.json").write_text(json.dumps(feature_tags,indent=2)+"\n")
    metadata["feature_tags_sha256"]=sha(output/"feature-tags.json")
    (output/"metadata.json").write_text(json.dumps(metadata,indent=2)+"\n")
    print("BLOCKOUT_METADATA "+json.dumps(metadata,sort_keys=True))


if __name__=="__main__":main()
