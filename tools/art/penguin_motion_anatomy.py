"""Canonical right foot and flipper reflected onto their left counterparts.

Only the new motion candidate changes. Accepted source packages stay immutable.
The Blender source and literal GLB streams use the same reflection, winding and
right-foot UVs; no hidden shear, pose-specific scaling or corrective deformation.
"""
from pathlib import Path
import hashlib
ROOT=Path(__file__).resolve().parents[2]
BASELINE_SHA='c895c19f310f71d8667cc871b1947d9a5d635653c99ee5acca4035fcb063c62c'
PAIRS=(('foot_R','foot_L'),('flipper_R','flipper_L'))

def revision_receipt():
 return {'id':'mirrored-right-limbs-v1','baseline_glb_sha256':BASELINE_SHA,'recipe_path':'tools/art/penguin_motion_anatomy.py','recipe_sha256':hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),'reflection':[-1,1,1],'translation':[0,0,0],'pairs':[{'source_part':source,'target_part':target} for source,target in PAIRS],'uv_policy':'reuse-source-part','scope':'Left foot and flipper are exact mirrored right instances; reversed winding, reflected normals/tangents and inverted tangent handedness. Body/head, right limbs, tail and map pixels stay exact.'}

def apply_blender(obj,parts):
 import bpy
 import numpy as np
 mesh=obj.data;before=np.array([v.co[:] for v in mesh.vertices],np.float32);positions=before.copy();replacements={}
 for source,target in PAIRS:
  la,lb=parts[target];ra,rb=parts[source];assert lb-la==rb-ra
  positions[la:lb]=before[ra:rb]*np.array([-1,1,1],np.float32)
  left=[p for p in mesh.polygons if all(la<=i<lb for i in p.vertices)];right=[p for p in mesh.polygons if all(ra<=i<rb for i in p.vertices)];assert len(left)==len(right)
  replacements.update({p.index:(q,la-ra) for p,q in zip(left,right)})
 old_uv=mesh.uv_layers.active.data;normals=[tuple(n.vector) for n in mesh.corner_normals]
 faces=[];corner_uv=[];corner_normals=[];smoothing=[];materials=[]
 for polygon in mesh.polygons:
  donor,offset=replacements.get(polygon.index,(polygon,0));mirrored=polygon.index in replacements;loops=list(donor.loop_indices)
  if mirrored:loops.reverse()
  faces.append([mesh.loops[i].vertex_index+offset for i in loops])
  corner_uv.extend(tuple(old_uv[i].uv) for i in loops)
  corner_normals.extend((-normals[i][0],normals[i][1],normals[i][2]) if mirrored else normals[i] for i in loops)
  smoothing.append(donor.use_smooth);materials.append(donor.material_index)
 new=bpy.data.meshes.new('PenguinMotionCanonicalFeet');new.from_pydata(positions.tolist(),[],faces);new.update()
 for material in mesh.materials:new.materials.append(material)
 uv=new.uv_layers.new(name=mesh.uv_layers.active.name)
 for i,value in enumerate(corner_uv):uv.data[i].uv=value
 for p,s,m in zip(new.polygons,smoothing,materials):p.use_smooth=s;p.material_index=m
 new.normals_split_custom_set(corner_normals);new.update();obj.data=new
 return before,np.array([v.co[:] for v in new.vertices],np.float32),revision_receipt()

def patch_streams(attributes,indices,exported_source,parts):
 import numpy as np
 oldsource=np.asarray(exported_source,dtype=int);source=oldsource.copy();out={name:values.copy() for name,values in attributes.items()};baseline_faces=np.asarray(indices).reshape(-1,3);faces=baseline_faces.copy();protected=np.ones(len(source),bool);count=0
 for donor,target in PAIRS:
  la,lb=parts[target];ra,rb=parts[donor];left=np.where((oldsource>=la)&(oldsource<lb))[0];right=np.where((oldsource>=ra)&(oldsource<rb))[0];assert len(left)==len(right)
  for name in ('POSITION','NORMAL','TANGENT','TEXCOORD_0'):out[name][left]=attributes[name][right]
  for name in ('POSITION','NORMAL','TANGENT'):out[name][left,0]*=-1
  out['TANGENT'][left,3]*=-1;source[left]=source[right]-ra+la
  left_faces=np.where(np.all((oldsource[baseline_faces]>=la)&(oldsource[baseline_faces]<lb),axis=1))[0];right_faces=np.where(np.all((oldsource[baseline_faces]>=ra)&(oldsource[baseline_faces]<rb),axis=1))[0];assert len(left_faces)==len(right_faces)
  mapping=np.arange(len(source));mapping[right]=left;faces[left_faces]=mapping[baseline_faces[right_faces]][:,[0,2,1]];protected[left]=False;count+=len(left)
 for name in out:assert np.array_equal(out[name][protected],attributes[name][protected])
 return out,faces.reshape(-1,1),source,int(count)
