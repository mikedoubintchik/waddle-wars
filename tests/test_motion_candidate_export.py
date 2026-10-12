"""Motion candidate isolation, real rest-byte preservation and hostile rig inputs."""
import copy
import importlib.util
import json
from pathlib import Path
import struct
import tempfile
import unittest
from unittest.mock import patch

from tests.test_hero_candidate_export import fixture as project_fixture, inventory, write
from tests.test_shape_surface_export import glb

ROOT=Path(__file__).resolve().parents[1]
spec=importlib.util.spec_from_file_location('motion_candidate_export',ROOT/'tools/qa/motion_candidate_export.py')
motion=importlib.util.module_from_spec(spec);spec.loader.exec_module(motion)


def add_accessor(doc,binary,rows,kind,component=5126):
    fmt={5126:'f',5123:'H'}[component];binary.extend(b'\0'*(-len(binary)%4))
    raw=struct.pack('<'+fmt*sum(len(r) for r in rows),*(v for row in rows for v in row))
    view=len(doc['bufferViews']);doc['bufferViews'].append({'buffer':0,'byteOffset':len(binary),'byteLength':len(raw)});binary.extend(raw)
    index=len(doc['accessors']);doc['accessors'].append({'bufferView':view,'componentType':component,'count':len(rows),'type':kind});return index


def rig_fixture(real=False):
    if real:
        doc,data=motion.shape.glb_data((ROOT/motion.REST_PATH).read_bytes());binary=bytearray(data)
        count=doc['accessors'][doc['meshes'][0]['primitives'][0]['attributes']['POSITION']]['count']
    else:
        doc={'nodes':[],'meshes':[{'primitives':[{'attributes':{}}]}],'accessors':[],'bufferViews':[],'buffers':[{}]};binary=bytearray();count=3
        doc['meshes'][0]['primitives'][0]['attributes']['POSITION']=add_accessor(doc,binary,[(0.,0.,0.)]*count,'VEC3')
    doc['nodes']=[{'mesh':0,'skin':0},{'name':'Root','children':[2]},{'name':'Body'}];doc['scenes']=[{'nodes':[0,1]}];doc['scene']=0
    identity=tuple(float(i==j) for j in range(4) for i in range(4))
    doc['skins']=[{'joints':[1,2],'skeleton':1,'inverseBindMatrices':add_accessor(doc,binary,[identity,identity],'MAT4')}]
    attrs=doc['meshes'][0]['primitives'][0]['attributes']
    attrs['JOINTS_0']=add_accessor(doc,binary,[(0,1,0,0)]*count,'VEC4',5123)
    attrs['WEIGHTS_0']=add_accessor(doc,binary,[(.5,.5,0.,0.)]*count,'VEC4')
    doc['animations']=[];metadata={'rig':{'joints':['Root','Body']},'clips':{}}
    for name,duration in [('waddle',1.2),('jump',1.),('slide',1.2)]:
        times=add_accessor(doc,binary,[(0.,),(duration/2,),(duration,)],'SCALAR');values=add_accessor(doc,binary,[(0.,0.,0.),(.02,0.,0.),(0.,0.,0.)],'VEC3')
        doc['animations'].append({'name':name,'channels':[{'target':{'node':2,'path':'translation'},'sampler':0}], 'samplers':[{'input':times,'output':values,'interpolation':'LINEAR'}]})
        metadata['clips'][name]={'duration':duration,'loop':motion.CLIPS[name]}
    doc['buffers'][0]['byteLength']=len(binary)
    return doc,binary,metadata


def package_fixture(folder):
    d,b,m=rig_fixture(real=True);package=folder/'package';package.mkdir()
    baseline=json.loads((ROOT/motion.REST_PATH).with_name('metadata.json').read_text())
    for k in ['source_height_m','gameplay_height_m','gameplay_scale','surface_maps']:m[k]=baseline[k]
    m.update(schema_version=1,gate=motion.GATE,unrigged=False,animation_ready=True,production_ready=False,material_contract=motion.shape.SURFACE_CONTRACT,rest_reference={'path':motion.REST_PATH,'glb_sha256':motion.REST_SHA})
    (package/'source.blend').write_bytes(b'BLENDER host fixture')
    m['source_sha256']=motion.digest((package/'source.blend').read_bytes())
    save(package,d,b,m)
    return package,d,b,m


def save(package,d,b,m):
    encoded=glb(d,bytes(b));(package/'candidate.glb').write_bytes(encoded);m['glb_sha256']=motion.digest(encoded);(package/'metadata.json').write_text(json.dumps(m))


class MotionRigTests(unittest.TestCase):
    def test_actual_skin_and_three_nonstatic_clips_bound(self):
        d,b,m=rig_fixture();r=motion.validate_rig(d,b,m)
        self.assertTrue(r['rest_bind_identity_verified']);self.assertEqual(set(r['clips']),set(motion.CLIPS));self.assertEqual(r['parents'],[None,'Root'])

    def test_constant_track_flag_comes_from_actual_source_keys(self):
        d,b,m=rig_fixture();animation=d['animations'][0]
        values=add_accessor(d,b,[(0.,0.,0.)]*3,'VEC3')
        animation['samplers'].append({'input':animation['samplers'][0]['input'],'output':values,'interpolation':'LINEAR'})
        animation['channels'].append({'target':{'node':1,'path':'translation'},'sampler':1})
        tracks=motion.validate_rig(d,b,m)['clips']['waddle']['tracks']
        self.assertEqual({track['joint']:track['constant'] for track in tracks},{'Body':False,'Root':True})
        offset=d['bufferViews'][d['accessors'][values]['bufferView']]['byteOffset']
        struct.pack_into('<f',b,offset+12,1.9073486328125e-6)
        tracks=motion.validate_rig(d,b,m)['clips']['waddle']['tracks']
        root_track=next(track for track in tracks if track['joint']=='Root')
        self.assertTrue(root_track['constant'])
        self.assertEqual(root_track['max_deviation'],1.9073486328125e-6)
        self.assertEqual(root_track['constant_tolerance'],3e-6)
        struct.pack_into('<f',b,offset+12,4e-6)
        tracks=motion.validate_rig(d,b,m)['clips']['waddle']['tracks']
        self.assertFalse(next(track for track in tracks if track['joint']=='Root')['constant'])

    def test_weights_and_inverse_binds_must_preserve_rest(self):
        for case in ['negative','unnormalized','joint_range','bind']:
            with self.subTest(case=case):
                d,b,m=rig_fixture();attrs=d['meshes'][0]['primitives'][0]['attributes'];index=d['skins'][0]['inverseBindMatrices'] if case=='bind' else attrs['JOINTS_0' if case=='joint_range' else 'WEIGHTS_0'];offset=d['bufferViews'][d['accessors'][index]['bufferView']]['byteOffset']
                if case=='joint_range':struct.pack_into('<H',b,offset,2)
                else:struct.pack_into('<f',b,offset,-.5 if case=='negative' else .3 if case=='unnormalized' else 2.)
                with self.assertRaises(ValueError):motion.validate_rig(d,b,m)

    def test_hierarchy_and_joint_only_animation_fail_closed(self):
        mutations=[lambda d,m:d['nodes'][2].update(children=[1]),lambda d,m:d['nodes'][0].update(translation=[.1,0,0]),lambda d,m:d['animations'][0]['channels'][0]['target'].update(node=0),lambda d,m:d['animations'][0]['channels'][0]['target'].update(path='weights'),lambda d,m:d['animations'][0]['samplers'][0].update(interpolation='STEP'),lambda d,m:m['rig'].update(joints=['Body','Root']),lambda d,m:d['animations'][0].update(name='idle'),lambda d,m:m['clips']['jump'].update(loop=True)]
        for i,mutate in enumerate(mutations):
            with self.subTest(case=i):
                d,b,m=rig_fixture();mutate(d,m)
                with self.assertRaises(ValueError):motion.validate_rig(d,b,m)

    def test_static_fake_clips_bad_times_and_loop_seams_rejected(self):
        for case in ['static','times','loop']:
            with self.subTest(case=case):
                d,b,m=rig_fixture();sampler=d['animations'][0]['samplers'][0];index=sampler['input' if case=='times' else 'output'];offset=d['bufferViews'][d['accessors'][index]['bufferView']]['byteOffset']
                struct.pack_into('<f',b,offset+(4 if case=='times' else 12 if case=='static' else 24),0. if case!='loop' else .02)
                with self.assertRaises(ValueError):motion.validate_rig(d,b,m)


class MotionPackageTests(unittest.TestCase):
    def mirrored_package(self, folder):
        p,d,b,m=package_fixture(folder)
        primitive=d['meshes'][0]['primitives'][0];attrs=primitive['attributes']
        streams={k:[list(row) for row in motion.accessor(d,b,v)] for k,v in attrs.items()}
        # Fixture identifies the immutable atlas charts including their cap
        # padding; production validator independently uses welded components.
        left={};right={}
        for part,y0,y1,count in [('foot',.5,.75,1922),('flipper',0,.499,482)]:
            left[part]=[i for i,uv in enumerate(streams['TEXCOORD_0']) if 648/1024-.005<=uv[0]<=816/1024+.005 and y0<=uv[1]<=y1]
            right[part]=[i for i,uv in enumerate(streams['TEXCOORD_0']) if 832/1024-.005<=uv[0]<=1000/1024+.005 and y0<=uv[1]<=y1]
            self.assertEqual(len(left[part]),len(right[part]));self.assertGreater(len(left[part]),count)
        for key in ('POSITION','NORMAL','TANGENT','TEXCOORD_0'):
            for part in left:
                for target,source in zip(left[part],right[part]):
                    streams[key][target]=streams[key][source].copy()
                    if key!='TEXCOORD_0':streams[key][target][0]*=-1
                    if key=='TANGENT':streams[key][target][3]*=-1
            attrs[key]=add_accessor(d,b,streams[key],{'POSITION':'VEC3','NORMAL':'VEC3','TANGENT':'VEC4','TEXCOORD_0':'VEC2'}[key])
        indices=[row[0] for row in motion.accessor(d,b,primitive['indices'])]
        faces=[indices[i:i+3] for i in range(0,len(indices),3)]
        for part in left:
            mapping=dict(zip(right[part],left[part]));left_set=set(left[part]);right_set=set(right[part])
            left_faces=[i for i,tri in enumerate(faces) if set(tri)<=left_set]
            right_faces=[tri for tri in faces if set(tri)<=right_set]
            self.assertEqual(len(left_faces),len(right_faces))
            for i,tri in zip(left_faces,right_faces):faces[i]=[mapping[tri[j]] for j in (0,2,1)]
        primitive['indices']=add_accessor(d,b,[(i,) for tri in faces for i in tri],'SCALAR',5123)
        s=importlib.util.spec_from_file_location('anatomy',ROOT/'tools/art/penguin_motion_anatomy.py')
        anatomy=importlib.util.module_from_spec(s);s.loader.exec_module(anatomy)
        m['anatomy_revision']=anatomy.revision_receipt();d['buffers'][0]['byteLength']=len(b)
        save(p,d,b,m)
        return p,d,b,m,left,right

    def test_exact_canonical_limb_clones_protect_all_other_parts(self):
        with tempfile.TemporaryDirectory() as temp:
            p,d,b,m,left,right=self.mirrored_package(Path(temp));result=motion.validate_package(p)
            self.assertEqual(result['anatomy_revision'],m['anatomy_revision'])
            baseline,raw=motion.shape.glb_data((ROOT/motion.REST_PATH).read_bytes())
            original=motion.shape.surface_components(baseline,raw)
            for name in original:
                if name not in ('foot_L','flipper_L'):self.assertEqual(result['rest_components'][name],original[name])
            for part in ('foot','flipper'):
                self.assertEqual(result['rest_components'][part+'_L'],motion.mirrored_right_component(baseline,raw,original,part+'_R'))

    def test_canonical_clone_rejects_wrong_frame_uv_placement_or_protected_part(self):
        for case in ('foot_handedness','foot_normal','foot_uv','foot_placement','foot_right',
                     'flipper_handedness','flipper_normal','flipper_uv','flipper_placement','flipper_right',
                     'missing','provenance','pairs','partial'):
            with self.subTest(case=case),tempfile.TemporaryDirectory() as temp:
                p,d,b,m,left,right=self.mirrored_package(Path(temp));attrs=d['meshes'][0]['primitives'][0]['attributes']
                if case=='missing':m.pop('anatomy_revision')
                elif case=='provenance':m['anatomy_revision']['recipe_sha256']='0'*64
                elif case=='pairs':m['anatomy_revision']['pairs'][1]['target_part']='short_tail_fan'
                elif case=='partial':
                    # Claiming the full revision cannot leave the old left flipper.
                    baseline,raw=motion.shape.glb_data((ROOT/motion.REST_PATH).read_bytes())
                    old_attrs=baseline['meshes'][0]['primitives'][0]['attributes']
                    for key in ('POSITION','NORMAL','TANGENT','TEXCOORD_0'):
                        rows=[list(row) for row in motion.accessor(d,b,attrs[key])]
                        old_rows=motion.accessor(baseline,raw,old_attrs[key])
                        for i in left['flipper']:rows[i]=list(old_rows[i])
                        attrs[key]=add_accessor(d,b,rows,{'POSITION':'VEC3','NORMAL':'VEC3','TANGENT':'VEC4','TEXCOORD_0':'VEC2'}[key])
                    d['buffers'][0]['byteLength']=len(b)
                else:
                    part,change=case.split('_')
                    key={'handedness':'TANGENT','normal':'NORMAL','uv':'TEXCOORD_0','placement':'POSITION','right':'POSITION'}[change]
                    index=right[part][10] if change=='right' else left[part][10];column=3 if change=='handedness' else 0
                    item=d['accessors'][attrs[key]];view=d['bufferViews'][item['bufferView']]
                    width={'TANGENT':4,'NORMAL':3,'TEXCOORD_0':2,'POSITION':3}[key]
                    offset=view.get('byteOffset',0)+index*width*4+column*4
                    value=struct.unpack_from('<f',b,offset)[0]
                    struct.pack_into('<f',b,offset,-value if change=='handedness' else value+.001)
                save(p,d,b,m)
                with self.assertRaises(ValueError):motion.validate_package(p)

    def revised_package(self, folder):
        p,d,b,m=package_fixture(folder)
        m['material_revision']=motion.surface_recipe.apply_document(d,b)
        encoded,index,space,_=motion.map_bytes(d,b)['base_color']
        m['surface_maps']['base_color'].update(image_index=index,sha256=motion.digest(encoded))
        save(p,d,b,m)
        return p,d,b,m

    def test_exact_material_revision_binds_same_rest_and_source_intent(self):
        with tempfile.TemporaryDirectory() as temp:
            p,d,b,m=self.revised_package(Path(temp));result=motion.validate_package(p)
            self.assertEqual(result['material_revision'],m['material_revision'])
            self.assertEqual(result['materials'][0]['specular'],.15)
            self.assertEqual(result['surface_maps']['normal']['sha256'],m['surface_maps']['normal']['sha256'])
            baseline,binary=motion.shape.glb_data((ROOT/motion.REST_PATH).read_bytes())
            self.assertNotEqual(motion.map_bytes(d,b)['base_color'][0],motion.map_bytes(baseline,binary)['base_color'][0])
            for name in ('normal','metallic_roughness'):
                self.assertEqual(motion.map_bytes(d,b)[name][0],motion.map_bytes(baseline,binary)[name][0])

    def test_material_revision_rejects_forgery_and_unapproved_maps(self):
        for case in ('recipe','specular','removed','pixels','extra_setting','normal'):
            with self.subTest(case=case),tempfile.TemporaryDirectory() as temp:
                p,d,b,m=self.revised_package(Path(temp))
                if case=='recipe':
                    m['material_revision']['recipe_sha256']='0'*64
                    d['materials'][0]['extras']['ww_motion_surface']=m['material_revision']
                elif case=='specular':
                    m['material_revision']['specular']=0
                    d['materials'][0]['extras']['ww_motion_surface']=m['material_revision']
                elif case=='removed':m.pop('material_revision')
                elif case=='extra_setting':d['materials'][0]['normalTexture']['scale']=2
                else:
                    name='base_color' if case=='pixels' else 'normal'
                    image=d['images'][motion.map_bytes(d,b)[name][1]];view=d['bufferViews'][image['bufferView']]
                    b[view['byteOffset']+20]^=1
                save(p,d,b,m)
                with self.assertRaises(ValueError):motion.validate_package(p)

    def test_surface_recipe_preserves_protected_pixels_and_mean(self):
        d,b=motion.shape.glb_data((ROOT/motion.REST_PATH).read_bytes())
        original=motion.map_bytes(d,b)['base_color'][0]
        encoded,receipt=motion.surface_recipe.derive(original)
        w,h,before=motion.shape.png_rgba(original);_,_,after=motion.shape.png_rgba(encoded)
        allowed=bytearray(w*h)
        for x0,y0,x1,y1,_ in motion.surface_recipe.REGIONS:
            for y in range(y0,y1):
                for x in range(x0,x1):allowed[(h-1-y)*w+x]=1
        changed=0
        for i in range(w*h):
            rgb=before[i*4:i*4+3]
            protected=not allowed[i] or max(rgb)>=112 or min(rgb)/max(max(rgb),1)<=.64
            if protected:self.assertEqual(before[i*4:i*4+4],after[i*4:i*4+4])
            else:changed+=before[i*4:i*4+3]!=after[i*4:i*4+3]
        self.assertGreater(changed,10000)
        for region in receipt['regions']:
            self.assertLess(abs(region['weighted_linear_mean_ratio']-1),.01)
        with self.assertRaises(ValueError):motion.surface_recipe.derive(b'not accepted artwork')

    def test_real_accepted_rest_and_maps_survive_added_skin(self):
        with tempfile.TemporaryDirectory() as temp:
            p,d,b,m=package_fixture(Path(temp));r=motion.validate_package(p)
            self.assertEqual(r['surface_count'],1);self.assertEqual(set(r['rest_components']),set(motion.shape.PART_RANGES));self.assertEqual(r['surface_maps']['normal']['sha256'],m['surface_maps']['normal']['sha256'])
            with self.assertRaises(ValueError):motion.shape.validate_package(p)

    def test_rest_position_and_texture_settings_change_rejected(self):
        for case in ['position','normal_scale','map']:
            with self.subTest(case=case),tempfile.TemporaryDirectory() as temp:
                p,d,b,m=package_fixture(Path(temp))
                if case=='position':
                    a=d['meshes'][0]['primitives'][0]['attributes']['POSITION'];offset=d['bufferViews'][d['accessors'][a]['bufferView']]['byteOffset'];x=struct.unpack_from('<f',b,offset)[0];struct.pack_into('<f',b,offset,x+.01)
                elif case=='normal_scale':d['materials'][0]['normalTexture']['scale']=.1
                else:
                    view=d['bufferViews'][d['images'][0]['bufferView']];b[view['byteOffset']+20]^=1
                save(p,d,b,m)
                with self.assertRaises(ValueError):motion.validate_package(p)

    def test_source_or_reference_hash_cannot_drift(self):
        with tempfile.TemporaryDirectory() as temp:
            p,d,b,m=package_fixture(Path(temp));m['rest_reference']['glb_sha256']='0'*64;save(p,d,b,m)
            with self.assertRaisesRegex(ValueError,'reference'):motion.validate_package(p)
            m['rest_reference']['glb_sha256']=motion.REST_SHA;save(p,d,b,m);(p/'source.blend').write_bytes(b'changed')
            with self.assertRaisesRegex(ValueError,'hash'):motion.validate_package(p)

    def test_install_preserves_sources_and_binds_all_prepared_inputs(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);source,project=project_fixture(root);p,d,b,m=package_fixture(root)
            for name in ['motion_candidate_browser.gd','motion_candidate_post_import.gd','surface_candidate_post_import.gd']:write(source/'tools/qa'/name,'extends Node\n')
            before=inventory(source);original=inventory(p);project_before=inventory(project)
            r=motion.install(source,project,p)
            self.assertEqual(before,inventory(source));self.assertEqual(original,inventory(p));self.assertFalse(r['gallery_eligible'])
            for name,data in project_before.items():
                if name not in ['project.godot','export_presets.cfg']:self.assertEqual((project/name).read_bytes(),data)
            self.assertIn('hero_motion_enabled=true',(project/'project.godot').read_text());self.assertNotIn('hero_shape_enabled',(project/'project.godot').read_text())
            self.assertEqual(r['binding']['importer_sha256'],motion.digest((project/'qa_motion/candidate.glb.import').read_bytes()))
            self.assertIn('animation/import=true',motion.IMPORTER);self.assertIn('animation/remove_immutable_tracks=false',motion.IMPORTER)
            node_settings=json.loads(motion.IMPORTER.split('_subresources=',1)[1])
            self.assertEqual(node_settings,{'nodes':{'PATH:AnimationPlayer':{'optimizer/enabled':False,'compression/enabled':False}}})
            self.assertEqual(r['binding']['animation_import_policy'],node_settings)
            after=inventory(project)
            with self.assertRaises(ValueError):motion.install(source,project,p)
            self.assertEqual(after,inventory(project))

    def test_preflight_failures_do_not_partially_install(self):
        with tempfile.TemporaryDirectory() as temp:
            root=Path(temp);source,project=project_fixture(root);p,d,b,m=package_fixture(root)
            # Invalid include refuses before reading any missing helper or mutating files.
            (project/'export_presets.cfg').write_text('malformed');before=inventory(project)
            with self.assertRaisesRegex(ValueError,'filter'):motion.install(source,project,p)
            self.assertEqual(before,inventory(project))
            with self.assertRaisesRegex(ValueError,'separate'):motion.install(source,source,p)

    def test_chrome_candidate_modes_are_mutually_exclusive_before_mutation(self):
        from tests.test_chrome_reference_export import qa
        with tempfile.TemporaryDirectory() as temp:
            out=Path(temp)/'out'
            with self.assertRaisesRegex(ValueError,'one isolated'):qa.prepare(out,hero_shape_package=Path('missing'),hero_motion_package=Path('missing'))
            self.assertFalse(out.exists())
            with self.assertRaisesRegex(ValueError,'one isolated'):qa.prepare(out,hero_candidate_runtime=True,hero_motion_package=Path('missing'))
            self.assertFalse(out.exists())

if __name__=='__main__':unittest.main()
