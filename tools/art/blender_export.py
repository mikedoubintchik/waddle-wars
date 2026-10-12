#!/usr/bin/env python3
"""Blender-internal deterministic GLB exporter. Invoke through export_art.py."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
import os
import sys
from pathlib import Path
from typing import Any

import bpy
from mathutils import Matrix, Vector


REQUIRED_EXPORT_PROPERTIES = {
    "check_existing",
    "export_all_influences",
    "export_all_vertex_colors",
    "export_anim_single_armature",
    "export_animation_mode",
    "export_animations",
    "export_apply",
    "export_armature_object_remove",
    "export_attributes",
    "export_cameras",
    "export_def_bones",
    "export_extras",
    "export_force_sampling",
    "export_format",
    "export_frame_range",
    "export_image_format",
    "export_influence_nb",
    "export_leaf_bone",
    "export_lights",
    "export_materials",
    "export_merge_animation",
    "export_morph",
    "export_morph_normal",
    "export_normals",
    "export_reset_pose_bones",
    "export_rest_position_armature",
    "export_skins",
    "export_tangents",
    "export_texcoords",
    "export_vertex_color",
    "export_yup",
    "filepath",
    "use_selection",
    "will_save_settings",
}


def parse_args() -> argparse.Namespace:
    args = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--expected-version", required=True)
    parser.add_argument("--job-json")
    parser.add_argument("--project-root")
    parser.add_argument("--self-test", action="store_true")
    return parser.parse_args(args)


def fail(message: str) -> None:
    print(f"[art-blender] FAIL {message}", file=sys.stderr)
    raise SystemExit(1)


def exporter_properties() -> dict[str, Any]:
    try:
        rna = bpy.ops.export_scene.gltf.get_rna_type()
    except Exception as exc:  # Blender operator API provides its own exception types.
        fail(f"glTF exporter unavailable: {exc}")
    return {prop.identifier: prop for prop in rna.properties if prop.identifier != "rna_type"}


def exact_version(expected: str) -> None:
    found = ".".join(str(piece) for piece in bpy.app.version[:3])
    if found != expected:
        fail(f"expected Blender {expected}, found {found}")


def file_sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for block in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def safe_output(project_root: Path, value: str) -> Path:
    output = (project_root / value).resolve()
    art_root = (project_root / "assets/art").resolve()
    try:
        output.relative_to(art_root)
    except ValueError:
        fail(f"output escapes assets/art: {value}")
    if output.suffix.lower() != ".glb":
        fail("output must use .glb")
    return output


def collection_objects(collection_name: str) -> list[bpy.types.Object]:
    collection = bpy.data.collections.get(collection_name)
    if collection is None:
        fail(f"collection not found: {collection_name}")
    objects = sorted(collection.all_objects, key=lambda value: value.name_full)
    if not objects:
        fail(f"collection is empty: {collection_name}")
    unsupported = [obj.name_full for obj in objects if obj.type not in {"MESH", "ARMATURE", "EMPTY"}]
    if unsupported:
        fail(f"collection contains unbaked object types: {', '.join(unsupported)}")
    if not any(obj.type == "MESH" for obj in objects):
        fail(f"collection has no mesh: {collection_name}")
    return objects


def validate_transforms(objects: list[bpy.types.Object]) -> None:
    object_set = set(objects)
    for obj in objects:
        scale = tuple(float(piece) for piece in obj.scale)
        if any(not math.isclose(piece, 1.0, abs_tol=1e-5) for piece in scale):
            fail(f"{obj.name_full} has unapplied scale {scale}")
        if obj.parent is None or obj.parent not in object_set:
            identity = Matrix.Identity(4)
            if any(
                not math.isclose(float(obj.matrix_world[row][column]), float(identity[row][column]),
                                 abs_tol=1e-5)
                for row in range(4)
                for column in range(4)
            ):
                fail(f"root {obj.name_full} must have identity world transform")


def validate_modifiers(objects: list[bpy.types.Object]) -> None:
    object_set = set(objects)
    for obj in objects:
        if obj.type != "MESH":
            continue
        unapplied = [
            modifier.name
            for modifier in obj.modifiers
            if modifier.show_render and modifier.type != "ARMATURE"
        ]
        if unapplied:
            fail(f"{obj.name_full} has unapplied render modifiers: {', '.join(unapplied)}")
        for modifier in obj.modifiers:
            if modifier.type != "ARMATURE" or not modifier.show_render:
                continue
            armature = modifier.object
            if armature is None or armature not in object_set:
                fail(f"{obj.name_full} armature modifier must target an exported armature")
            if obj.parent is not armature:
                fail(f"{obj.name_full} skinned mesh must be parented to {armature.name_full}")


def mesh_metrics(objects: list[bpy.types.Object]) -> dict[str, Any]:
    triangles = 0
    surfaces = 0
    influences = 0
    deform_bones = 0
    bounds_min = Vector((math.inf, math.inf, math.inf))
    bounds_max = Vector((-math.inf, -math.inf, -math.inf))
    pivot_bounds_min = Vector((math.inf, math.inf, math.inf))
    pivot_bounds_max = Vector((-math.inf, -math.inf, -math.inf))
    for obj in objects:
        if obj.type == "ARMATURE":
            deform_bones += sum(1 for bone in obj.data.bones if bone.use_deform)
        if obj.type != "MESH":
            continue
        mesh = obj.data
        coordinate_sets: list[Any] = [mesh.vertices]
        if mesh.shape_keys is not None:
            coordinate_sets.extend(key_block.data for key_block in mesh.shape_keys.key_blocks)
        for set_index, coordinates in enumerate(coordinate_sets):
            for vertex in coordinates:
                world = obj.matrix_world @ vertex.co
                bounds_min.x = min(bounds_min.x, world.x)
                bounds_min.y = min(bounds_min.y, world.y)
                bounds_min.z = min(bounds_min.z, world.z)
                bounds_max.x = max(bounds_max.x, world.x)
                bounds_max.y = max(bounds_max.y, world.y)
                bounds_max.z = max(bounds_max.z, world.z)
                if set_index == 0:
                    pivot_bounds_min.x = min(pivot_bounds_min.x, world.x)
                    pivot_bounds_min.y = min(pivot_bounds_min.y, world.y)
                    pivot_bounds_min.z = min(pivot_bounds_min.z, world.z)
                    pivot_bounds_max.x = max(pivot_bounds_max.x, world.x)
                    pivot_bounds_max.y = max(pivot_bounds_max.y, world.y)
                    pivot_bounds_max.z = max(pivot_bounds_max.z, world.z)
        mesh.calc_loop_triangles()
        mesh_triangles = len(mesh.loop_triangles)
        triangles += mesh_triangles
        if mesh_triangles:
            used_materials = {polygon.material_index for polygon in mesh.polygons}
            surfaces += max(1, len(used_materials))
        armature = obj.find_armature()
        deform_group_indices: set[int] = set()
        if armature is not None:
            deform_names = {bone.name for bone in armature.data.bones if bone.use_deform}
            deform_group_indices = {
                group.index for group in obj.vertex_groups if group.name in deform_names
            }
        for vertex in mesh.vertices:
            influences = max(
                influences,
                sum(
                    1 for group in vertex.groups
                    if group.group in deform_group_indices and group.weight > 1e-6
                ),
            )
    if triangles <= 0:
        fail("export collection contains no triangles")
    # Manifest dimensions are width/depth/height in Blender authoring axes.
    bounds_size = bounds_max - bounds_min
    return {
        "lod0_triangles": triangles,
        "surfaces": surfaces,
        "skin_influences": influences,
        "deform_bones": deform_bones,
        "bounds_min": [bounds_min.x, bounds_min.y, bounds_min.z],
        "bounds_max": [bounds_max.x, bounds_max.y, bounds_max.z],
        "bounds_meters": [bounds_size.x, bounds_size.y, bounds_size.z],
        "pivot_bounds_min": [pivot_bounds_min.x, pivot_bounds_min.y, pivot_bounds_min.z],
        "pivot_bounds_max": [pivot_bounds_max.x, pivot_bounds_max.y, pivot_bounds_max.z],
    }


def validate_metrics(metrics: dict[str, Any], expected: dict[str, Any]) -> None:
    comparisons = {
        "lod0_triangles": "lod0_triangles_max",
        "surfaces": "surfaces_max",
        "skin_influences": "skin_influences_max",
        "deform_bones": "deform_bones_max",
    }
    for measured_key, limit_key in comparisons.items():
        if limit_key not in expected:
            continue
        measured = metrics[measured_key]
        limit = int(expected[limit_key])
        if measured > limit:
            fail(f"{measured_key} {measured} exceeds {limit_key} {limit}")
    minimum = int(expected.get("lod0_triangles_min", 1))
    if int(metrics["lod0_triangles"]) < minimum:
        fail(f"lod0_triangles {metrics['lod0_triangles']} below lod0_triangles_min {minimum}")
    maximum_bounds = expected.get("bounds_meters_max", [])
    if not isinstance(maximum_bounds, list) or len(maximum_bounds) != 3:
        fail("bounds_meters_max must contain three values")
    for index, measured in enumerate(metrics["bounds_meters"]):
        limit = float(maximum_bounds[index])
        if measured > limit + 1e-5:
            fail(f"bounds {'XYZ'[index]} {measured:.4f} exceeds {limit:.4f} m")


def validate_pivot(metrics: dict[str, Any], expected: dict[str, Any]) -> None:
    tolerance = float(expected.get("pivot_tolerance_m", 0.01))
    minimum = metrics["pivot_bounds_min"]
    maximum = metrics["pivot_bounds_max"]
    center = [(minimum[index] + maximum[index]) * 0.5 for index in range(3)]
    policy = str(expected.get("pivot_policy", ""))
    if policy == "ground_center":
        if abs(float(minimum[2])) > tolerance \
                or abs(center[0]) > tolerance or abs(center[1]) > tolerance:
            fail(
                f"ground_center pivot outside tolerance {tolerance}: "
                f"min={minimum} max={maximum}"
            )
    elif policy == "center":
        if any(abs(value) > tolerance for value in center):
            fail(f"center pivot outside tolerance {tolerance}: center={center}")
    else:
        fail(f"unknown pivot_policy {policy!r}")


def validate_textures(objects: list[bpy.types.Object], expected: dict[str, Any]) -> None:
    limit = int(expected.get("texture_size_max", 2048))
    seen_images: set[int] = set()
    seen_trees: set[int] = set()

    def validate_tree(node_tree: bpy.types.NodeTree) -> None:
        tree_pointer = node_tree.as_pointer()
        if tree_pointer in seen_trees:
            return
        seen_trees.add(tree_pointer)
        for node in node_tree.nodes:
            if node.type == "GROUP" and node.node_tree is not None:
                validate_tree(node.node_tree)
                continue
            if node.type != "TEX_IMAGE" or node.image is None:
                continue
            image_pointer = node.image.as_pointer()
            if image_pointer in seen_images:
                continue
            seen_images.add(image_pointer)
            if node.image.source not in {"FILE", "GENERATED"}:
                fail(
                    f"texture {node.image.name_full} uses unsupported source "
                    f"{node.image.source}; bake to a regular image"
                )
            if node.image.source == "FILE" and node.image.packed_file is None:
                fail(
                    f"texture {node.image.name_full} must be packed so source_sha256 "
                    "covers export inputs"
                )
            width, height = (int(value) for value in node.image.size[:2])
            for dimension in (width, height):
                if dimension <= 0 or dimension > limit or dimension & (dimension - 1):
                    fail(
                        f"texture {node.image.name_full} dimensions {width}x{height} "
                        f"must be power-of-two <= {limit}"
                    )

    for obj in objects:
        if obj.type != "MESH":
            continue
        for slot in obj.material_slots:
            material = slot.material
            if material is None or material.node_tree is None:
                continue
            validate_tree(material.node_tree)


def action_bone_paths(action: bpy.types.Action) -> list[str]:
    paths: set[str] = set()
    for slot in action.slots:
        if slot.target_id_type != "OBJECT":
            continue
        for layer in action.layers:
            for strip in layer.strips:
                channelbag = strip.channelbag(slot)
                if channelbag is None:
                    continue
                for fcurve in channelbag.fcurves:
                    if fcurve.data_path.startswith('pose.bones['):
                        paths.add(fcurve.data_path)
    return sorted(paths)


def action_has_bone_channels(action: bpy.types.Action, armature: bpy.types.Object) -> bool:
    paths = action_bone_paths(action)
    if not paths:
        return False
    deform_prefixes = tuple(
        f'pose.bones["{bone.name}"]'
        for bone in armature.data.bones
        if bone.use_deform
    )
    has_deform_channel = False
    for path in paths:
        try:
            armature.path_resolve(path, False)
        except ValueError:
            return False
        if path.startswith(deform_prefixes):
            has_deform_channel = True
    return has_deform_channel


def has_nla_strips(animation_data: Any) -> bool:
    return animation_data is not None and any(
        strip.action is not None
        for track in animation_data.nla_tracks
        if not track.mute
        for strip in track.strips
        if not strip.mute
    )


def validate_named_contract(objects: list[bpy.types.Object], expected: dict[str, Any]) -> None:
    required_actions = set(expected.get("required_animations", []))
    actions = {action.name: action for action in bpy.data.actions}
    missing_actions = sorted(required_actions - set(actions))
    if missing_actions:
        fail(f"missing animation actions: {', '.join(missing_actions)}")
    if required_actions:
        armatures = [obj for obj in objects if obj.type == "ARMATURE"]
        if len(armatures) != 1:
            fail(f"animation export requires exactly one armature, found {len(armatures)}")
        root_bones = [bone.name for bone in armatures[0].data.bones if bone.parent is None]
        if len(root_bones) != 1:
            fail(
                "animation armature must have exactly one root bone for standards-clean GLB, "
                f"found {len(root_bones)}"
            )
        if armatures[0].animation_data is None:
            fail(f"armature {armatures[0].name_full} has no animation data")
        nla_owners: list[str] = []
        for obj in objects:
            if has_nla_strips(obj.animation_data):
                nla_owners.append(obj.name_full)
            if obj.type == "MESH" and obj.data.shape_keys is not None \
                    and has_nla_strips(obj.data.shape_keys.animation_data):
                nla_owners.append(f"{obj.name_full}.shape_keys")
        if nla_owners:
            fail(
                "unbaked NLA strips are not allowed in ACTIONS exports: "
                + ", ".join(sorted(nla_owners))
            )
        unexpected = sorted(
            name for name, action in actions.items()
            if name not in required_actions and action_bone_paths(action)
        )
        if unexpected:
            fail(
                "unexpected armature actions would be exported by ACTIONS mode: "
                + ", ".join(unexpected)
            )
        incompatible = sorted(
            name
            for name in required_actions
            if not action_has_bone_channels(actions[name], armatures[0])
            or float(actions[name].frame_range[1]) <= float(actions[name].frame_range[0])
        )
        if incompatible:
            fail(f"animation actions have no timed bone channels: {', '.join(incompatible)}")
    sockets = {obj.name: obj for obj in objects if obj.type == "EMPTY"}
    required_sockets = set(expected.get("required_sockets", []))
    missing_sockets = sorted(required_sockets - set(sockets))
    if missing_sockets:
        fail(f"missing sockets: {', '.join(missing_sockets)}")
    armature_set = {obj for obj in objects if obj.type == "ARMATURE"}
    invalid_sockets = sorted(
        name
        for name in required_sockets
        if sockets[name].parent not in armature_set
        or sockets[name].parent_type != "BONE"
        or not sockets[name].parent_bone
        or sockets[name].parent.data.bones.get(sockets[name].parent_bone) is None
    )
    if invalid_sockets:
        fail(
            "sockets must be EMPTY objects parented directly to exported bones: "
            + ", ".join(invalid_sockets)
        )


def material_mode(properties: dict[str, Any]) -> str:
    prop = properties.get("export_materials")
    if prop is None:
        fail("glTF exporter missing export_materials")
    identifiers = {item.identifier for item in prop.enum_items}
    if "PLACEHOLDER" not in identifiers:
        fail("glTF exporter lacks PLACEHOLDER material mode")
    return "PLACEHOLDER"


def exporter_kwargs(output: Path, export_animations: bool) -> dict[str, Any]:
    properties = exporter_properties()
    missing = sorted(REQUIRED_EXPORT_PROPERTIES - set(properties))
    if missing:
        fail(f"glTF exporter missing required properties: {', '.join(missing)}")
    wanted: dict[str, Any] = {
        "filepath": str(output),
        "check_existing": False,
        "export_format": "GLB",
        "use_selection": True,
        # Applying modifiers here prevents shape-key export. Source validation
        # rejects every unapplied render modifier except the armature instead.
        "export_apply": False,
        "export_yup": True,
        "export_texcoords": True,
        "export_normals": True,
        "export_tangents": True,
        "export_vertex_color": "MATERIAL",
        "export_all_vertex_colors": True,
        "export_attributes": True,
        "export_skins": True,
        "export_all_influences": False,
        "export_influence_nb": 4,
        "export_def_bones": True,
        "export_leaf_bone": False,
        # Removing the single-root Blender armature wrapper keeps the skinned
        # mesh at the GLB root, as required by Khronos validation.
        "export_armature_object_remove": True,
        "export_morph": True,
        "export_morph_normal": True,
        "export_animations": export_animations,
        "export_animation_mode": "ACTIONS",
        "export_merge_animation": "ACTION",
        "export_anim_single_armature": True,
        "export_frame_range": False,
        "export_force_sampling": export_animations,
        "export_reset_pose_bones": True,
        "export_rest_position_armature": True,
        "export_cameras": False,
        "export_lights": False,
        "export_extras": False,
        "export_image_format": "NONE",
        "will_save_settings": False,
        "export_materials": material_mode(properties),
    }
    unsupported = sorted(set(wanted) - set(properties))
    if unsupported:
        fail(f"glTF exporter missing configured properties: {', '.join(unsupported)}")
    return wanted


def select_only(objects: list[bpy.types.Object]) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.select_set(True)
    active = next((obj for obj in objects if obj.type == "MESH"), objects[0])
    bpy.context.view_layer.objects.active = active


def self_test(expected_version: str) -> int:
    exact_version(expected_version)
    properties = exporter_properties()
    missing = sorted(REQUIRED_EXPORT_PROPERTIES - set(properties))
    if missing:
        fail(f"glTF exporter missing required properties: {', '.join(missing)}")
    kwargs = exporter_kwargs(Path("self_test.glb"), True)
    expected_values = {
        "export_animation_mode": "ACTIONS",
        "export_apply": False,
        "export_armature_object_remove": True,
        "export_image_format": "NONE",
        "export_influence_nb": 4,
        "export_materials": "PLACEHOLDER",
        "export_merge_animation": "ACTION",
        "export_vertex_color": "MATERIAL",
    }
    for key, value in expected_values.items():
        if kwargs.get(key) != value:
            fail(f"unexpected exporter setting {key}={kwargs.get(key)!r}")
    if "export_colors" in kwargs:
        fail("obsolete export_colors setting must not be used")
    print(
        "[art-blender] PASS self-test "
        f"version={expected_version} gltf_properties={len(properties)} "
        f"material_mode={material_mode(properties)}"
    )
    return 0


def export(args: argparse.Namespace) -> int:
    exact_version(args.expected_version)
    if not args.job_json or not args.project_root:
        fail("--job-json and --project-root are required for export")
    try:
        job = json.loads(args.job_json)
    except json.JSONDecodeError as exc:
        fail(f"invalid job JSON: {exc}")
    if not isinstance(job, dict):
        fail("job JSON root must be an object")
    project_root = Path(args.project_root).resolve()
    output = safe_output(project_root, str(job.get("output", "")))
    objects = collection_objects(str(job.get("collection", "")))
    validate_transforms(objects)
    validate_modifiers(objects)
    metrics = mesh_metrics(objects)
    expected = job.get("expected", {})
    if not isinstance(expected, dict):
        fail("job expected field must be an object")
    validate_metrics(metrics, expected)
    validate_pivot(metrics, expected)
    validate_textures(objects, expected)
    validate_named_contract(objects, expected)
    select_only(objects)
    output.parent.mkdir(parents=True, exist_ok=True)
    temporary = output.with_name(f".{output.stem}.tmp.glb")
    if temporary.exists():
        temporary.unlink()
    try:
        result = bpy.ops.export_scene.gltf(
            **exporter_kwargs(temporary, bool(job.get("export_animations", False)))
        )
        if "FINISHED" not in result or not temporary.is_file() or temporary.stat().st_size == 0:
            fail(f"glTF export did not produce output: {result}")
        os.replace(temporary, output)
    finally:
        temporary.unlink(missing_ok=True)
    digest = file_sha256(output)
    print(
        "[art-blender] PASS export "
        f"id={job.get('id')} metrics={json.dumps(metrics, sort_keys=True)} "
        f"bytes={output.stat().st_size} sha256={digest}"
    )
    return 0


def main() -> int:
    args = parse_args()
    if args.self_test:
        return self_test(args.expected_version)
    return export(args)


if __name__ == "__main__":
    raise SystemExit(main())
