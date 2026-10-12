#!/usr/bin/env python3
"""Prepare isolated matched DAY browser candidates. Never edits production manifests.
Uses the coordinator's already-frozen QA snapshot and corrected token bridge.
"""
from pathlib import Path
import argparse,datetime as dt,hashlib,importlib.util,json,re,shutil,subprocess,uuid
ROOT=Path(__file__).resolve().parents[2]
def load_tool(name):
 spec=importlib.util.spec_from_file_location(name,ROOT/'tools/qa'/f'{name}.py')
 obj=importlib.util.module_from_spec(spec);spec.loader.exec_module(obj);return obj
qa=load_tool('chrome_reference_export')
def prepare(base,out,variant):
 assert variant in ['candidate','baseline']
 assert not out.exists(), 'Use fresh output; preserve earlier exports'
 record=json.loads((ROOT/'qa_shots/tests/runner-day-scoped-candidate-20261008/candidate.json').read_text())
 candidate=Path(record['candidate_path'])
 out.mkdir(parents=True);project=out/'project'
 subprocess.run(['cp','-cR',str(base/'project'),str(project)],check=True)
 changed=[]
 if variant=='candidate':
  for rel in record['base_production_hashes']:
   if rel=='export_presets.cfg':continue
   if rel!='art_src/runner/source_manifest.json':
    assert qa.sha(project/rel)==record['base_production_hashes'][rel], f'Frozen base drift: {rel}'
   dest=project/rel;dest.parent.mkdir(parents=True,exist_ok=True);shutil.copy2(candidate/rel,dest);changed.append(rel)
  preset=(project/'export_presets.cfg').read_text();assert preset.count('assets/art/runner/day/*')==1
  preset=preset.replace('assets/art/runner/day/*',','.join(record['excluded_day_paths']))
  (project/'export_presets.cfg').write_text(preset);changed.append('export_presets.cfg')
  for aid in record['candidate_runtime_ids']:
   entry=next(a for a in json.loads((candidate/'assets/art/art_manifest.json').read_text())['assets'] if a['id']==aid)
   assert qa.sha(project/entry['path'].removeprefix('res://'))==entry['sha256']
  (project/'art_src/.gdignore').touch()
 token=uuid.uuid4().hex;identity='waddle-day-'+variant+'-'+uuid.uuid4().hex
 config=(project/'project.godot').read_text()
 config=re.sub(r'^config/name="[^"]*"$',f'config/name="{identity}"',config,flags=re.M)
 config=re.sub(r'^config/custom_user_dir_name="[^"]*"$',f'config/custom_user_dir_name="{identity}"',config,flags=re.M)
 config=re.sub(r'^route_token="[^"]*"$',f'route_token="{token}"',config,flags=re.M)
 config=config.replace('ChromeReferenceQA="*res://_qa_local/chrome_reference_bridge.gd"','ChromeReferenceQA="*res://_qa_local/runner_day_course_bridge.gd"')
 config=config.replace('[application]\n','[application]\nqa/release_runner_art_only=true\n',1)
 (project/'project.godot').write_text(config)
 local=project/'_qa_local';local.mkdir(exist_ok=True)
 for name in ['chrome_reference_bridge.gd','chrome_reference_bridge.js','runner_day_course_bridge.gd','runner_day_course_bridge.js','runner_day_course_game.gd','runner_day_course_game.tscn']:
  source_name=name+'.in' if name in ['runner_day_course_bridge.gd','runner_day_course_game.gd','runner_day_course_game.tscn'] else name
  shutil.copy2(ROOT/'tools/qa'/source_name,local/name)
 (project/'tests').mkdir(exist_ok=True)
 for suffix in ['gd','tscn']:shutil.copy2(ROOT/f'tests/runner_day_browser_probe_test.{suffix}',project/f'tests/runner_day_browser_probe_test.{suffix}')
 shutil.copy2(base/'production-head.html',out/'production-head.html')
 shutil.copy2(base/'source-export-presets.cfg',out/'source-export-presets.cfg')
 (out/'web').mkdir()
 files=qa.inventory(project)
 baseline=json.loads((base/'manifest.json').read_text())
 manifest={'prepared_utc':qa.now(),'variant':variant,'base_frozen_snapshot':str(base),'base_source_fingerprint':baseline['source_fingerprint'],
  'source_fingerprint':hashlib.sha256(json.dumps(files,sort_keys=True).encode()).hexdigest(),'source_sha256':files,'export_input_sha256':files,
  'source_preset_sha256':qa.sha(out/'source-export-presets.cfg'),'production_head_sha256':qa.sha(out/'production-head.html'),
  'qa_token':token,'user_identity':identity,'scoped_production_differences':changed,
  'candidate_only':True,'main_tree_integrated':False,'production_audio':'Default WebAudio; root must preserve Chrome site mute',
  'production_exclusions_and_script_mode_preserved':variant=='baseline','script_mode_and_other_exclusions_preserved':True,
  'synthetic':['Fixed generation seed20260818 before real RunnerGame ready','Real RunnerPlayer autopilot verbs; no physical input claim','Separate continuous mode and paused stills mode, never mix timing evidence','No invulnerability, teleport, speed or delta changes, quality/governor/canvas override, or power grants'],
  'bounds':{'samples':12000,'load_seconds':60,'continuous_seconds':90,'stills_total_seconds':240,'stop_poll_seconds':3},
  'import_cache':'APFS clone of verified v3 imports; refresh editor registry. Not a cold import.',
  'pending':['Actual Chrome pixel review','Continuous performance comparison','Main catalog integration approval']}
 qa.write(out/'manifest.json',manifest)
 print(json.dumps({'prepared':str(out),'variant':variant,'token':token,'fingerprint':manifest['source_fingerprint']}))
def build(out):
 qa.build(out,qa.GODOT)
 manifest=json.loads((out/'manifest.json').read_text());report=json.loads((out/'build.json').read_text())
 report['production_exclusions_and_script_mode_preserved']=manifest['variant']=='baseline'
 report['script_mode_and_other_exclusions_preserved']=True
 report['scoped_production_differences']=manifest['scoped_production_differences']
 report['candidate_only']=True;report['main_tree_integrated']=False
 qa.write(out/'build.json',report)
if __name__=='__main__':
 p=argparse.ArgumentParser(description=__doc__);p.add_argument('mode',choices=['prepare','build','serve']);p.add_argument('out',type=Path)
 p.add_argument('--base',type=Path,default=ROOT/'qa_shots/tests/chrome-reference-final-20261008-v3');p.add_argument('--variant',choices=['candidate','baseline'],default='candidate');p.add_argument('--port',type=int,default=54618)
 a=p.parse_args();out=a.out.resolve()
 if a.mode=='prepare':prepare(a.base.resolve(),out,a.variant)
 elif a.mode=='build':build(out)
 else:qa.serve(out,a.port)
