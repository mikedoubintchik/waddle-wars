"""Localized gate mutation checks against the immutable b21 source; no engines."""
import copy
import json
from pathlib import Path
import struct
import unittest
from tests.test_shape_candidate_export import shape

ROOT=Path(__file__).resolve().parents[1]


class LocalSurfaceContractTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.package=ROOT/'art_src/characters/penguin_rear_surface_v1'
        cls.doc,cls.binary=shape.glb_data((cls.package/'candidate.glb').read_bytes())
        cls.metadata=json.loads((cls.package/'metadata.json').read_text())
        cls.metadata.update(gate='rear-surface-v2',geometry_contract=shape.LOCAL_GEOMETRY_CONTRACT,
            geometry_reference={'path':'art_src/characters/penguin_rear_surface_v1/candidate.glb','glb_sha256':shape.B21_SHA})
        cls.primitive=cls.doc['meshes'][0]['primitives'][0]
        cls.positions=shape.accessor_values(cls.doc,cls.binary,cls.primitive['attributes']['POSITION'])

    def changed(self,name,index,values):
        accessor=self.doc['accessors'][self.primitive['attributes'][name]]
        view=self.doc['bufferViews'][accessor['bufferView']]
        width={'VEC2':2,'VEC3':3,'VEC4':4}[accessor['type']]
        start=view.get('byteOffset',0)+accessor.get('byteOffset',0)+index*view.get('byteStride',width*4)
        result=bytearray(self.binary);struct.pack_into('<'+'f'*width,result,start,*values);return bytes(result)

    def check_geometry(self,binary,metadata=None):
        return shape.validate_local_geometry(self.doc,binary,self.doc,self.binary,metadata or self.metadata)

    def test_identity_and_local_flipper_change_pass(self):
        baseline=self.check_geometry(self.binary);self.assertEqual(set(baseline['protected_parts']),shape.PROTECTED_PARTS)
        point=min(self.positions,key=lambda p:p[0]);result=self.binary
        for i,p in enumerate(self.positions):
            if p==point:
                old=self.binary;self.binary=result
                try:result=self.changed('POSITION',i,(p[0]-.001,p[1],p[2]))
                finally:self.binary=old
        changed=self.check_geometry(result);self.assertNotEqual(changed['components']['flipper_L'],baseline['components']['flipper_L'])

    def test_protected_body_and_feet_normal_changes_rejected(self):
        for region,index in [('head',max(range(len(self.positions)),key=lambda i:self.positions[i][1])),
                             ('left_foot',min(range(len(self.positions)),key=lambda i:self.positions[i][1]+(0 if self.positions[i][0]<0 else 10))),
                             ('right_foot',min(range(len(self.positions)),key=lambda i:self.positions[i][1]+(0 if self.positions[i][0]>0 else 10)))]:
            normals=shape.accessor_values(self.doc,self.binary,self.primitive['attributes']['NORMAL']);n=normals[index]
            with self.subTest(region=region),self.assertRaisesRegex(ValueError,'Protected'):
                self.check_geometry(self.changed('NORMAL',index,(-n[0],-n[1],-n[2])))

    def test_protected_body_tangent_change_rejected(self):
        index=max(range(len(self.positions)),key=lambda i:self.positions[i][1]);t=shape.accessor_values(self.doc,self.binary,self.primitive['attributes']['TANGENT'])[index]
        with self.assertRaisesRegex(ValueError,'Protected'):self.check_geometry(self.changed('TANGENT',index,(-t[0],-t[1],-t[2],t[3])))

    def test_uv_topology_and_candidate_relabeling_rejected(self):
        with self.assertRaisesRegex(ValueError,'UV topology'):self.check_geometry(self.changed('TEXCOORD_0',0,(.99,.99)))
        m=copy.deepcopy(self.metadata);m['parts_vertex_ranges']['continuous_body_head']=[0,482]
        with self.assertRaisesRegex(ValueError,'contract/ranges'):self.check_geometry(self.binary,m)

    def test_open_or_reversed_topology_rejected(self):
        a=self.doc['accessors'][self.primitive['indices']];v=self.doc['bufferViews'][a['bufferView']];start=v.get('byteOffset',0)+a.get('byteOffset',0);fmt='H' if a['componentType']==5123 else 'I';size=struct.calcsize('<'+fmt)
        values=list(struct.unpack_from('<'+fmt*3,self.binary,start));changed=bytearray(self.binary);struct.pack_into('<'+fmt*3,changed,start,*values[::-1])
        with self.assertRaisesRegex(ValueError,'closed'):self.check_geometry(bytes(changed))
        struct.pack_into('<'+fmt*3,changed,start,values[0],values[0],values[2])
        with self.assertRaisesRegex(ValueError,'degenerate'):self.check_geometry(bytes(changed))

    def test_exact_protected_map_regions_reject_one_changed_pixel(self):
        maps=self.metadata['surface_maps'];self.assertEqual(len(shape.validate_protected_pixels(self.doc,self.binary,self.doc,self.binary,self.metadata,maps)),3)
        # Decode bytes are supplied independently; metadata hashes cannot bless an altered protected texel.
        original=shape.png_rgba;calls=0
        def altered(encoded):
            nonlocal calls
            w,h,pixels=original(encoded);calls+=1
            if calls==2:
                pixels=bytearray(pixels);pixels[((1024-1016)*1024+8)*4]^=1;pixels=bytes(pixels)
            return w,h,pixels
        from unittest.mock import patch
        with patch.object(shape,'png_rgba',altered),self.assertRaisesRegex(ValueError,'Protected body/feet map pixels'):
            shape.validate_protected_pixels(self.doc,self.binary,self.doc,self.binary,self.metadata,maps)

    def test_v1_still_rejects_scoped_geometry_reference(self):
        m=copy.deepcopy(self.metadata);m['gate']='rear-surface-v1'
        with self.assertRaisesRegex(ValueError,'unchanged V9'):shape.validate_surface(self.doc,self.binary,m)


if __name__=='__main__':unittest.main()
