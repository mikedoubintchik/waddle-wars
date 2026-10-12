#!/usr/bin/env python3
"""Read-only saved Blender source parity for the isolated X -> Y material proof.

No rendering, source writes, or geometry/paint mutation. New semantic masks are
checked against their authored equations, never reverse-inferred from RGB.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import render_hero_penguin_v12_source_proof as author
from hero_penguin_v12_feather_detail_recipe import RECIPE_ID, TILE_SHA256

MATERIALS = ("PreviewBodyFeatherSurface", "DeepNavyFeather", "WarmCreamFeather")
MASK_NAME = "SourceSemanticMasks"


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


def array(collection, field, width, dtype=np.float32):
    result = np.empty(len(collection) * width, dtype=dtype)
    collection.foreach_get(field, result)
    return result.reshape((-1, width))


def signature(values):
    return {"shape": list(values.shape), "dtype": str(values.dtype),
            "sha256": hashlib.sha256(values.tobytes()).hexdigest()}


def connection(socket):
    return [(link.from_node.name, link.from_socket.identifier) for link in socket.links]


def material_snapshot(material):
    nodes = material.node_tree.nodes
    principled = nodes.get("Principled BSDF")
    textures = {}
    for node in nodes:
        if node.type != "TEX_IMAGE" or node.image is None:
            continue
        image = node.image
        filename = Path(image.filepath).name
        if filename in textures:
            raise RuntimeError(f"duplicate texture {filename} in {material.name}")
        textures[filename] = {
            "name": node.name, "image_name": image.name,
            "colorspace": image.colorspace_settings.name,
            "packed_sha256": hashlib.sha256(bytes(image.packed_file.data)).hexdigest()
            if image.packed_file else None,
            "size": list(image.size), "vector_source": connection(node.inputs["Vector"]),
            "interpolation": node.interpolation, "extension": node.extension,
            "projection": node.projection,
        }
    normals = [{"name": node.name, "space": node.space, "uv_map": node.uv_map,
                "rgb_source": connection(node.inputs["Color"])}
               for node in nodes if node.type == "NORMAL_MAP"]
    return {"textures": textures, "normal_maps": normals,
            "bump_nodes": [n.name for n in nodes if n.type == "BUMP"],
            "noise_nodes": [n.name for n in nodes if n.type in ("TEX_NOISE", "TEX_VORONOI", "TEX_WAVE")],
            "recipe": material.get("feather_detail_recipe"),
            "ior": principled.inputs["IOR"].default_value,
            "specular": principled.inputs["Specular IOR Level"].default_value,
            "sheen": principled.inputs["Sheen Weight"].default_value}


def other_material_snapshot(material):
    def value(socket):
        item = getattr(socket, "default_value", None)
        if item is None or isinstance(item, (str, bool, int, float)):
            return item
        return list(item)
    nodes = []
    if material.use_nodes:
        for node in material.node_tree.nodes:
            nodes.append({"name": node.name, "type": node.type,
                          "inputs": [(socket.identifier, value(socket), connection(socket)) for socket in node.inputs],
                          "vertex_color_layer": getattr(node, "layer_name", None)})
    return {"diffuse_color": list(material.diffuse_color), "nodes": nodes,
            "use_nodes": material.use_nodes, "surface_render_method": material.surface_render_method}


def snapshot(path):
    bpy.ops.wm.open_mainfile(filepath=str(path), load_ui=False)
    objects = {}
    for obj in bpy.data.objects:
        row = {"type": obj.type, "matrix": np.asarray(obj.matrix_world, dtype=np.float64),
               "parent": obj.parent.name if obj.parent else None,
               "hide_render": obj.hide_render, "hide_viewport": obj.hide_viewport,
               "data_name": obj.data.name if obj.data else None}
        if obj.type == "MESH":
            mesh = obj.data
            row["arrays"] = {
                "positions": array(mesh.vertices, "co", 3),
                "vertex_normals": array(mesh.vertices, "normal", 3),
                "corner_normals": array(mesh.corner_normals, "vector", 3),
                "loop_vertices": array(mesh.loops, "vertex_index", 1, np.int32),
                "poly_starts": array(mesh.polygons, "loop_start", 1, np.int32),
                "poly_lengths": array(mesh.polygons, "loop_total", 1, np.int32),
                "poly_smooth": array(mesh.polygons, "use_smooth", 1, np.bool_),
                "poly_materials": array(mesh.polygons, "material_index", 1, np.int32),
            }
            row["uv_names"] = [uv.name for uv in mesh.uv_layers]
            row["uv_active"] = mesh.uv_layers.active.name if mesh.uv_layers.active else None
            for uv in mesh.uv_layers:
                row["arrays"]["uv:" + uv.name] = array(uv.data, "uv", 2)
            row["color_metadata"] = {}
            for color in mesh.color_attributes:
                row["color_metadata"][color.name] = [color.domain, color.data_type]
                row["arrays"]["color:" + color.name] = array(color.data, "color", 4)
            row["materials"] = [mat.name if mat else None for mat in mesh.materials]
            row["mask_contract"] = obj.get("source_mask_contract")
            row["modifiers"] = [(mod.name, mod.type, mod.show_render, mod.show_viewport) for mod in obj.modifiers]
            row["shape_keys"] = [] if not mesh.shape_keys else [key.name for key in mesh.shape_keys.key_blocks]
        elif obj.type == "LIGHT":
            row["settings"] = {"type": obj.data.type, "color": list(obj.data.color),
                               "energy": obj.data.energy, "size": obj.data.size if obj.data.type == "AREA" else None}
        elif obj.type == "CAMERA":
            row["settings"] = {"type": obj.data.type, "ortho_scale": obj.data.ortho_scale,
                               "lens": obj.data.lens, "clip_start": obj.data.clip_start, "clip_end": obj.data.clip_end}
        objects[obj.name] = row
    scene = bpy.context.scene
    stage = {"engine": scene.render.engine, "samples": scene.cycles.samples,
             "resolution": [scene.render.resolution_x, scene.render.resolution_y, scene.render.resolution_percentage],
             "view_transform": scene.view_settings.view_transform, "look": scene.view_settings.look,
             "exposure": scene.view_settings.exposure, "gamma": scene.view_settings.gamma,
             "world_color": list(scene.world.node_tree.nodes.get("Background").inputs["Color"].default_value),
             "world_strength": scene.world.node_tree.nodes.get("Background").inputs["Strength"].default_value}
    return {"objects": objects, "materials": {name: material_snapshot(bpy.data.materials[name])
            for name in MATERIALS if name in bpy.data.materials}, "stage": stage,
            "other_materials": {mat.name: other_material_snapshot(mat) for mat in bpy.data.materials
                                if mat.name not in MATERIALS}}


def wing_masks(side):
    root = Vector((side * author.WING_ROOT[0], author.WING_ROOT[1], author.WING_ROOT[2]))
    control = Vector((side * author.WING_CONTROL[0], author.WING_CONTROL[1], author.WING_CONTROL[2]))
    end = Vector((side * author.WING_TIP[0], author.WING_TIP[1], author.WING_TIP[2]))
    values = []
    for ring in range(45):
        t = ring / 44.0
        axis = ((control-root)*(1-t)+(end-control)*t).normalized()
        _broad, thick = (Vector(v) for v in author.paddle_cross_section(tuple(axis), side))
        for segment in range(48):
            angle = math.tau * segment / 48
            cream = 1-author.smoothstep(-.80, -.25, math.cos(angle))
            cream *= author.smoothstep(.14, .27, t)*(1-author.smoothstep(.84, .98, t))
            cream *= author.smoothstep(0, .6, -thick.y*math.sin(angle))
            values.append((cream, 0, 0, 1))
    return np.asarray(values + [(0, 0, 0, 1)]*2, dtype=np.float32)


def main():
    args = sys.argv[sys.argv.index("--")+1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--baseline", type=Path, required=True)
    parser.add_argument("--candidate", type=Path, required=True)
    parser.add_argument("--report", type=Path, required=True)
    opts = parser.parse_args(args)
    if tuple(bpy.app.version[:3]) != (5, 2, 0):
        raise RuntimeError("requires pinned Blender 5.2.0")
    before, after = snapshot(opts.baseline.resolve()), snapshot(opts.candidate.resolve())
    errors, changed, masks, geometry = [], [], {}, {}

    def check(condition, description):
        if not condition:
            errors.append(description)

    check(before["objects"].keys() == after["objects"].keys(), "object inventory changed")
    max_delta = 0.0
    for name, left in before["objects"].items():
        if name not in after["objects"]:
            continue
        right = after["objects"][name]
        check(np.array_equal(left["matrix"], right["matrix"]), name + " transform changed")
        for key in set(left)-{"arrays", "matrix", "color_metadata", "mask_contract"}:
            check(left[key] == right[key], name + " " + key + " changed")
        if left["type"] != "MESH":
            continue
        allowed = {"color:" + MASK_NAME}
        check(set(right["arrays"])-set(left["arrays"]) <= allowed, name + " unexpected new arrays")
        check(set(left["arrays"]) <= set(right["arrays"]), name + " missing old arrays")
        for field, values in left["arrays"].items():
            other = right["arrays"].get(field)
            exact = other is not None and np.array_equal(values, other)
            if not exact:
                changed.append(name + "/" + field)
            check(exact, name + " " + field + " changed")
            if other is not None and values.shape == other.shape and values.dtype.kind == "f":
                max_delta = max(max_delta, float(np.max(np.abs(values-other), initial=0)))
        for attr, metadata in left["color_metadata"].items():
            check(metadata == right["color_metadata"].get(attr), name + " existing attribute metadata changed")
        geometry[name] = {field: signature(values) for field, values in right["arrays"].items()
                          if field != "color:" + MASK_NAME}
        mask = right["arrays"].get("color:" + MASK_NAME)
        if mask is None:
            continue
        check(right["color_metadata"][MASK_NAME] == ["POINT", "FLOAT_COLOR"], name + " wrong mask format")
        check(right["mask_contract"] == "feather-palette-weights-v1", name + " wrong mask contract")
        check(mask.shape == (len(right["arrays"]["positions"]), 4), name + " wrong mask count")
        check(bool(np.isfinite(mask).all() and (mask >= 0).all() and (mask <= 1).all()), name + " invalid mask channels")
        check(bool((mask[:, :3].sum(axis=1) <= 1.0000001).all() and (mask[:, 3] == 1).all()), name + " invalid mask compositing")
        if name.startswith("PaddleWing"):
            expected = wing_masks(float(name.removeprefix("PaddleWing")))
        else:
            check("PreviewBodyFeatherSurface" in right["materials"], name + " unexpected mask object")
            expected = np.asarray([author.body_paint(Vector(point))[1]
                                   for point in right["arrays"]["positions"]], dtype=np.float32)
        delta = float(np.max(np.abs(mask-expected))) if mask.shape == expected.shape else float("inf")
        check(delta <= 1e-6, name + " mask differs from authored weight equations")
        masks[name] = {"vertices": len(mask), "min_rgba": mask.min(axis=0).tolist(),
                       "max_rgba": mask.max(axis=0).tolist(), "authored_equation_max_delta": delta,
                       "nonzero_rgb_counts": np.count_nonzero(mask[:, :3], axis=0).tolist(),
                       "sha256": signature(mask)["sha256"]}
    check(len(masks) == 3 and {"PaddleWing-1", "PaddleWing+1"} <= set(masks), "expected body and both wing masks")
    check(before["stage"] == after["stage"], "lighting/color management/render settings changed")
    check(before["other_materials"] == after["other_materials"], "non-feather material paint/graph changed")
    check(before["materials"].keys() == after["materials"].keys(), "saved feather material inventory changed")
    check({"PreviewBodyFeatherSurface", "DeepNavyFeather"} <= set(after["materials"]), "missing used feather materials")
    for name in before["materials"].keys() & after["materials"].keys():
        left, right = before["materials"][name], after["materials"][name]
        check(left["textures"] == right["textures"], name + " texture images or sampling changed")
        check(set(right["textures"]) == set(TILE_SHA256), name + " expected exactly six original textures")
        for filename, texture in right["textures"].items():
            check(texture["packed_sha256"] == TILE_SHA256.get(filename), name + " packed texture hash differs " + filename)
        for key in ("normal_maps", "bump_nodes", "noise_nodes", "ior", "specular"):
            check(left[key] == right[key], name + " " + key + " changed")
        check(len(right["normal_maps"]) == 1 and not right["bump_nodes"] and not right["noise_nodes"], name + " unexpected normal/bump/noise")
        check(left["recipe"] is None and right["recipe"] == RECIPE_ID, name + " wrong recipe state")
    report = {"passed": not errors, "blender": bpy.app.version_string,
              "baseline": str(opts.baseline.resolve()), "baseline_sha256": sha(opts.baseline),
              "candidate": str(opts.candidate.resolve()), "candidate_sha256": sha(opts.candidate),
              "audit_script_sha256": sha(__file__), "source_generator_sha256": sha(author.__file__),
              "design_sha256": sha(Path(__file__).with_name("hero_penguin_v12_design.py")),
              "command": sys.argv, "read_only_source": True, "rendered": False,
              "source_object_count": len(after["objects"]), "mesh_count": len(geometry),
              "unchanged_geometry_uv_normal_and_existing_paint_max_delta": max_delta,
              "changed_arrays": changed, "source_semantic_masks": masks,
              "materials_baseline": before["materials"], "materials_candidate": after["materials"],
              "unsaved_unused_materials": sorted(set(MATERIALS)-set(after["materials"])),
              "unchanged_nonfeather_materials": sorted(after["other_materials"]),
              "stage": after["stage"], "mesh_array_fingerprints": geometry,
              "errors": errors,
              "omissions": ["Not a bake/GLB/runtime/animation/performance gate.",
                            "No pixel-equivalence claim; recipe intentionally changes material response.",
                            "Material graph evaluation and visual fidelity require separate image review.",
                            "Modifier flags and shape-key names compared; no evaluated-mesh or animation audit."]}
    opts.report.parent.mkdir(parents=True, exist_ok=True)
    opts.report.write_text(json.dumps(report, indent=2, allow_nan=False) + "\n")
    print(json.dumps({"passed": not errors, "objects": len(after["objects"]), "meshes": len(geometry),
                      "max_delta": max_delta, "masks": masks, "errors": errors}, indent=2))
    if errors:
        raise RuntimeError("source material variant audit failed")


if __name__ == "__main__":
    main()
