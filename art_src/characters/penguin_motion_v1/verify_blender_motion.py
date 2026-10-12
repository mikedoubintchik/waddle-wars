from pathlib import Path
import bpy, json,struct,hashlib
import numpy as np
from mathutils import Matrix,Quaternion,Vector
P=Path(__file__).resolve().parent
raw=(P/'candidate.glb').read_bytes();n=struct.unpack_from('<I',raw,12)[0];d=json.loads(raw[20:20+n]);off=20+n+8;binary=raw[off:]
def accessor(i):
 a=d['accessors'][i];v=d['bufferViews'][a['bufferView']];w={'SCALAR':1,'VEC3':3,'VEC4':4}[a['type']];return np.ndarray((a['count'],w),dtype='<f4',buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',w*4),4)).copy()
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
bpy.ops.wm.open_mainfile(filepath=str(P/'source.blend'));rig=bpy.data.objects['PenguinMotionRig'];names={i:d['nodes'][i]['name'] for i in d['skins'][0]['joints']};parent={}
for i,node in enumerate(d['nodes']):
 for c in node.get('children',[]):parent[c]=i
reports={}
for animation in d['animations']:
 clip=animation['name'];action=bpy.data.actions[clip];rig.animation_data.action=action
 if action.slots:rig.animation_data.action_slot=action.slots[0]
 count=len(accessor(animation['samplers'][0]['input']));errors=[]
 for f in sorted(set([0,1,count//4,count//2,3*count//4,count-1])):
  bpy.context.scene.frame_set(f);bpy.context.view_layer.update();components={}
  for channel in animation['channels']:
   sampler=animation['samplers'][channel['sampler']];components.setdefault(channel['target']['node'],{})[channel['target']['path']]=accessor(sampler['output'])[f]
  globals_={}
  def global_node(i):
   if i in globals_:return globals_[i]
   node=components.get(i,d['nodes'][i]);loc=Vector(node.get('translation',[0,0,0]));q=node.get('rotation',[0,0,0,1]);rot=Quaternion((q[3],q[0],q[1],q[2]));scale=node.get('scale',[1,1,1]);local=Matrix.LocRotScale(loc,rot,Vector(scale));globals_[i]=(global_node(parent[i])@local if i in parent else local);return globals_[i]
  for i,name in names.items():
   expect=C.inverted()@global_node(i)@C;observed=rig.pose.bones[name].matrix;error=float(np.max(abs(np.array(observed)-np.array(expect))));errors.append({'frame':f,'bone':name,'matrix_max_error':error})
 maximum=max(x['matrix_max_error'] for x in errors);reports[clip]={'max_matrix_error':maximum,'worst':max(errors,key=lambda x:x['matrix_max_error']),'samples':len(errors)}
print(json.dumps(reports));(P/'blender-action-verification.json').write_text(json.dumps({'candidate_sha256':hashlib.sha256(raw).hexdigest(),'source_sha256':hashlib.sha256((P/'source.blend').read_bytes()).hexdigest(),'clips':reports,'passed':all(x['max_matrix_error']<3e-5 for x in reports.values())},indent=2)+'\n')
assert all(x['max_matrix_error']<3e-5 for x in reports.values()),reports
