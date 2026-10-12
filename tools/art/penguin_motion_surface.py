"""One source-authored matte feather revision; independent of pose and lighting.

Pure stdlib pixel recipe also used by the strict motion validator. Blender hook
updates the editable material to the same pixels and specular intent.
"""
from __future__ import annotations
from array import array
import copy
import functools
import hashlib
import importlib.util
from pathlib import Path
import struct
import zlib

REVISION = 'charcoal-feather-contrast-v1'
BASELINE_SHA = 'c895c19f310f71d8667cc871b1947d9a5d635653c99ee5acca4035fcb063c62c'
BASE_COLOR_SHA = '46253671996aba6272f65c3c4c0b1da24c4b1be696887bf1ad1b14bd041d1ee1'
SPECULAR = 0.15
RECIPE_PATH = 'tools/art/penguin_motion_surface.py'
# Atlas rectangles use Blender's bottom-left origin. Tail and both feet stay exact.
REGIONS = ((8, 8, 632, 1016, 12), (648, 520, 816, 1016, 5), (832, 520, 1000, 1016, 5))


def sha(data):
    return hashlib.sha256(data).hexdigest()


def png_pixels(encoded):
    path = Path(__file__).resolve().parents[1] / 'qa/shape_candidate_export.py'
    spec = importlib.util.spec_from_file_location('_surface_pixel_codec', path)
    module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    return module.png_rgba(encoded)


def _box(values, width, height, radius):
    """Separable clipped box mean. Stable float64 order on host and Blender."""
    horizontal = array('d', [0.0]) * len(values)
    result = array('d', [0.0]) * len(values)
    for y in range(height):
        start = y * width
        prefix = [0.0]
        for x in range(width): prefix.append(prefix[-1] + values[start + x])
        for x in range(width):
            low, high = max(0, x-radius), min(width, x+radius+1)
            horizontal[start+x] = (prefix[high]-prefix[low])/(high-low)
    for x in range(width):
        prefix = [0.0]
        for y in range(height): prefix.append(prefix[-1] + horizontal[y*width+x])
        for y in range(height):
            low, high = max(0, y-radius), min(height, y+radius+1)
            result[y*width+x] = (prefix[high]-prefix[low])/(high-low)
    return result


def _png(width, height, rgba):
    def chunk(kind, data):
        return struct.pack('>I',len(data))+kind+data+struct.pack('>I',zlib.crc32(kind+data)&0xffffffff)
    # RGB, lossless Sub filter; every accepted source alpha is opaque.
    rows = bytearray()
    for y in range(height):
        rgb = bytearray(v for x in range(width) for v in rgba[(y*width+x)*4:(y*width+x)*4+3])
        rows.append(1)
        rows.extend((value-(rgb[i-3] if i>=3 else 0))&255 for i,value in enumerate(rgb))
    return (b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',width,height,8,2,0,0,0))
            +chunk(b'IDAT',zlib.compress(rows,9))+chunk(b'IEND',b''))


@functools.lru_cache(maxsize=1)
def _derive(encoded):
    """Return exact revised PNG + receipt; reject any other starting artwork."""
    if sha(encoded) != BASE_COLOR_SHA:
        raise ValueError('Motion surface recipe requires exact accepted c895 base-color PNG')
    width, height, rgba = png_pixels(encoded)
    if (width,height)!=(1024,1024) or any(a!=255 for a in rgba[3::4]):
        raise ValueError('Motion surface recipe requires opaque 1024 atlas')
    result = bytearray(rgba)
    linear = [(c/255/12.92 if c/255<=.04045 else ((c/255+.055)/1.055)**2.4) for c in range(256)]
    measurements = []
    for x0,y0,x1,y1,radius in REGIONS:
        w,h = x1-x0,y1-y0
        indices = [((height-1-y)*width+x)*4 for y in range(y0,y1) for x in range(x0,x1)]
        luminance, mask = array('d'), array('d')
        for i in indices:
            rgb=rgba[i:i+3]; high=max(rgb); low=min(rgb)
            luminance.append(sum(linear[c]*weight for c,weight in zip(rgb,(.2126,.7152,.0722))))
            # Charcoal only. Warm gold, pale underfaces and ivory are excluded.
            mask.append(min(1.,max(0.,(112-high)/12))*min(1.,max(0.,(low/max(high,1)-.64)/.08)))
        weighted = array('d',(v*m for v,m in zip(luminance,mask)))
        smooth_weight = _box(mask,w,h,radius)
        smooth_value = _box(weighted,w,h,radius)
        base = [v/max(m,1e-12) for v,m in zip(smooth_value,smooth_weight)]
        # Double existing feather pigment variation, preserving hue and the
        # chart's weighted mean. Normal relief and feather placement unchanged.
        proposed = [max(v*.60,min(v*1.40,b+2.0*(v-b))) for v,b in zip(luminance,base)]
        correction = sum(v*m for v,m in zip(luminance,mask))/max(sum(v*m for v,m in zip(proposed,mask)),1e-12)
        before_sum=after_sum=0.; changed=0
        for k,i in enumerate(indices):
            if mask[k]<=0: continue
            factor=(1-mask[k])+mask[k]*proposed[k]*correction/max(luminance[k],1e-12)
            for c in range(3):
                value=linear[rgba[i+c]]*factor
                srgb=value*12.92 if value<=.0031308 else 1.055*value**(1/2.4)-.055
                result[i+c]=max(0,min(255,int(srgb*255+.5)))
            before_sum+=luminance[k]*mask[k]
            after_sum+=sum(linear[result[i+c]]*weight for c,weight in enumerate((.2126,.7152,.0722)))*mask[k]
            changed+=result[i:i+3]!=rgba[i:i+3]
        measurements.append({'rectangle':[x0,y0,x1,y1],'changed_texels':changed,
                             'weighted_linear_mean_ratio':after_sum/max(before_sum,1e-12)})
    png = _png(width,height,result)
    receipt = {'id':REVISION,'baseline_glb_sha256':BASELINE_SHA,
               'recipe_path':RECIPE_PATH,'recipe_sha256':sha(Path(__file__).read_bytes()),
               'base_color_before_sha256':sha(encoded),'base_color_after_sha256':sha(png),
               'base_color_rgba8_sha256':sha(result),'specular':SPECULAR,
               'scope':'Charcoal body/flipper pigment contrast; all other texels and normal/MR maps exact. Pose-independent matte specular.',
               'regions':measurements}
    return png,receipt


def derive(encoded):
    png,receipt=_derive(encoded)
    return png,copy.deepcopy(receipt)


def base_color_png(doc, binary):
    texture=doc['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index']
    image=doc['images'][doc['textures'][texture]['source']]
    view=doc['bufferViews'][image['bufferView']]; start=view.get('byteOffset',0)
    return bytes(binary[start:start+view['byteLength']])


def apply_document(doc, binary):
    """Mutate a fresh motion document; preserve every preexisting binary byte."""
    encoded,receipt=derive(base_color_png(doc,binary))
    texture=doc['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index']
    image=doc['images'][doc['textures'][texture]['source']]
    binary.extend(b'\0'*(-len(binary)%4))
    image['bufferView']=len(doc['bufferViews'])
    doc['bufferViews'].append({'buffer':0,'byteOffset':len(binary),'byteLength':len(encoded)})
    binary.extend(encoded);doc['buffers'][0]['byteLength']=len(binary)
    doc['materials'][0].setdefault('extras',{})['ww_motion_surface']=receipt
    return receipt


def apply_blender_material(obj, doc, binary, output_dir):
    """Store matching editable Blender pixels/specular; no render or export."""
    import bpy
    output=Path(output_dir)/'motion-base-color.png'
    output.write_bytes(base_color_png(doc,binary))
    material=obj.data.materials[0];principled=material.node_tree.nodes.get('Principled BSDF')
    principled.inputs['Specular IOR Level'].default_value=SPECULAR
    incoming=principled.inputs['Base Color'].links
    if len(incoming)!=1 or incoming[0].from_node.type!='TEX_IMAGE':
        raise ValueError('Expected source base-color image node')
    image=bpy.data.images.load(str(output),check_existing=False);image.colorspace_settings.name='sRGB';image.pack()
    incoming[0].from_node.image=image
    material['ww_motion_surface']=REVISION
    material['godot_metallic_specular']=SPECULAR
