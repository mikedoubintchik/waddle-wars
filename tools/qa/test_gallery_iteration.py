"""Real filesystem/image regression tests; no Godot, browser or remote services."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest
from PIL import Image

def dimensions(path):
    with Image.open(path) as image:return list(image.size)

SPEC=importlib.util.spec_from_file_location('gallery_iteration',Path(__file__).with_name('gallery_iteration.py'))
g=importlib.util.module_from_spec(SPEC);SPEC.loader.exec_module(g)

class IterationTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup)
        self.home=Path(self.temp.name);self.root=self.home/'repo';self.root.mkdir();self.base=self.home/'base';self.base.mkdir();self.d=self.home/'iteration'
        for directory in ['scripts','assets','data','scenes']:(self.root/directory).mkdir()
        (self.root/'scripts/world.gd').write_text('old');(self.root/'scripts/shop.gd').write_text('old')
        (self.root/'project.godot').write_text('project');(self.root/'export_presets.cfg').write_text('preset')
        pages=[{'id':'world','title':'World','group':'run'},{'id':'shop','title':'Shop','group':'menu'}];rows=[]
        for page in pages:
            for o in g.ORIENTATIONS:
                p=self.base/f'{o}-{page["id"]}.jpg';Image.new('RGB',(80,45) if o=='desktop' else (45,80),'blue').save(p)
                rows.append({'id':page['id'],'title':page['title'],'orientation':o,'actual':p.name,'reference':p.name,'capture_sha256':g.sha(p),'reference_sha256':g.sha(p),'dimensions':dimensions(p),'source_iteration':1,'current_capture_status':'accepted','availability':'accepted','capture_provenance':{'captured_at':'2026-01-01T00:00:00Z','build_sha256':'a'*64,'accepted':True}})
        g.write(self.base/'manifest.json',{'pages':pages,'entries':rows,'prior_collections':[]})
        self.dep=self.home/'dependencies.json';g.write(self.dep,{'rules':[{'paths':['scripts/world*'],'routes':['world'],'reason':'world'},{'paths':['scripts/shop*'],'routes':['shop'],'reason':'shop'}]})
        g.start(self.d,self.base/'manifest.json','test',self.root,dependencies=self.dep)
    def changed(self):
        (self.root/'scripts/world.gd').write_text('new');g.plan(self.d)
    def export(self):
        out=self.home/'export';out.mkdir(exist_ok=True);(out/'web').mkdir(exist_ok=True);(out/'web/index.pck').write_bytes(b'actual pack')
        files=g.snapshot(self.root,g.EXPORT_SCOPE)['files'];preset=files.pop('export_presets.cfg')
        manifest={'source_sha256':files,'source_preset_sha256':preset,'source_fingerprint':g.digest(files)}
        g.write(out/'manifest.json',manifest);g.write(out/'build.json',{'source_fingerprint':manifest['source_fingerprint'],'files':{'index.pck':{'sha256':g.sha(out/'web/index.pck')}}})
        return out
    def captures(self,out):
        m=g.read(out/'manifest.json');pack=g.sha(out/'web/index.pck')
        for o in g.ORIENTATIONS:
            p=self.d/'originals'/o/'world.jpg';p.parent.mkdir(parents=True,exist_ok=True);Image.new('RGB',(100,60) if o=='desktop' else (60,100),'red').save(p)
            state={'route':'world','status':'ready','error':'','capture_utc':'2026-02-01T00:00:00Z','canvas_backing':dimensions(p),'touch_points':5 if o=='mobile' else 0,
                   'source_url':'http://localhost/?qa_token=private&qa_route=world','build':{'source_fingerprint':m['source_fingerprint'],'pack_sha256':pack,'runtime_audio_driver':'Dummy','qa_auth_isolation':'offline_visual_qa'}}
            g.write(p.with_suffix('.json'),state)
        g.review(self.d,out)
        a=g.read(self.d/'review-draft.json');a['accepted']=True
        for row in a['captures']:row.update(accepted=True,reviewed_by='test coordinator',reviewed_at='2026-02-02T00:00:00Z')
        g.write(self.d/'accepted.json',a);return self.d/'accepted.json'
    def test_snapshot_untracked_added_deleted_and_unknown_fallback(self):
        (self.root/'scripts/untracked_new.gd').write_text('new');(self.root/'scripts/shop.gd').unlink()
        result=g.plan(self.d);p=g.get_plan(self.d)
        self.assertEqual(result['views'],4);self.assertEqual(p['unknown_paths'],['scripts/untracked_new.gd'])
        self.assertEqual({x['kind'] for x in p['changes']},{'added','deleted'})
    def test_clothing_dependency_includes_run_and_equipment_consumers(self):
        dependencies=g.read(Path(__file__).with_name('gallery_dependencies.json'))
        pages=[{'id':'runner_hud','group':'run'},{'id':'equipment_hat_beanie','group':'equipment'},
               {'id':'customize','group':'menu'},{'id':'customize_trails','group':'menu'},
               {'id':'customize_insufficient','group':'menu'},{'id':'credits','group':'menu'}]
        impacted,unknown=g.impacts([{'path':'scripts/characters/penguin_apparel.gd','kind':'added'}],pages,dependencies)
        self.assertEqual(set(impacted),{'runner_hud','equipment_hat_beanie','customize','customize_trails','customize_insufficient'})
        self.assertEqual(unknown,[])

    def test_no_change_requests_no_capture_and_preserves_originals_dates(self):
        p=g.get_plan(self.d);self.assertEqual(p['requests'],[])
        g.build(self.d);m=g.read(self.d/'gallery/manifest.json')
        for row,prior in zip(m['entries'],g.read(self.base/'manifest.json')['entries']):
            self.assertEqual((self.d/'gallery'/row['actual']).read_bytes(),(self.base/prior['actual']).read_bytes())
            self.assertEqual(row['capture_provenance'],prior['capture_provenance'])
        delivery=g.delivery(self.d);self.assertEqual(delivery['new_files'],3)
    def test_unrelated_rows_exact_while_affected_remain_pending(self):
        self.changed();g.build(self.d);m=g.read(self.d/'gallery/manifest.json')
        self.assertEqual(m['pending_current_views'],2)
        for row in m['entries']:
            self.assertEqual(row['current_capture_status'],'pending' if row['id']=='world' else 'accepted')
            self.assertEqual(row['capture_provenance']['captured_at'],'2026-01-01T00:00:00Z')
        with self.assertRaisesRegex(ValueError,'still pending'):g.delivery(self.d)
    def test_source_edit_after_plan_blocks_build_and_review(self):
        self.changed();out=self.export();(self.root/'scripts/shop.gd').write_text('later')
        with self.assertRaisesRegex(ValueError,'Source changed|source changed'):g.build(self.d)
        with self.assertRaisesRegex(ValueError,'source changed'):g.review(self.d,out)
    def test_draft_never_promotes(self):
        self.changed();out=self.export();self.captures(out)
        with self.assertRaisesRegex(ValueError,'acceptance missing'):g.build(self.d,self.d/'review-draft.json')
    def test_partial_acceptance_keeps_missing_view_pending(self):
        self.changed();out=self.export();a=self.captures(out);v=g.read(a);v['captures']=v['captures'][:1];g.write(a,v)
        result=g.build(self.d,a);self.assertEqual(result['fresh_views'],1);self.assertEqual(result['pending_views'],1)
    def test_failed_capture_stays_pending(self):
        self.changed();out=self.export();self.captures(out)
        side=self.d/'originals/mobile/world.json';s=g.read(side);s['error']='renderer stopped';g.write(side,s)
        g.review(self.d,out);draft=g.read(self.d/'review-draft.json');self.assertTrue(draft['captures'][1]['validation_errors'])
        result=g.build(self.d);self.assertEqual(result['pending_views'],2)
    def test_success_and_only_changed_delivery(self):
        self.changed();out=self.export();a=self.captures(out);result=g.build(self.d,a)
        self.assertEqual((result['fresh_views'],result['pending_views']),(2,0));d=g.delivery(self.d)
        self.assertEqual(d['new_files'],13) #2 originals+4 comparisons+2 public sidecars+3 docs+2 changed sheets
        m=g.read(self.d/'gallery/manifest.json');self.assertNotIn('qa_token',json.dumps(m))
        sidecars=list((self.d/'gallery/provenance').glob('*.json'));self.assertTrue(sidecars)
        self.assertTrue(all('qa_token' not in p.read_text() for p in sidecars))
        self.assertEqual({r['input_mode'] for r in m['entries'] if r['id']=='world'},{'touch_emulation','desktop_input'})
    def test_corruptions_rejected_at_admission(self):
        self.changed();out=self.export();a=self.captures(out);original=g.read(a)
        mutations=[('sha256','bad'),('sidecar_sha256','bad'),('build_sha256','bad'),('source_fingerprint','bad'),('captured_at','2026-01-01T00:00:00Z'),('dimensions',[12,12]),('input_mode','physical_phone'),('validation_errors',['ignored']),('accepted',False)]
        for field,value in mutations:
            with self.subTest(field=field):
                v=copy.deepcopy(original);v['captures'][0][field]=value;g.write(a,v)
                with self.assertRaises(ValueError):g.build(self.d,a)
    def test_sidecar_state_independently_checked_even_if_rehashed(self):
        self.changed();out=self.export();a=self.captures(out);original=g.read(a);side=self.d/'originals/desktop/world.json';state=g.read(side)
        for field,value in [('error','bad'),('route','shop'),('status','loading'),('canvas_backing',[12,12]),('capture_utc','other')]:
            with self.subTest(field=field):
                s=copy.deepcopy(state);s[field]=value;g.write(side,s)
                v=copy.deepcopy(original);v['captures'][0]['sidecar_sha256']=g.sha(side);g.write(a,v)
                with self.assertRaises(ValueError):g.build(self.d,a)
    def test_duplicate_and_obsolete_plan_rejected(self):
        self.changed();out=self.export();a=self.captures(out);v=g.read(a);v['captures'].append(v['captures'][0]);g.write(a,v)
        with self.assertRaisesRegex(ValueError,'Duplicate'):g.build(self.d,a)
        v['captures'].pop();v['plan_id']='obsolete';g.write(a,v)
        with self.assertRaisesRegex(ValueError,'obsolete plan'):g.build(self.d,a)
    def test_delivery_revalidates_current_and_accepted_bytes(self):
        self.changed();out=self.export();a=self.captures(out);g.build(self.d,a)
        v=g.read(a);v['source_fingerprint']='bad';g.write(a,v)
        with self.assertRaisesRegex(ValueError,'input changed'):g.delivery(self.d)
    def test_export_different_source_and_actual_pack_rejected(self):
        self.changed();out=self.export();a=self.captures(out)
        (out/'web/index.pck').write_bytes(b'new pack')
        with self.assertRaisesRegex(ValueError,'PCK hash'):g.build(self.d,a)
    def test_candidate_export_cannot_be_promoted_as_shipping(self):
        self.changed();out=self.export();a=self.captures(out)
        manifest=g.read(out/'manifest.json');manifest['hero_candidate']={'gallery_eligible':False};g.write(out/'manifest.json',manifest)
        with self.assertRaisesRegex(ValueError,'Candidate-only export'):g.review(self.d,out)
        with self.assertRaisesRegex(ValueError,'Candidate-only export'):g.verify_export(out)
    def test_unrigged_shape_export_cannot_be_promoted_as_shipping(self):
        self.changed();out=self.export()
        manifest=g.read(out/'manifest.json')
        for candidate in ['hero_shape', 'hero_motion', 'runner_color_review']:
            current={**manifest,candidate:{'gallery_eligible':False}};g.write(out/'manifest.json',current)
            with self.assertRaisesRegex(ValueError,'Candidate-only export'):g.review(self.d,out)
            with self.assertRaisesRegex(ValueError,'Candidate-only export'):g.verify_export(out)
    def test_repeat_plan_retains_first_receipt_and_previous_versions(self):
        before=(self.d/'capture-request.json').read_bytes();g.plan(self.d)
        self.assertEqual(before,(self.d/'capture-request.json').read_bytes())
        self.changed();self.assertEqual(len(list((self.d/'plans').glob('*/plan.json'))),2)
    def test_base_manifest_mutation_rejected(self):
        (self.base/'manifest.json').write_text('{}')
        with self.assertRaisesRegex(ValueError,'Frozen'):g.plan(self.d)
    def test_historical_adoption_keeps_date_and_pending_for_changed_source(self):
        out=self.export();self.changed()
        mapping=self.home/'map.json'
        # Capture current fake pixels with the explicitly older build identity.
        for o in g.ORIENTATIONS:
            image=self.home/f'old-{o}.jpg';size=(100,60) if o=='desktop' else (60,100);Image.new('RGB',size,'green').save(image)
            g.write(image.with_suffix('.json'),{'route':'world','status':'ready','error':'','capture_utc':'2026-01-15T00:00:00Z','canvas_backing':list(size),'touch_points':0,
                'build':{'source_fingerprint':g.read(out/'manifest.json')['source_fingerprint'],'pack_sha256':g.sha(out/'web/index.pck'),'runtime_audio_driver':'Dummy','qa_auth_isolation':'offline_visual_qa'}})
        g.write(mapping,{'captures':[{'id':'world','orientation':o,'path':str(self.home/f'old-{o}.jpg'),'sidecar':str(self.home/f'old-{o}.json'),'source_iteration':'old unpublished pass'} for o in g.ORIENTATIONS]})
        g.review(self.d,out,historical_map=mapping)
        a=g.read(self.d/'review-draft.json');a['accepted']=True
        for row in a['captures']:row.update(accepted=True,reviewed_by='coordinator',reviewed_at='2026-02-02T00:00:00Z')
        approval=self.d/'historical.json';g.write(approval,a)
        result=g.build(self.d,historical=[approval]);self.assertEqual(result['fresh_views'],0);self.assertEqual(result['pending_views'],2)
        rows=g.read(self.d/'gallery/manifest.json')['entries'];self.assertEqual(rows[0]['capture_provenance']['captured_at'],'2026-01-15T00:00:00Z')
    def test_next_iteration_auto_detects_between_iteration_source_changes(self):
        g.build(self.d);(self.root/'scripts/shop.gd').write_text('between iterations')
        next_dir=self.home/'next';result=g.start(next_dir,self.d/'gallery/manifest.json','next',self.root,dependencies=self.dep)
        self.assertEqual(result['carried_files'],1);self.assertEqual(g.get_plan(next_dir)['affected_routes'],['shop'])
    def test_rejected_approval_does_not_mutate_existing_gallery(self):
        self.changed();out=self.export();a=self.captures(out);g.build(self.d,a)
        original=(self.d/'gallery/captures/desktop-world.jpg').read_bytes();v=g.read(a);v['captures'][0]['sha256']='bad';g.write(a,v)
        with self.assertRaises(ValueError):g.build(self.d,a)
        self.assertEqual((self.d/'gallery/captures/desktop-world.jpg').read_bytes(),original)
    def test_malformed_sidecar_becomes_pending_review_error(self):
        self.changed();out=self.export();self.captures(out)
        g.write(self.d/'originals/mobile/world.json',[]);g.review(self.d,out)
        rows=g.read(self.d/'review-draft.json')['captures'];self.assertIn('Malformed sidecar',rows[1]['validation_errors'][0])
    def test_incomplete_base_matrix_rejected(self):
        value=g.read(self.base/'manifest.json');value['entries'].pop();g.write(self.base/'manifest.json',value)
        other=self.home/'incomplete'
        with self.assertRaisesRegex(ValueError,'exactly one row'):g.start(other,self.base/'manifest.json','next',self.root,dependencies=self.dep)
    def test_nonpack_runtime_export_mutation_rejected(self):
        out=self.export();script=out/'web/index.js';script.write_text('original')
        b=g.read(out/'build.json');b['files']['index.js']={'sha256':g.sha(script)};g.write(out/'build.json',b)
        script.write_text('mutated')
        with self.assertRaisesRegex(ValueError,'file hash mismatch: index.js'):g.verify_export(out)
    def test_retained_fresh_flag_is_cleared(self):
        v=g.read(self.base/'manifest.json');v['entries'][0]['refreshed_this_iteration']=True;g.write(self.base/'manifest.json',v)
        other=self.home/'fresh';g.start(other,self.base/'manifest.json','next',self.root,dependencies=self.dep);g.build(other)
        m=g.read(other/'gallery/manifest.json');self.assertEqual(m['fresh_views'],0);self.assertFalse(any(r['refreshed_this_iteration'] for r in m['entries']))
    def test_malformed_scalar_metadata_is_row_error_not_review_crash(self):
        self.changed();out=self.export();self.captures(out);side=self.d/'originals/mobile/world.json';original=g.read(side)
        for key,value in [('capture_utc',None),('capture_utc','nonsense'),('capture_utc','2026-02-01T00:00:00'),('touch_points',None),('touch_points',-1),('touch_points',True),('canvas_backing',[0,80]),('canvas_backing',[80,True]),('canvas_backing','80x40')]:
            with self.subTest(key=key,value=value):
                state=copy.deepcopy(original);state[key]=value;g.write(side,state);g.review(self.d,out)
                self.assertTrue(g.read(self.d/'review-draft.json')['captures'][1]['validation_errors'])

if __name__=='__main__':unittest.main()
