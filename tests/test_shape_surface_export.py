"""Separate mapped-surface contract: source geometry, PNG bytes and channel semantics."""
import copy
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch
import zlib

from tests.test_shape_candidate_export import shape


def glb(doc, binary):
    data = json.dumps(doc).encode(); data += b' ' * (-len(data) % 4)
    binary += b'\0' * (-len(binary) % 4)
    return struct.pack('<4sII', b'glTF', 2, 28 + len(data) + len(binary)) + struct.pack('<II', len(data), 0x4E4F534A) + data + struct.pack('<II', len(binary), 0x004E4942) + binary


def png(color):
    def chunk(name, data):
        return struct.pack('>I', len(data)) + name + data + struct.pack('>I', zlib.crc32(name + data))
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', 2, 2, 8, 6, 0, 0, 0)) + chunk(b'IDAT', zlib.compress((b'\0' + bytes(color) * 2) * 2)) + chunk(b'IEND', b'')


def fixture(root):
    binary = bytearray(); views = []; accessors = []
    def accessor(values, width, component=5126):
        index = len(accessors); fmt = 'f' if component == 5126 else 'I'
        raw = struct.pack('<' + fmt * len(values), *values)
        views.append({'buffer': 0, 'byteOffset': len(binary), 'byteLength': len(raw)}); binary.extend(raw)
        accessors.append({'bufferView': len(views)-1, 'componentType': component, 'count': len(values)//width,
                          'type': {1:'SCALAR',2:'VEC2',3:'VEC3',4:'VEC4'}[width]})
        return index
    attrs = {'POSITION': accessor([0,0,0, 1,0,0, 0,1,0],3), 'NORMAL': accessor([0,0,1]*3,3),
             'TANGENT': accessor([1,0,0,1]*3,4), 'TEXCOORD_0': accessor([0,0,1,0,0,1],2)}
    primitive = {'attributes': attrs, 'indices': accessor([0,1,2],1,5125), 'material':0}
    doc = {'asset':{'version':'2.0'},'nodes':[{'mesh':0}], 'meshes':[{'primitives':[primitive]}],
           'accessors':accessors,'bufferViews':views,'buffers':[{'byteLength':len(binary)}]}
    baseline = root/'baseline.glb'; baseline.write_bytes(glb(doc, bytes(binary)))
    metadata = {'geometry_reference': {'path':'art_src/characters/penguin_rear_blockout_v1/candidate.glb', 'glb_sha256':shape.digest(baseline.read_bytes())}, 'surface_maps':{}}
    doc['samplers']=[{'minFilter':9987,'magFilter':9729,'wrapS':33071,'wrapT':33071}]
    doc.update(materials=[{'name':'Surface','doubleSided':True,'normalTexture':{'index':1,'scale':.6},
        'pbrMetallicRoughness':{'baseColorTexture':{'index':0},'metallicRoughnessTexture':{'index':2},'metallicFactor':1,'roughnessFactor':1}}],images=[],textures=[])
    for i,(name,color,space) in enumerate([('base_color',[32,44,52,255],'srgb'),('normal',[128,128,255,255],'linear'),('metallic_roughness',[255,230,0,255],'linear')]):
        encoded=png(color);views.append({'buffer':0,'byteOffset':len(binary),'byteLength':len(encoded)});binary.extend(encoded)
        doc['images'].append({'bufferView':len(views)-1,'mimeType':'image/png'});doc['textures'].append({'source':i,'sampler':0})
        metadata['surface_maps'][name]={'image_index':i,'sha256':shape.digest(encoded),'width':2,'height':2,'color_space':space}
    doc['buffers'][0]['byteLength']=len(binary)
    return doc,bytes(binary),metadata,baseline


class SurfaceContractTests(unittest.TestCase):
    def validate(self, doc, binary, metadata, baseline):
        with patch.object(shape,'V9_SHA',shape.digest(baseline.read_bytes())):
            return shape.validate_surface(doc,binary,metadata,baseline)

    def test_embedded_maps_bound_to_pixels_and_unchanged_geometry(self):
        with tempfile.TemporaryDirectory() as temp:
            d,b,m,r=fixture(Path(temp));result=self.validate(d,b,m,r)
            self.assertEqual(set(result['surface_maps']),{'base_color','normal','metallic_roughness'})
            self.assertEqual(result['surface_maps']['normal']['rgba8_sha256'],shape.digest(bytes([128,128,255,255])*4))
            self.assertEqual(shape.importer_for({'material_contract':shape.SURFACE_CONTRACT}),shape.SURFACE_IMPORTER)
            self.assertIn('gltf/embedded_image_handling=3',shape.SURFACE_IMPORTER)
            self.assertIn('gltf/embedded_image_handling=1',shape.IMPORTER)

    def test_missing_external_reused_and_wrong_color_space_maps_rejected(self):
        mutations=[lambda d,m:d['materials'][0].pop('normalTexture'),
                   lambda d,m:d['images'][0].update(uri='https://example.invalid/map.png'),
                   lambda d,m:d['textures'][2].update(source=0),
                   lambda d,m:m['surface_maps']['base_color'].update(color_space='linear'),
                   lambda d,m:m['surface_maps']['normal'].update(sha256='0'*64),
                   lambda d,m:d['materials'][0]['pbrMetallicRoughness'].update(metallicFactor=0),
                   lambda d,m:d['meshes'][0]['primitives'][0]['attributes'].pop('TANGENT'),
                   lambda d,m:d.update(extensionsUsed=['KHR_materials_unlit']),
                   lambda d,m:d['samplers'][0].update(minFilter=9728)]
        for i,mutate in enumerate(mutations):
            with self.subTest(i=i),tempfile.TemporaryDirectory() as temp:
                d,b,m,r=fixture(Path(temp));mutate(d,m)
                with self.assertRaises(ValueError):self.validate(d,b,m,r)

    def test_geometry_change_and_png_pixel_corruption_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            d,b,m,r=fixture(Path(temp));changed=bytearray(b);struct.pack_into('<f',changed,0,.01)
            with self.assertRaisesRegex(ValueError,'positions'):self.validate(d,bytes(changed),m,r)
            corrupted=bytearray(b);corrupted[-15]^=1
            with self.assertRaisesRegex(ValueError,'checksum'):self.validate(d,bytes(corrupted),m,r)

    def test_metal_channel_cannot_hide_metallic_pixels(self):
        with tempfile.TemporaryDirectory() as temp:
            d,b,m,r=fixture(Path(temp));view=d['bufferViews'][d['images'][2]['bufferView']];encoded=png([255,230,40,255])
            b=b[:view['byteOffset']]+encoded;view['byteLength']=len(encoded);m['surface_maps']['metallic_roughness']['sha256']=shape.digest(encoded)
            with self.assertRaisesRegex(ValueError,'zero metallic'):self.validate(d,b,m,r)

    def test_cyclic_triangle_preserves_proof_but_reversed_winding_rejected(self):
        with tempfile.TemporaryDirectory() as temp:
            d,b,m,r=fixture(Path(temp));attrs=d['meshes'][0]['primitives'][0]['attributes'];index=d['accessors'][d['meshes'][0]['primitives'][0]['indices']];offset=d['bufferViews'][index['bufferView']]['byteOffset']
            changed=bytearray(b);struct.pack_into('<III',changed,offset,1,2,0)
            self.assertEqual(self.validate(d,b,m,r)['geometry_signature'],self.validate(d,bytes(changed),m,r)['geometry_signature'])
            struct.pack_into('<III',changed,offset,0,2,1)
            with self.assertRaisesRegex(ValueError,'topology'):self.validate(d,bytes(changed),m,r)


if __name__=='__main__':unittest.main()
