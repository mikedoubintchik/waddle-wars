"""Strict, separate animated candidate gate; never weakens the static shape gate."""
from __future__ import annotations
import copy
import importlib.util
import json
import math
from pathlib import Path
import re
import struct

_spec = importlib.util.spec_from_file_location('motion_shape_contract', Path(__file__).with_name('shape_candidate_export.py'))
shape = importlib.util.module_from_spec(_spec); _spec.loader.exec_module(shape)
_surface_spec = importlib.util.spec_from_file_location('motion_surface_recipe', Path(__file__).resolve().parents[1]/'art/penguin_motion_surface.py')
surface_recipe = importlib.util.module_from_spec(_surface_spec); _surface_spec.loader.exec_module(surface_recipe)
digest = shape.digest
GATE = 'rear-motion-v1'
REST_SHA = 'c895c19f310f71d8667cc871b1947d9a5d635653c99ee5acca4035fcb063c62c'
REST_PATH = 'art_src/characters/penguin_rear_surface_v3/candidate.glb'
CLIPS = {'waddle': True, 'jump': False, 'slide': True}
# Baked rigid TRS has up to1.91e-6 floating noise; source audit separates it
# from actual animation (minimum variation >.006). Never permit arbitrary1key tracks.
CONSTANT_TRACK_TOLERANCE = 3e-6
IMPORTER = shape.SURFACE_IMPORTER.replace('animation/import=false', 'animation/import=true').replace('res://qa_shape/surface_post_import.gd', 'res://qa_motion/motion_post_import.gd')
IMPORTER += 'skins/use_named_skins=true\nanimation/fps=30\nanimation/trimming=false\nanimation/remove_immutable_tracks=false\n'
# Godot4.7 ResourceImporterScene._post_fix_animations reads these per-node
# settings through _subresources/nodes and import_id (fallback PATH:<nodepath>).
# Observed raw scene has no import_id metadata and path AnimationPlayer.
ANIMATION_NODE_SETTINGS = {'nodes': {'PATH:AnimationPlayer': {'optimizer/enabled': False, 'compression/enabled': False}}}
IMPORTER += '_subresources=' + json.dumps(ANIMATION_NODE_SETTINGS, separators=(',', ':')) + '\n'

IDENTITY = [[float(i == j) for j in range(4)] for i in range(4)]


def accessor(doc, binary, index):
    """Motion accessors include float MAT4 inverse binds and integer joint indices."""
    try:
        a = doc['accessors'][index]; view = doc['bufferViews'][a['bufferView']]
        fmt, size = {5126: ('f', 4), 5125: ('I', 4), 5123: ('H', 2), 5121: ('B', 1)}[a['componentType']]
        width = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
        if a.get('sparse') or a.get('normalized') or view.get('buffer', 0) != 0 or type(a['count']) is not int or not 0 < a['count'] <= 1_000_000:
            raise ValueError('Unsupported motion accessor')
        stride = view.get('byteStride', size * width); start = view.get('byteOffset', 0) + a.get('byteOffset', 0)
        if stride < size * width or start < 0 or start + (a['count'] - 1) * stride + size * width > min(len(binary), view.get('byteOffset', 0) + view['byteLength']):
            raise ValueError('Motion accessor exceeds embedded buffer')
        rows = [struct.unpack_from('<' + fmt * width, binary, start + i * stride) for i in range(a['count'])]
        if not all(math.isfinite(x) for row in rows for x in row): raise ValueError('Nonfinite motion accessor')
        return rows
    except (KeyError, IndexError, TypeError, struct.error) as error:
        raise ValueError('Malformed motion accessor') from error


def matmul(a, b):
    return [[sum(a[i][k] * b[k][j] for k in range(4)) for j in range(4)] for i in range(4)]


def column_matrix(values):
    if len(values) != 16 or not all(type(v) in (int, float) and math.isfinite(v) for v in values): raise ValueError('Invalid node/bind matrix')
    return [[values[j * 4 + i] for j in range(4)] for i in range(4)]


def node_matrix(node):
    if 'matrix' in node:
        if any(k in node for k in ['translation', 'rotation', 'scale']): raise ValueError('Mixed matrix/TRS node')
        return column_matrix(node['matrix'])
    t, q, s = node.get('translation', [0, 0, 0]), node.get('rotation', [0, 0, 0, 1]), node.get('scale', [1, 1, 1])
    if len(t) != 3 or len(q) != 4 or len(s) != 3 or not all(type(v) in (int,float) and math.isfinite(v) for v in t+q+s) or any(v <= 0 for v in s) or abs(sum(v*v for v in q)-1) > 1e-5:
        raise ValueError('Invalid finite positive node TRS')
    x,y,z,w=q
    r=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)], [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)], [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
    return [[r[i][j]*s[j] for j in range(3)]+[t[i]] for i in range(3)]+[[0,0,0,1]]


def close_matrix(a,b): return max(abs(a[i][j]-b[i][j]) for i in range(4) for j in range(4)) <= 1e-5


def validate_rig(doc, binary, metadata):
    nodes, skins = doc.get('nodes', []), doc.get('skins', [])
    if len(skins) != 1 or not nodes or len(nodes) > 100: raise ValueError('Motion requires one bounded skin hierarchy')
    if len(doc.get('scenes', [])) != 1 or doc.get('scene', 0) != 0: raise ValueError('Motion requires one default scene')
    parents = {}; roots = doc['scenes'][0].get('nodes', [])
    for i,node in enumerate(nodes):
        if any(k in node for k in ['camera', 'extensions', 'weights']): raise ValueError('Unsupported animated scene node')
        for child in node.get('children', []):
            if type(child) is not int or not 0 <= child < len(nodes) or child in parents: raise ValueError('Invalid/multiple-parent joint hierarchy')
            parents[child]=i
    if len(set(roots)) != len(roots) or set(roots) != set(range(len(nodes)))-set(parents): raise ValueError('Motion scene must contain every hierarchy root')
    worlds={}; visiting=set()
    def world(i):
        if i in visiting: raise ValueError('Cyclic motion hierarchy')
        if i not in worlds:
            visiting.add(i); worlds[i]=matmul(world(parents[i]),node_matrix(nodes[i])) if i in parents else node_matrix(nodes[i]); visiting.remove(i)
        return worlds[i]
    for i in range(len(nodes)): world(i)
    mesh_nodes=[i for i,n in enumerate(nodes) if 'mesh' in n]
    if len(mesh_nodes)!=1 or nodes[mesh_nodes[0]].get('mesh')!=0 or nodes[mesh_nodes[0]].get('skin')!=0 or not close_matrix(world(mesh_nodes[0]),IDENTITY): raise ValueError('Motion requires one identity-world skinned mesh')
    if any('skin' in n for i,n in enumerate(nodes) if i not in mesh_nodes): raise ValueError('Unexpected skin reference')
    skin=skins[0]; joints=skin.get('joints', [])
    if not 2 <= len(joints) <= 64 or len(set(joints)) != len(joints) or any(type(j) is not int or not 0 <= j < len(nodes) or j in mesh_nodes for j in joints): raise ValueError('Invalid skin joint list')
    names=[nodes[j].get('name') for j in joints]
    if any(not isinstance(n,str) or not re.fullmatch(r'[A-Za-z][A-Za-z0-9_]*',n) for n in names) or len(set(names)) != len(names): raise ValueError('Joint names must be unique safe identifiers')
    if metadata.get('rig', {}).get('joints') != names: raise ValueError('Declared joints differ from actual skin order')
    joint_roots=[j for j in joints if parents.get(j) not in joints]
    if len(joint_roots)!=1 or skin.get('skeleton',joint_roots[0]) not in [joint_roots[0],parents.get(joint_roots[0])]: raise ValueError('Skin joints must form one connected hierarchy')
    for j in joints:
        if j!=joint_roots[0] and parents.get(j) not in joints: raise ValueError('Disjoint bone hierarchy')
    binds=accessor(doc,binary,skin['inverseBindMatrices'])
    bind_accessor=doc['accessors'][skin['inverseBindMatrices']]
    if bind_accessor['type']!='MAT4' or bind_accessor['componentType']!=5126 or len(binds)!=len(joints): raise ValueError('Inverse bind matrices missing or malformed')
    for j,bind in zip(joints,binds):
        if not close_matrix(matmul(world(j),column_matrix(bind)),world(mesh_nodes[0])): raise ValueError('Inverse bind matrix changes accepted rest pose')
    primitive=doc['meshes'][0]['primitives'][0];attrs=primitive['attributes']; count=len(accessor(doc,binary,attrs['POSITION']))
    if set(attrs)-{'POSITION','NORMAL','TANGENT','TEXCOORD_0','JOINTS_0','WEIGHTS_0'}: raise ValueError('Unexpected motion mesh attribute')
    indices=accessor(doc,binary,attrs['JOINTS_0']);weights=accessor(doc,binary,attrs['WEIGHTS_0'])
    ja,wa=doc['accessors'][attrs['JOINTS_0']],doc['accessors'][attrs['WEIGHTS_0']]
    if ja['type']!='VEC4' or ja['componentType'] not in (5121,5123) or wa['type']!='VEC4' or wa['componentType']!=5126 or len(indices)!=count or len(weights)!=count: raise ValueError('Skin needs four finite joint weights per vertex')
    for js,ws in zip(indices,weights):
        if any(not 0<=j<len(joints) for j in js) or any(not 0<=w<=1 for w in ws) or abs(sum(ws)-1)>1e-5: raise ValueError('Invalid or unnormalized skin weights')
    animations=doc.get('animations',[])
    if len(animations)!=3 or {a.get('name') for a in animations} != set(CLIPS) or set(metadata.get('clips',{})) != set(CLIPS): raise ValueError('Motion requires exactly waddle, jump and slide clips')
    clip_proof={}
    for animation in animations:
        name=animation['name']; contract=metadata['clips'][name];duration=contract.get('duration')
        if type(duration) not in (int,float) or not math.isfinite(duration) or not .2<=duration<=5 or contract.get('loop') is not CLIPS[name]: raise ValueError('Invalid clip duration/loop contract')
        channels=animation.get('channels',[]);samplers=animation.get('samplers',[]);seen=set();used=set();moving=False;records=[]
        if not channels or len(channels)>len(joints)*3: raise ValueError('Empty/oversized motion clip')
        for channel in channels:
            target=channel.get('target',{});bone=target.get('node');path=target.get('path'); key=(bone,path)
            if bone not in joints or path not in ('translation','rotation','scale') or key in seen or target.get('extensions'): raise ValueError('Animation must use unique joint-only TRS tracks')
            seen.add(key);si=channel.get('sampler')
            if type(si) is not int or not 0<=si<len(samplers): raise ValueError('Missing animation sampler')
            used.add(si);sampler=samplers[si]
            if sampler.get('interpolation','LINEAR')!='LINEAR': raise ValueError('Motion clips must contain baked LINEAR keys')
            times=accessor(doc,binary,sampler['input']);values=accessor(doc,binary,sampler['output'])
            ta,va=doc['accessors'][sampler['input']],doc['accessors'][sampler['output']]
            if ta['type']!='SCALAR' or ta['componentType']!=5126 or va['componentType']!=5126 or va['type']!=('VEC4' if path=='rotation' else 'VEC3') or len(times)<2 or len(times)!=len(values): raise ValueError('Invalid animation key accessor')
            ts=[v[0] for v in times]
            if abs(ts[0])>1e-6 or abs(ts[-1]-duration)>1e-5 or any(b<=a for a,b in zip(ts,ts[1:])): raise ValueError('Animation keys must span declared duration in increasing order')
            if path=='rotation' and any(abs(sum(v*v for v in q)-1)>1e-4 for q in values): raise ValueError('Animation quaternion not normalized')
            if path=='scale' and any(v<=0 for row in values for v in row): raise ValueError('Animation scale must stay positive')
            endpoint_error=min(max(abs(a-b) for a,b in zip(values[0],values[-1])),max(abs(a+b) for a,b in zip(values[0],values[-1]))) if path=='rotation' else max(abs(a-b) for a,b in zip(values[0],values[-1]))
            if CLIPS[name] and endpoint_error>1e-5: raise ValueError('Loop endpoints differ')
            moving |= any(max(abs(a-b) for a,b in zip(values[0],v))>1e-4 for v in values[1:])
            max_deviation = max(min(max(abs(a-b) for a,b in zip(values[0],v)), max(abs(a+b) for a,b in zip(values[0],v))) if path == 'rotation' else max(abs(a-b) for a,b in zip(values[0],v)) for v in values)
            constant = max_deviation <= CONSTANT_TRACK_TOLERANCE
            records.append({'joint':nodes[bone]['name'],'path':path,'keys':len(ts),'constant':constant,
                            'max_deviation':max_deviation,'constant_tolerance':CONSTANT_TRACK_TOLERANCE,
                            'data_sha256':digest(json.dumps([times,values],separators=(',',':')).encode())})
        if used!=set(range(len(samplers))) or not moving: raise ValueError('Unused sampler or static placeholder clip')
        clip_proof[name]={'duration':duration,'loop':CLIPS[name],'tracks':sorted(records,key=lambda r:(r['joint'],r['path']))}
    return {'joints':names,'parents':[names[joints.index(parents[j])] if parents.get(j) in joints else None for j in joints],
            'rest_matrices_sha256':digest(json.dumps([world(j) for j in joints]).encode()),'rest_local_matrices':[node_matrix(nodes[j]) for j in joints],'inverse_binds_sha256':digest(json.dumps(binds).encode()),
            'weights_sha256':digest(json.dumps([indices,weights]).encode()),'rest_bind_identity_verified':True,'clips':clip_proof}


def map_bytes(doc,binary):
    if len(doc.get('materials',[]))!=1 or len(doc.get('textures',[]))!=3 or len(doc.get('images',[]))!=3 or doc.get('extensionsUsed') or doc.get('extensionsRequired'): raise ValueError('Motion requires exactly the accepted standard three-map material')
    material=doc['materials'][0];pbr=material['pbrMetallicRoughness']; result={}
    slots={'base_color':(pbr['baseColorTexture'],'srgb'),'normal':(material['normalTexture'],'linear'),'metallic_roughness':(pbr['metallicRoughnessTexture'],'linear')}
    for name,(slot,space) in slots.items():
        texture=doc['textures'][slot['index']];image=doc['images'][texture['source']];view=doc['bufferViews'][image['bufferView']]
        if image.get('mimeType')!='image/png' or 'uri' in image or view.get('buffer',0)!=0 or texture.get('extensions') or slot.get('extensions') or slot.get('texCoord',0)!=0: raise ValueError('Unsupported motion map binding')
        start=view.get('byteOffset',0);end=start+view['byteLength']
        if start<0 or end>len(binary):raise ValueError('Motion map buffer outside GLB')
        result[name]=(binary[start:end],texture['source'],space,doc['samplers'][texture['sampler']])
    if len({v[1] for v in result.values()})!=3:raise ValueError('Motion maps must remain separate')
    return result


def mirrored_right_component(doc: dict, binary: bytes, original: dict, source_part: str) -> dict:
    """Independent exact expected left limb: reflect accepted right triangles.

    The immutable c895 atlas uniquely identifies each right-limb chart. Closed
    component validation separately proves counts, topology and winding.
    """
    if source_part not in ('foot_R','flipper_R'):
        raise ValueError('Only approved right foot/flipper can be canonical donors')
    y0,y1={'foot_R':(264,504),'flipper_R':(520,1016)}[source_part]
    primitive=doc['meshes'][0]['primitives'][0];attrs=primitive['attributes']
    positions=accessor(doc,binary,attrs['POSITION']);normals=accessor(doc,binary,attrs['NORMAL'])
    uv=accessor(doc,binary,attrs['TEXCOORD_0']);tangents=accessor(doc,binary,attrs['TANGENT'])
    indices=[row[0] for row in accessor(doc,binary,primitive['indices'])]
    seeds={i for i,(p,t) in enumerate(zip(positions,uv)) if p[0]>0
           and 832/1024-1e-7<=t[0]<=1000/1024+1e-7
           and 1-y1/1024-1e-7<=t[1]<=1-y0/1024+1e-7}
    # Cap UVs extend into padding. Weld exact positions to recover the entire
    # connected limb rather than clipping its chart bounds or guessing slices.
    unique={};welded=[]
    for p in positions:
        if p not in unique:unique[p]=len(unique)
        welded.append(unique[p])
    parent=list(range(len(unique)))
    def root(i):
        while parent[i]!=i:
            parent[i]=parent[parent[i]];i=parent[i]
        return i
    for start in range(0,len(indices),3):
        a,b,c=[welded[i] for i in indices[start:start+3]]
        parent[root(b)]=root(a);parent[root(c)]=root(a)
    groups={root(welded[i]) for i in seeds}
    if len(groups)!=1:raise ValueError('Canonical '+source_part+' chart is missing or ambiguous')
    selected={i for i in range(len(positions)) if root(welded[i]) in groups}
    records=[];uv_records=[];points=set()
    for start in range(0,len(indices),3):
        tri=indices[start:start+3]
        if not any(i in selected for i in tri):continue
        if not all(i in selected for i in tri):raise ValueError('Canonical '+source_part+' atlas triangle crosses part boundary')
        tri=[tri[0],tri[2],tri[1]]  # Reflection changes handedness.
        vertices=[];uv_vertices=[]
        for i in tri:
            p,n,t=positions[i],normals[i],tangents[i]
            point=(-p[0],p[1],p[2]);points.add(point)
            vertices.append(struct.pack('<12f',*(point+(-n[0],n[1],n[2])+tuple(uv[i])+(-t[0],t[1],t[2],-t[3]))))
            uv_vertices.append(struct.pack('<2f',*uv[i]))
        records.append(min(b''.join(vertices[n:]+vertices[:n]) for n in range(3)))
        uv_records.append(min(b''.join(uv_vertices[n:]+uv_vertices[:n]) for n in range(3)))
    if len(points)!=original[source_part]['unique_positions'] or len(records)!=original[source_part]['triangles']:
        raise ValueError('Canonical '+source_part+' chart failed complete component coverage')
    return {'unique_positions':len(points),'triangles':len(records),
            'position_normal_uv_tangent_sha256':digest(b''.join(sorted(records))),
            'oriented_uv_triangles_sha256':digest(b''.join(sorted(uv_records))),
            'bounds_min':[min(p[k] for p in points) for k in range(3)],
            'bounds_max':[max(p[k] for p in points) for k in range(3)]}


def validate_rest_geometry(components, original, before, old, metadata):
    revision=metadata.get('anatomy_revision')
    if revision is None:
        if components!=original:raise ValueError('Motion changed accepted rest positions, normals, UVs, tangents or triangles')
        return {}
    path=Path(__file__).resolve().parents[1]/'art/penguin_motion_anatomy.py'
    spec=importlib.util.spec_from_file_location('motion_anatomy_recipe',path)
    recipe=importlib.util.module_from_spec(spec);spec.loader.exec_module(recipe)
    if not isinstance(revision,dict) or revision!=recipe.revision_receipt() \
            or revision.get('id')!='mirrored-right-limbs-v1' \
            or revision.get('baseline_glb_sha256')!=REST_SHA \
            or revision.get('recipe_path')!='tools/art/penguin_motion_anatomy.py' \
            or revision.get('recipe_sha256')!=digest(path.read_bytes()) \
            or revision.get('reflection')!=[-1,1,1] or revision.get('translation')!=[0,0,0] \
            or revision.get('pairs')!=[{'source_part':'foot_R','target_part':'foot_L'}, {'source_part':'flipper_R','target_part':'flipper_L'}] \
            or revision.get('uv_policy')!='reuse-source-part':
        raise ValueError('Motion anatomy revision differs from approved mirrored right-limbs recipe')
    expected=copy.deepcopy(original)
    for source,target in [('foot_R','foot_L'),('flipper_R','flipper_L')]:
        expected[target]=mirrored_right_component(before,old,original,source)
    if components!=expected:
        changed=[name for name in expected if components.get(name)!=expected[name]]
        raise ValueError('Motion anatomy must match exact reflected right limbs; divergent parts: '+','.join(changed))
    return revision


def validate_package(package: Path, reference: Path | None = None) -> dict:
    package=package.resolve(strict=True);files={}
    for name in ('metadata.json','candidate.glb','source.blend'):
        path=package/name
        if path.is_symlink() or not path.is_file() or path.resolve().parent!=package:raise ValueError('Missing or unsafe motion package file: '+name)
        files[name]=path.read_bytes()
    metadata=json.loads(files['metadata.json'])
    if metadata.get('schema_version')!=1 or metadata.get('gate')!=GATE or metadata.get('material_contract')!=shape.SURFACE_CONTRACT or metadata.get('unrigged') is not False or metadata.get('animation_ready') is not True or metadata.get('production_ready') is not False:raise ValueError('Package must explicitly declare isolated rear motion review')
    if metadata.get('glb_sha256')!=digest(files['candidate.glb']) or metadata.get('source_sha256')!=digest(files['source.blend']):raise ValueError('Motion source/model hash mismatch')
    if metadata.get('rest_reference')!={'path':REST_PATH,'glb_sha256':REST_SHA}:raise ValueError('Motion must bind accepted c895 rest reference')
    reference=reference or Path(__file__).resolve().parents[2]/REST_PATH; baseline=reference.read_bytes()
    if digest(baseline)!=REST_SHA:raise ValueError('Accepted motion rest reference changed')
    doc,binary=shape.glb_data(files['candidate.glb']);before,old=shape.glb_data(baseline)
    if len(doc.get('buffers',[]))!=1 or any('uri' in b for b in doc['buffers']) or len(doc.get('meshes',[]))!=1 or len(doc['meshes'][0].get('primitives',[]))!=1:raise ValueError('Motion requires one embedded triangle mesh')
    primitive=doc['meshes'][0]['primitives'][0]
    if primitive.get('mode',4)!=4 or primitive.get('material')!=0 or primitive.get('targets') or doc['meshes'][0].get('weights'):raise ValueError('Motion mesh topology/material contract invalid')
    rest=copy.deepcopy(doc);rest['nodes']=[{'mesh':0}]
    components=shape.surface_components(rest,binary);original=shape.surface_components(before,old)
    anatomy_revision=validate_rest_geometry(components,original,before,old,metadata)
    # Material names may change; actual settings and every referenced texture remain exact.
    def settings(document):
        material=copy.deepcopy(document['materials'][0]);material.pop('name',None)
        for slot in [material.get('normalTexture',{}),material['pbrMetallicRoughness'].get('baseColorTexture',{}),material['pbrMetallicRoughness'].get('metallicRoughnessTexture',{})]:slot.pop('index',None)
        return material
    current_maps,old_maps=map_bytes(doc,binary),map_bytes(before,old)
    current_settings,old_settings=settings(doc),settings(before)
    revision=metadata.get('material_revision',{})
    if 'material_revision' in metadata and (not isinstance(revision,dict) or not revision):
        raise ValueError('Motion material revision must explicitly name the approved recipe')
    revised_base=None
    if revision:
        revised_base,expected_revision=surface_recipe.derive(old_maps['base_color'][0])
        if revision!=expected_revision or current_settings.get('extras',{}).get('ww_motion_surface')!=expected_revision:
            raise ValueError('Motion material revision differs from exact source recipe/provenance')
        current_settings['extras'].pop('ww_motion_surface')
        if not current_settings['extras']:current_settings.pop('extras')
    if current_settings!=old_settings or set(metadata.get('surface_maps',{}))!=set(current_maps):raise ValueError('Motion changed accepted PBR material settings')
    maps={}
    for name,(encoded,index,space,sampler) in current_maps.items():
        expected_encoded=revised_base if name=='base_color' and revised_base is not None else old_maps[name][0]
        if encoded!=expected_encoded or sampler!=old_maps[name][3]:raise ValueError('Motion changed accepted map bytes or filtering: '+name)
        w,h,pixels=shape.png_rgba(encoded);actual={'image_index':index,'sha256':digest(encoded),'width':w,'height':h,'color_space':space}
        if any(metadata['surface_maps'][name].get(k)!=v for k,v in actual.items()):raise ValueError('Motion surface map metadata mismatch: '+name)
        maps[name]={**actual,'rgba8_sha256':digest(pixels),'texcoord':0}
    rig=validate_rig(doc,binary,metadata)
    bounds=[original[name]['bounds_max'][1] for name in original];low=min(original[name]['bounds_min'][1] for name in original);height=max(bounds)-low
    if not isinstance(metadata.get('source_height_m'),(int,float)) or abs(metadata['source_height_m']-height)>1e-6 or metadata.get('gameplay_height_m')!=1.05 or abs(metadata.get('gameplay_scale',0)-1.05/height)>1e-6:raise ValueError('Motion gameplay rest scale changed')
    material=doc['materials'][0]
    return {'metadata':metadata,'files':files,'rest_components':components,'surface_maps':maps,'rig':rig,'clips':rig.pop('clips'),
            'gameplay_scale':1.05/height,'surface_count':1,'normal_scale':material['normalTexture'].get('scale',1),'double_sided':bool(material.get('doubleSided',False)),
            'material_revision':revision,
            'anatomy_revision':anatomy_revision,
            'materials':[{'name':material.get('name',''),'roughness':1.0,'metallic':1.0,'specular':surface_recipe.SPECULAR if revision else 0.5,'normal_scale':material['normalTexture'].get('scale',1),'double_sided':bool(material.get('doubleSided',False))}]}


def install(source: Path, project: Path, package: Path) -> dict:
    source,project=source.resolve(),project.resolve();validated=validate_package(package)
    if source==project or not (project/'_qa_local').is_dir() or (project/'_qa_local').is_symlink():raise ValueError('Motion review requires separate prepared QA project')
    for name in ('project.godot','export_presets.cfg'):
        path=project/name
        if path.is_symlink() or not path.resolve().is_relative_to(project):raise ValueError('Unsafe motion review destination')
    config=(project/'project.godot').read_text();presets=(project/'export_presets.cfg').read_text();bridge='ChromeReferenceQA="*res://_qa_local/chrome_reference_bridge.gd"'
    if not re.search(r'^config/custom_user_dir_name="waddle-chrome-reference-[^"\n]+"$',config,re.M) or 'config/use_custom_user_dir=true' not in config or config.count(bridge)!=1 or config.count('[qa]\n')!=1 or any(k in config for k in ['HeroCandidateQA=','ShapeCandidateQA=','MotionCandidateQA=','hero_motion_enabled=','hero_shape_enabled=']):raise ValueError('Motion review requires isolated bridge without another candidate')
    if presets.count(',_qa_local/*.js"')!=1:raise ValueError('Motion QA include filter missing')
    folder=project/'qa_motion';helper_path=project/'_qa_local/motion_candidate_browser.gd'
    if folder.exists() or folder.is_symlink() or helper_path.exists() or helper_path.is_symlink():raise ValueError('Motion candidate already installed')
    helper=(source/'tools/qa/motion_candidate_browser.gd').read_bytes();post=(source/'tools/qa/motion_candidate_post_import.gd').read_bytes();surface=(source/'tools/qa/surface_candidate_post_import.gd').read_bytes()
    metadata=validated['metadata'];binding={k:validated[k] for k in ['rest_components','surface_maps','rig','clips','gameplay_scale','surface_count','normal_scale','double_sided','materials','material_revision','anatomy_revision']}
    binding.update({k:metadata[k] for k in ['gate','material_contract','source_height_m','gameplay_height_m','rest_reference','glb_sha256','source_sha256']})
    binding.update(schema_version=1,unrigged=False,animation_ready=True,production_ready=False,metadata_sha256=digest(validated['files']['metadata.json']),importer_sha256=digest(IMPORTER.encode()),post_import_sha256=digest(post),surface_post_import_sha256=digest(surface),scope='Rear motion candidate: waddle, jump and slide; front and final integration pending',animation_import_policy=ANIMATION_NODE_SETTINGS)
    folder.mkdir()
    for name,data in [('candidate.glb',validated['files']['candidate.glb']),('candidate.glb.import',IMPORTER.encode()),('motion_post_import.gd',post),('surface_post_import.gd',surface),('candidate_binding.json',(json.dumps(binding,indent=2)+'\n').encode())]: (folder/name).write_bytes(data)
    helper_path.write_bytes(helper)
    config=config.replace(bridge,bridge+'\nMotionCandidateQA="*res://_qa_local/motion_candidate_browser.gd"',1).replace('[qa]\n','[qa]\nhero_motion_enabled=true\n',1)
    (project/'project.godot').write_text(config);(project/'export_presets.cfg').write_text(presets.replace(',_qa_local/*.js"',',_qa_local/*.js,qa_motion/*.json"',1))
    return {'binding':binding,'binding_sha256':digest((folder/'candidate_binding.json').read_bytes()),'helper_sha256':digest(helper),'controls_sha256':digest(review_controls().encode()),'gallery_eligible':False,'scope':binding['scope']}


def review_controls():
    return '''<style>#ww-motion-review{position:fixed;z-index:2147483646;bottom:8px;left:50%;transform:translateX(-50%);width:min(460px,calc(100vw - 16px));box-sizing:border-box;background:#0c1d2af5;color:#eef7fa;border:1px solid #7298a3;border-radius:12px;padding:10px;font:13px/1.4 system-ui}#ww-motion-review small{display:block}#ww-motion-review button{min-height:36px;margin:3px;border:1px solid #668696;border-radius:7px;background:#203c50;color:inherit;font:inherit}#ww-motion-review [aria-pressed=true]{background:#d0eff2;color:#102e3a}</style>
<section id="ww-motion-review" hidden aria-label="Motion candidate controls"><strong>Motion candidate</strong> <span role="status" aria-live="polite">Preparing…</span><small>Rear motion review • front and final integration pending</small><div><button data-view="rear">In-game rear</button><button data-view="rear_detail">Rear detail</button></div><div><button data-action="waddle">Waddle</button><button data-action="jump">Jump</button><button data-action="slide">Slide</button><button data-playing="false">Play</button><button data-playing="true">Pause</button></div></section>
<script>(()=>{const panel=document.getElementById('ww-motion-review');if(!panel||!window.__wwQABuild?.hero_motion||!['127.0.0.1','localhost','[::1]'].includes(location.hostname)||!new URLSearchParams(location.search).get('qa_token'))return;panel.hidden=false;const buttons=[...panel.querySelectorAll('button')],status=panel.querySelector('[role=status]');let busy=false;const delay=()=>new Promise(r=>setTimeout(r,160));async function ready(){const end=Date.now()+180000;let routed=false;while(Date.now()<end){const qa=window.__wwQA?.read(),motion=window.__wwMotionCandidate?.status();if(qa?.status==='error'||motion?.status==='error')throw Error('Preview unavailable');if(qa?.status==='ready'&&qa.route!=='runner_hud'&&!routed){window.__wwQA.route('runner_hud');routed=true;}if(qa?.status==='ready'&&qa.route==='runner_hud'&&qa.settled_frames>=2&&motion?.status==='ready')return;await delay();}throw Error('Preview unavailable');}async function run(button){if(busy)return;busy=true;buttons.forEach(b=>b.disabled=true);try{await ready();if(button){if(button.dataset.view)window.__wwMotionCandidate.view(button.dataset.view);else if(button.dataset.action)window.__wwMotionCandidate.action(button.dataset.action);else window.__wwMotionCandidate.play(button.dataset.playing==='false');await new Promise(r=>requestAnimationFrame(()=>requestAnimationFrame(r)));}const proof=window.__wwMotionCandidate.read();if(proof.status!=='ready'||proof.errors?.length)throw Error('Verification failed');status.textContent='Verified';buttons.forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.view?b.dataset.view===proof.view:b.dataset.action?b.dataset.action===proof.action:((b.dataset.playing==='false')===!!proof.playing))));}catch(e){status.textContent=e.message;}finally{busy=false;buttons.forEach(b=>b.disabled=false);}}buttons.forEach(b=>b.addEventListener('click',()=>run(b)));run(null);})();</script>'''
