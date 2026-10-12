"""Historical daylight recipe, replayed only against its exact pre-promotion source.

No image recoloring, model/map mutation or generic saturation adjustment. The
fixed source hashes preserve the original review experiment. This recipe was
promoted to normal gameplay on 2026-10-12; current runtime exports need no
--runner-color-review flag. Historical tests use the preserved text fixture.
"""
from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re

RECIPE_ID = 'runner-day-water-v6'
SUN_ENERGY = 0.25
WATER_DETAIL = {
    'day_detail_weight': 1.0,
    'day_tile_metres': [10.0, 128.0],
    'day_lateral_reference_metres': 80.0,
    # Nonnegative material inputs calibrated against Godot's existing GLES3
    # ACES/exposure/white pipeline. A zero-red input can produce negative red
    # *after* ACES, where the engine's fractional-power conversion is undefined.
    'day_trough_tint': [0.1733874951, 0.3539693131, 0.6587933568, 1.0],
    'day_body_tint': [0.1617658861, 0.4084237627, 0.7555587524, 1.0],
    'day_face_tint': [0.1070936283, 0.4641352836, 0.8910564644, 1.0],
    'day_crest_tint': [0.68, 0.94, 1.0, 1.0],
}
BINDING_PATH = '_qa_local/runner_color_binding.json'
SOURCE_SHA256 = {
    'data/art/course_profiles/runner_day.tres': '0d8cd8f3428eb260d8b2420128823c470db059c218f1bf480a1073155e7d2d0d',
    'scripts/runner/runner_track.gd': 'a826ac2d121c5121899cb44e568881a9815802d221b1ab6cf9a93f4a21653561',
    'scripts/runner/runner_game.gd': '48c8fcf13078c5083883838a91328c12a657e48cead3cdd8738132e50dd89faf',
    'scripts/runner/runner_painted_sea.gd': '87a6b592e7f856c948f2c3ae761ff113ee3f8d0b3a635985360141b4306cb066',
    'assets/art/runner/materials/runner_painted_sea_v1.gdshader': '6e6f02a4f28b17c459a9e02ba116dd2f9bde2f1f77408048c87284f19ee989ac',
}


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def water_detail_uniforms() -> str:
    """Keep colour uniforms renderer-aware; only scalar paint is normalized."""
    return '''// Isolated DAY review: original non-DAY path remains below.
uniform float day_detail_weight = 0.0;
uniform vec2 day_tile_metres = vec2(10.0, 128.0);
uniform float day_lateral_reference_metres = 80.0;
uniform vec4 day_trough_tint : source_color = vec4(0.1733874951, 0.3539693131, 0.6587933568, 1.0);
uniform vec4 day_body_tint : source_color = vec4(0.1617658861, 0.4084237627, 0.7555587524, 1.0);
uniform vec4 day_face_tint : source_color = vec4(0.1070936283, 0.4641352836, 0.8910564644, 1.0);
uniform vec4 day_crest_tint : source_color = vec4(0.68, 0.94, 1.0, 1.0);

// Compatibility samples source_color in sRGB; Forward+ uses linear. The
// authored paint thresholds are sRGB scalars, while palette RGB always stays
// in the renderer's own working space through source_color uniforms.
float paint_srgb_scalar(float value) {
    if (OUTPUT_IS_SRGB) {
        return value;
    }
    return value <= 0.0031308 ? value * 12.92 : 1.055 * pow(value, 1.0 / 2.4) - 0.055;
}
'''


def water_detail_fragment() -> str:
    return '''// The runner's low fixed-lateral camera makes off-axis world-X
    // derivatives enormous. World-fixed UVs require >100:1 anisotropy here,
    // averaging painted wave bodies into rows. Angular lateral coordinates
    // keep the same paint readable; longitudinal phase remains world-anchored.
    // This is authored runner-camera mapping, not a change to mip filtering.
    float detail_weight = clamp(day_detail_weight, 0.0, 1.0);
    if (painted_enabled && detail_weight > 0.0) {
        float view_depth = max(-VERTEX.z, 1.0);
        vec2 detail_coordinates = vec2(
            VERTEX.x / view_depth * day_lateral_reference_metres / day_tile_metres.x,
            world_pos.z / day_tile_metres.y);
        vec2 detail_uv = abs(fract(detail_coordinates * 0.5) * 2.0 - 1.0);
        float signal = paint_srgb_scalar(texture(painted_albedo, detail_uv).g);
        vec3 detailed_water = mix(day_trough_tint.rgb, day_body_tint.rgb,
            smoothstep(0.35, 0.43, signal));
        detailed_water = mix(detailed_water, day_face_tint.rgb,
            smoothstep(0.43, 0.58, signal));
        // A sparse smooth tail survives filtering without whitening every
        // wave face. These highlights follow the existing painted facets.
        float catch_weight = smoothstep(0.60, 0.73, signal);
        detailed_water = mix(detailed_water, day_crest_tint.rgb, catch_weight);
        near_water = mix(near_water, detailed_water, detail_weight);
    }
    // Preserve the exact distant sky match and smooth approach to it. DAY
    // keeps saturated middle-distance facets instead of bleaching them early.
    float day_haze = haze * haze;
    day_haze *= day_haze;
    float detailed_haze = mix(haze, day_haze, detail_weight);
    ALBEDO = mix(near_water, distant_ground, detailed_haze);'''


def water_detail_setup() -> str:
    lines = ['\tmaterial_override = _water_material']
    for name, value in WATER_DETAIL.items():
        if name == 'day_detail_weight':
            continue  # Driven by the existing biome interpolation below.
        if isinstance(value, (int, float)):
            lines.append(f'\t_water_material.set_shader_parameter("{name}", {value})')
            continue
        constructor = 'Vector2' if len(value) == 2 else 'Color'
        values = ', '.join(str(component) for component in value)
        lines.append(f'\t_water_material.set_shader_parameter("{name}", {constructor}({values}))')
    return '\n'.join(lines) + '\n'


def replacements() -> dict:
    return {
        'data/art/course_profiles/runner_day.tres': [
            ('sun_energy = 1.24\n', f'sun_energy = {SUN_ENERGY}\n'),
            ('sky_top = Color(0.035, 0.46, 0.95, 1)', 'sky_top = Color(0.02, 0.42, 1, 1)'),
            ('sky_horizon = Color(0.34, 0.76, 1, 1)', 'sky_horizon = Color(0.18, 0.70, 1, 1)'),
        ],
        'scripts/runner/runner_track.gd': [
            ('"sun_energy": 1.24,', f'"sun_energy": {SUN_ENERGY},'),
            ('return Color(0.34, 0.53, 0.69)', 'return Color(0.15, 0.57, 0.84)'),
            ('"sky_top": Color(0.035, 0.46, 0.95)', '"sky_top": Color(0.02, 0.42, 1.0)'),
            ('"sky_horizon": Color(0.34, 0.76, 1.0)', '"sky_horizon": Color(0.18, 0.70, 1.0)'),
        ],
        'scripts/runner/runner_game.gd': [
            ('"fill_energy": 0.40, "rim_energy": 0.95}, true)',
             '"fill_energy": 0.40, "rim_energy": 0.95,\n'
             '\t\t\t\t"water_tint": Color(0.008, 0.44, 0.75), "water_haze": Vector2(110.0, 600.0),\n'
             '\t\t\t\t"water_crest_tint": Vector3(0.08, 0.75, 1.0), "water_detail_weight": 1.0}, true)'),
        ],
        'scripts/runner/runner_painted_sea.gd': [
            ('var water := reference_water_tint(horizon, bottom)',
             'var water: Color = environment.get("water_tint", reference_water_tint(horizon, bottom))'),
            ('var _bottom_tint: Color\n', 'var _bottom_tint: Color\nvar _haze_distances := Vector2(110.0, 600.0)\n'
             'var _crest_tint := Vector3(0.70, 0.91, 1.0)\nvar _detail_weight := 0.0\n'),
            ('\tmaterial_override = _water_material\n', water_detail_setup()),
            ('var amount := clampf(weight, 0.0, 1.0)',
             'var haze: Vector2 = environment.get("water_haze", Vector2(110.0, 600.0))\n'
             '\tvar crest: Vector3 = environment.get("water_crest_tint", Vector3(0.70, 0.91, 1.0))\n'
             '\tvar detail: float = environment.get("water_detail_weight", 0.0)\n'
             '\tvar amount := clampf(weight, 0.0, 1.0)'),
            ('var next_bottom := _bottom_tint.lerp(bottom, amount)',
             'var next_bottom := _bottom_tint.lerp(bottom, amount)\n'
             '\tvar next_haze := _haze_distances.lerp(haze, amount)\n'
             '\tvar next_crest := _crest_tint.lerp(crest, amount)\n'
             '\tvar next_detail := lerpf(_detail_weight, detail, amount)'),
            ('\t\t_water_material.set_shader_parameter("bottom_tint", _bottom_tint)\n',
             '\t\t_water_material.set_shader_parameter("bottom_tint", _bottom_tint)\n'
             '\tif next_haze != _haze_distances:\n'
             '\t\t_haze_distances = next_haze\n'
             '\t\t_water_material.set_shader_parameter("haze_distances", _haze_distances)\n'
             '\tif next_crest != _crest_tint:\n'
             '\t\t_crest_tint = next_crest\n'
             '\t\t_water_material.set_shader_parameter("crest_tint", _crest_tint)\n'
             '\tif next_detail != _detail_weight:\n'
             '\t\t_detail_weight = next_detail\n'
             '\t\t_water_material.set_shader_parameter("day_detail_weight", _detail_weight)\n'),
        ],
        'assets/art/runner/materials/runner_painted_sea_v1.gdshader': [
            ('// Painted ocean: one opaque plane, one filtered sample, no reflection/depth',
             '// Painted ocean: one opaque plane, at most two filtered samples, no reflection/depth'),
            ('uniform float tile_metres = 32.0;',
             'uniform float tile_metres = 32.0;\nuniform vec2 haze_distances = vec2(110.0, 600.0);\n'
             'uniform vec3 crest_tint = vec3(0.70, 0.91, 1.0);\n' + water_detail_uniforms()),
            ('smoothstep(110.0, 600.0, distance_to_camera)',
             'smoothstep(haze_distances.x, haze_distances.y, distance_to_camera)'),
            ('mix(near_water, vec3(0.70, 0.91, 1.0), crest * 0.48)',
             'mix(near_water, crest_tint, crest * 0.48)'),
            ('ALBEDO = mix(near_water, distant_ground, haze);', water_detail_fragment()),
        ],
    }


def patched(path: str, raw: bytes) -> bytes:
    text = raw.decode('utf-8')
    for before, after in replacements()[path]:
        if text.count(before) != 1:
            raise ValueError(f'Color recipe requires exactly one replacement: {path}: {before!r}')
        text = text.replace(before, after, 1)
    return text.encode('utf-8')


def validate_source(source: Path) -> dict[str, bytes]:
    """Preflight all source bytes before prepare creates a destination."""
    source = source.resolve()
    result = {}
    for relative, expected in SOURCE_SHA256.items():
        path = source / relative
        if path.is_symlink() or not path.resolve().is_relative_to(source):
            raise ValueError(f'Unsafe color source: {relative}')
        raw = path.read_bytes()
        if digest(raw) != expected:
            raise ValueError(f'Color recipe source changed: {relative}')
        result[relative] = patched(relative, raw)
    return result


def install(source: Path, project: Path) -> dict:
    source, project = source.resolve(), project.resolve()
    if source == project:
        raise ValueError('Color recipe requires separate isolated QA project')
    outputs = validate_source(source)
    config_path = project / 'project.godot'
    local = project / '_qa_local'
    binding_path = project / BINDING_PATH
    if config_path.is_symlink() or not config_path.resolve().is_relative_to(project) \
            or not local.is_dir() or local.is_symlink() or not local.resolve().is_relative_to(project):
        raise ValueError('Unsafe color recipe destination')
    config = config_path.read_text()
    if not re.search(r'^config/custom_user_dir_name="waddle-chrome-reference-[^"\n]+"$', config, re.M) \
            or 'config/use_custom_user_dir=true' not in config \
            or config.count('ChromeReferenceQA="*res://_qa_local/chrome_reference_bridge.gd"') != 1:
        raise ValueError('Color recipe requires isolated Chrome QA identity')
    if binding_path.exists() or binding_path.is_symlink():
        raise ValueError('Color recipe already installed')
    files = {}
    for relative, output in outputs.items():
        path = project / relative
        if path.is_symlink() or not path.resolve().is_relative_to(project) or path.samefile(source / relative):
            raise ValueError(f'Unsafe color destination: {relative}')
        if digest(path.read_bytes()) != SOURCE_SHA256[relative]:
            raise ValueError(f'Copied color source differs: {relative}')
        files[relative] = {'source_sha256': SOURCE_SHA256[relative],
                           'prepared_sha256': digest(output),
                           'replacements': len(replacements()[relative])}
    receipt = {
        'schema': 1, 'id': RECIPE_ID, 'recipe_sha256': digest(Path(__file__).read_bytes()),
        'human_approval': False, 'gallery_eligible': False,
        'production_runtime_unchanged': True, 'binding_path': BINDING_PATH,
        'files': files,
        'settings': {
            'biome': 'DAY', 'sun_energy_before': 1.24, 'sun_energy': SUN_ENERGY,
            'deck_tint_before': [0.34, 0.53, 0.69], 'deck_tint': [0.15, 0.57, 0.84],
            'water_tint_before': [0.02054, 0.400896, 0.6636], 'water_tint': [0.008, 0.44, 0.75],
            'water_haze_before': [110.0, 600.0], 'water_haze': [110.0, 600.0],
            'water_crest_tint_before': [0.70, 0.91, 1.0], 'water_crest_tint': [0.08, 0.75, 1.0],
            'water_detail': WATER_DETAIL,
            **{f'water_{name}': value for name, value in WATER_DETAIL.items()},
            'water_detail_haze': 'DAY: original smoothstep to fourth power; unchanged 110/600 m endpoints',
            'water_palette_calibration': {
                'renderer': 'Godot 4.7.1 a13da4feb GLES3 / gl_compatibility',
                'target_encoded_rgb8': {'trough': [8, 85, 175], 'body': [8, 105, 195], 'face': [8, 125, 215]},
                'tonemap': 'ACES', 'exposure': 0.86, 'white': 6.0,
                'method': 'Offline inverse of existing engine pipeline; nonnegative material inputs only',
                'limitation': 'Near-water palette interpolation is positive after ACES. Preserved far-horizon ground colors are outside that proof.',
                'capture_color_management': 'Chrome JPEG captures embed Display P3; numeric comparison must convert samples in memory to reference sRGB. Original image bytes remain unchanged.',
            },
            'water_detail_signal': 'Existing paint green in sRGB; trough/body/face .35/.43/.58; catches .60/.73',
            'water_detail_mapping': 'DAY lateral angular viewX/viewDepth at 80 m reference, world-Z phase at 128 m; fixed-lateral runner camera',
            'water_detail_mapping_limit': 'Lateral texture phase follows camera angle; a future horizontally moving or orbiting camera requires separate art review',
            'water_texture_samples_max': 2,
            'water_filtering': 'Original linear mipmaps and anisotropy; no LOD bias or new textures',
            'sky_top_before': [0.035, 0.46, 0.95], 'sky_top': [0.02, 0.42, 1.0],
            'sky_horizon_before': [0.34, 0.76, 1.0], 'sky_horizon': [0.18, 0.70, 1.0],
            'ambient_energy': 0.56, 'fill_energy': 0.40, 'rim_energy': 0.95,
            'tonemap': 'ACES', 'tonemap_exposure': 0.86,
            'other_biomes': 'unchanged; existing interpolation retained',
            'model_material_maps': 'unchanged, including both feet',
        },
        'scope': 'Unpromoted DAY water facets and sparse catches, with v3 hero/ice/sky unchanged. Original haze endpoints and non-DAY behavior retained. Actual game render required for review.',
    }
    # All checks complete before the first write. Source paths are never written.
    for relative, output in outputs.items():
        (project / relative).write_bytes(output)
    encoded = (json.dumps(receipt, indent=2) + '\n').encode()
    with binding_path.open('xb') as stream:
        stream.write(encoded)
    return {**receipt, 'binding_sha256': digest(encoded)}
