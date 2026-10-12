#!/usr/bin/env python3
"""Fresh fitted penguin rig and baked in-place clips. Blender5.2, no rendering.
Protected accepted GLB streams stay literal. Explicit source recipes replace the
left foot and flipper with mirrored right anatomy and adjust matte feather surface contrast.
Skin and animation buffers come from this editable Blender rig.
"""
from pathlib import Path
import bpy, json, math, struct, hashlib, copy, importlib.util
import numpy as np
from mathutils import Matrix, Vector, Quaternion
ROOT=Path(__file__).resolve().parents[2]
BASE=ROOT/'art_src/characters/penguin_rear_surface_v3'
OUT=ROOT/'art_src/characters/penguin_motion_v1'
REST_SHA='c895c19f310f71d8667cc871b1947d9a5d635653c99ee5acca4035fcb063c62c'
FPS=30
CLIPS={'waddle':{'duration':1.2,'loop':True},'jump':{'duration':1.0,'loop':False},'slide':{'duration':1.2,'loop':True}}
C=Matrix(((1,0,0,0),(0,0,1,0),(0,-1,0,0),(0,0,0,1)))
sha=lambda p:hashlib.sha256(Path(p).read_bytes()).hexdigest()

def glb_read(path):
    raw=path.read_bytes();offset=12;doc=None;binary=None
    while offset<len(raw):
        n,k=struct.unpack_from('<II',raw,offset);data=raw[offset+8:offset+8+n];offset+=8+n
        if k==0x4e4f534a:doc=json.loads(data)
        elif k==0x004e4942:binary=bytearray(data)
    return doc,binary

def array(doc,binary,index):
    a=doc['accessors'][index];v=doc['bufferViews'][a['bufferView']];dt=np.dtype({5126:'<f4',5125:'<u4',5123:'<u2',5121:'u1'}[a['componentType']]);w={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[a['type']]
    return np.ndarray((a['count'],w),dtype=dt,buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',dt.itemsize*w),dt.itemsize)).copy()

def add_accessor(doc,binary,values,kind,component=5126,target=None):
    values=np.asarray(values,dtype={5126:'<f4',5123:'<u2',5125:'<u4'}[component]);values=values.reshape(len(values),-1)
    while len(binary)%4:binary.append(0)
    view={'buffer':0,'byteOffset':len(binary),'byteLength':values.nbytes}
    if target:view['target']=target
    doc['bufferViews'].append(view);binary.extend(values.tobytes())
    a={'bufferView':len(doc['bufferViews'])-1,'componentType':component,'count':len(values),'type':kind}
    if kind in ('SCALAR','VEC3'):a.update(min=values.min(0).astype(float).tolist(),max=values.max(0).astype(float).tolist())
    doc['accessors'].append(a);return len(doc['accessors'])-1

def write_glb(path,doc,binary):
    doc['buffers'][0]['byteLength']=len(binary)
    text=json.dumps(doc,separators=(',',':')).encode();text+=b' '*((-len(text))%4);binary+=b'\0'*((-len(binary))%4)
    path.write_bytes(struct.pack('<III',0x46546c67,2,12+8+len(text)+8+len(binary))+struct.pack('<II',len(text),0x4e4f534a)+text+struct.pack('<II',len(binary),0x004e4942)+binary)

def translate(p):return Matrix.Translation(Vector(p))
def rotate(axis,degrees):return Matrix.Rotation(math.radians(degrees),4,axis)
def around(p,r):return translate(p)@r@translate(-Vector(p))
def smooth(a,b,x):
    v=max(0.,min(1.,(x-a)/(b-a)));return v*v*(3-2*v)
def rigid_mix(a,b,t):
    at,ar,_=a.decompose();bt,br,_=b.decompose()
    return translate(at.lerp(bt,t))@ar.slerp(br,t).to_matrix().to_4x4()
def transform_points(matrix,points):return np.c_[points,np.ones(len(points))]@np.array(matrix).T
def contained_by_closed_mesh(point,triangles):
    """Three independent ray parity checks on the actual posed body surface."""
    point=np.asarray(point,dtype=float);e1=triangles[:,1]-triangles[:,0];e2=triangles[:,2]-triangles[:,0];relative=point-triangles[:,0];answers=[]
    for direction in ((.932,.271,.241),(-.383,.877,.293),(.249,-.421,.872)):
        ray=np.asarray(direction);h=np.cross(ray,e2);det=np.einsum('ij,ij->i',e1,h);valid=np.abs(det)>1e-10;inv=np.divide(1.,det,out=np.zeros_like(det),where=valid)
        u=inv*np.einsum('ij,ij->i',relative,h);q=np.cross(relative,e1);v=inv*(q@ray);t=inv*np.einsum('ij,ij->i',e2,q)
        hits=np.sort(t[valid&(u>=-1e-8)&(v>=-1e-8)&(u+v<=1+1e-8)&(t>1e-8)])
        distinct=0 if len(hits)==0 else 1+int(np.count_nonzero(np.diff(hits)>1e-7));answers.append(bool(distinct%2))
    return answers

def main():
    assert tuple(bpy.app.version[:3])==(5,2,0)
    assert sha(BASE/'candidate.glb')==REST_SHA
    OUT.mkdir(parents=True,exist_ok=True);metadata=json.loads((BASE/'metadata.json').read_text())
    bpy.ops.wm.open_mainfile(filepath=str(BASE/'source.blend'))
    mesh_obj=bpy.data.objects['RearBlockout'];parts=metadata['parts_vertex_ranges']
    spec=importlib.util.spec_from_file_location('penguin_motion_anatomy',ROOT/'tools/art/penguin_motion_anatomy.py');anatomy=importlib.util.module_from_spec(spec);spec.loader.exec_module(anatomy)
    baseline_rest,rest,anatomy_revision=anatomy.apply_blender(mesh_obj,parts);mesh=mesh_obj.data
    metadata['anatomical_foot_direction']['left']=copy.deepcopy(metadata['anatomical_foot_direction']['right'])
    for field in ('rear_heel','forward_middle_toe','ankle_cap','anatomical_forward_direction_godot'):
        metadata['anatomical_foot_direction']['left'][field][0]*=-1
    # Bone hierarchy fitted to accepted anatomy; no legacy rig is loaded.
    cap={side:Vector(metadata['anatomical_foot_direction']['left' if side=='L' else 'right']['ankle_cap']) for side in ('L','R')}
    # Metadata foot landmarks use Godot coordinates.
    cap={s:Vector((v.x,-v.z,v.y)) for s,v in cap.items()}
    # Canonical mirrored feet retain anatomical per-side lateral axes.
    # Articulate about each anatomical lateral axis, not the avatar-wide X axis.
    foot_lateral={}
    for s,side in [('L','left'),('R','right')]:
        forward=metadata['anatomical_foot_direction'][side]['anatomical_forward_direction_godot']
        foot_lateral[s]=Vector((-forward[2],-forward[0],0)).normalized()
    pivot=Vector((0,.045,.32));torso_pivot=Vector((0,.115,.82));head_pivot=Vector((0,.24,1.32))
    shoulders={s:Vector(rest[parts['flipper_'+s][0]:parts['flipper_'+s][0]+16].mean(0)) for s in ('L','R')}
    mids={s:Vector(rest[parts['flipper_'+s][0]+225:parts['flipper_'+s][0]+241].mean(0)) for s in ('L','R')}
    definitions=[('motion_root',None,(0,0,0),(0,0,.12)),('pelvis','motion_root',pivot,(0,.08,.70)),('torso','pelvis',torso_pivot,head_pivot),('head','torso',head_pivot,(0,.32,1.62))]
    for s,sign in [('L',-1),('R',1)]:
        hip=Vector((sign*.23,.045,.43));ankle=cap[s]
        definitions += [('hip_'+s,'pelvis',hip,ankle),('ankle_'+s,'hip_'+s,ankle,ankle+Vector((0,.035,-.10))),('foot_'+s,'ankle_'+s,ankle,ankle+Vector((0,.18,-.23))),('flipper_'+s,'torso',shoulders[s],mids[s]),('flipper_tip_'+s,'flipper_'+s,mids[s],Vector(rest[parts['flipper_'+s][1]-1]))]
    definitions += [('tail','pelvis',(0,-.25,.40),(0,-.31,.16))]
    rig_data=bpy.data.armatures.new('PenguinMotionRig');rig=bpy.data.objects.new('PenguinMotionRig',rig_data);bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig;rig.select_set(True);mesh_obj.select_set(False);bpy.ops.object.mode_set(mode='EDIT')
    for name,parent,head,tail in definitions:
        bone=rig_data.edit_bones.new(name);bone.head=head;bone.tail=tail;bone.use_deform=True
        if parent:bone.parent=rig_data.edit_bones[parent]
        bone.use_connect=False
    bpy.ops.object.mode_set(mode='OBJECT');names=[d[0] for d in definitions];joint_index={name:i for i,name in enumerate(names)}
    rest_global={name:rig_data.bones[name].matrix_local.copy() for name in names};parents={d[0]:d[1] for d in definitions}
    weights=np.zeros((len(rest),len(names)),np.float32)
    def weight(i,entries):
        total=sum(entries.values());assert total>0
        for name,value in entries.items():weights[i,joint_index[name]]=value/total
    b0,b1=parts['continuous_body_head']
    mesh.calc_loop_triangles()
    body_triangles=np.array([tuple(t.vertices) for t in mesh.loop_triangles if all(b0<=i<b1 for i in t.vertices)],dtype=int)
    for i in range(b0,b1):
        z=float(rest[i,2]);upper=smooth(.63,1.02,z);head=smooth(1.22,1.47,z)
        weight(i,{'pelvis':1-upper,'torso':upper*(1-head),'head':upper*head})
    for s in ('L','R'):
        f0,f1=parts['foot_'+s]
        for i in range(f0,f1):
            # Rounded heel and forefoot are one rigid volume. Only the narrow
            # upper ankle bends; the old .095m onset deformed the visible heel.
            z=float(rest[i,2]);cap_weight=smooth(.218,.278,z);ankle_weight=.25*smooth(.205,.250,z)*(1-cap_weight)
            weight(i,{'foot_'+s:1-cap_weight-ankle_weight,'ankle_'+s:ankle_weight,'hip_'+s:cap_weight})
        f0,f1=parts['flipper_'+s];root=shoulders[s];tip=Vector(rest[f1-1]);axis=tip-root;length=axis.length_squared
        for i in range(f0,f1):
            t=max(0,min(1,(Vector(rest[i])-root).dot(axis)/length));tip_weight=smooth(.45,.82,t)*.72;body_weight=(1-smooth(0,.13,t))*.22
            weight(i,{'torso':body_weight,'flipper_'+s:(1-body_weight)*(1-tip_weight),'flipper_tip_'+s:(1-body_weight)*tip_weight})
    for i in range(*parts['short_tail_fan']):weight(i,{'tail':1})
    assert np.max(np.count_nonzero(weights>1e-8,axis=1))<=4 and np.max(abs(weights.sum(1)-1))<1e-6
    for group in list(mesh_obj.vertex_groups):mesh_obj.vertex_groups.remove(group)
    for name in names:
        group=mesh_obj.vertex_groups.new(name=name)
        for i in np.where(weights[:,joint_index[name]]>0)[0]:group.add([int(i)],float(weights[i,joint_index[name]]),'REPLACE')
    modifier=mesh_obj.modifiers.new('FreshMotionSkin','ARMATURE');modifier.object=rig;mesh_obj.parent=rig;mesh_obj.matrix_parent_inverse=Matrix.Identity(4)
    scene=bpy.context.scene;scene.render.fps=FPS;rig.animation_data_create()
    def posed_vertices(ds,begin=0,end=None):
        end=len(rest) if end is None else end;points=rest[begin:end];out=np.zeros_like(points,dtype=np.float64)
        for j,name in enumerate(names):
            w=weights[begin:end,j]
            if np.any(w):out+=transform_points(ds[name],points)[:,:3]*w[:,None]
        return out
    def pose(clip,p):
        wave=math.tau*p;ds={name:Matrix.Identity(4) for name in names};flap={s:0. for s in ('L','R')};foot_ds={};support={}
        if clip=='waddle':
            roll=-20*math.cos(wave);body=translate((-.025*math.cos(wave),0,.012*(1-math.cos(2*wave))))@around(pivot,rotate('Y',roll))
            upper=body@around(torso_pivot,rotate('X',-2.5*(.5+.5*math.cos(2*wave))))
            head=upper@around(head_pivot,rotate('Y',-roll*.13))
            for s,offset in [('L',.31),('R',.81)]:
                phase=(p+offset)%1;stance=phase<=.62;support[s]=stance
                swing=0. if stance else (phase-.62)/.38;lift=.150*math.sin(math.pi*swing)**1.45
                forward=.072*math.sin(math.pi*swing);pitch=-12*math.sin(math.pi*swing)
                foot_rotation=around(cap[s],rotate('X',pitch));fa,fb=parts['foot_'+s];rigid_floor=transform_points(foot_rotation,rest[fa:fb])[:,2].min()
                # Right accepted stance is tucked farther under the rump.
                # Expose only its swing arc; stance and lift timing remain exact.
                outward=.075*math.sin(math.pi*swing) if s=='R' else 0.
                foot_ds[s]=translate((outward,forward,lift-rigid_floor))@foot_rotation;flap[s]=(1 if s=='L' else -1)*3.5*math.cos(wave)
        elif clip=='jump':
            air=math.sin(math.pi*p)**.65;landing=smooth(.80,1,p);body=translate((0,0,-.085*landing))@around(pivot,rotate('X',-24*air))
            upper=body;head=upper
            for s,sign in [('L',1),('R',-1)]:
                support[s]=p>=.999
                # Independent plantar flexion keeps feet dangling while the
                # torso leans. Heel volume stays rigid, including its dorsum.
                foot_pitch=-54
                foot_rotation=around(cap[s],rotate(foot_lateral[s],foot_pitch*air))
                foot_ds[s]=foot_rotation
                flap[s]=sign*(34*air+4*math.sin(wave*2)*air)
        else:
            body=around(pivot,rotate('X',-65));upper=body;head=upper@around(head_pivot,rotate('X',12))
            for s in ('L','R'):support[s]=False
        ds['pelvis']=body;ds['torso']=upper;ds['head']=head;ds['tail']=body
        # Body support is computed from actual skinned accepted surface.
        minimum=posed_vertices(ds,b0,b1)[:,2].min()
        # Jump feet now remain attached. Preserve the accepted body-to-floor
        # offset at landing so returning feet also recover their planted rest.
        floor=.032 if clip=='slide' else (float(rest[b0:b1,2].min()) if clip=='jump' else .055)
        correction=max(0.,floor-minimum)
        if correction:
            lift=translate((0,0,correction));body=lift@body;upper=lift@upper;head=lift@head
            ds.update(pelvis=body,torso=upper,head=head,tail=body)
        for s,sign in [('L',1),('R',-1)]:
            hip_pose=body
            if clip=='jump':
                # Solve attachment after body floor correction; no hidden tuck
                # and no gap for skin weights to stretch across.
                foot_ds[s]=translate(body@cap[s]-cap[s])@foot_ds[s]
            if clip=='slide':
                kick=math.sin(wave+(0 if s=='L' else math.pi))
                # A rigid foot hangs from its ankle. The former -146deg left
                # curl put its cap below its heel, then forced it to floor,
                # leaving a .31-.40m gap to the body-driven cap.
                foot_pitch=-95
                # Slide legs fan apart from buried, laterally shifted hips.
                # Rotate around world forward, rather than yawing the toes
                # away from camera or bending either shared heel volume.
                hip_pose=translate((-sign*.07,0,0))@body
                rotation=rotate('Y',sign*12)@rotate(foot_lateral[s],foot_pitch+9*kick)
                relative=around(cap[s],rotation)
                foot_ds[s]=translate(hip_pose@cap[s]-cap[s])@relative;flap[s]=sign*(25+4*math.sin(wave+(0 if s=='L' else math.pi)))
            ds['hip_'+s]=hip_pose;ds['ankle_'+s]=rigid_mix(hip_pose,foot_ds[s],.55);ds['foot_'+s]=foot_ds[s]
            flap_matrix=around(shoulders[s],rotate('Y',flap[s]))
            if clip=='slide':flap_matrix=flap_matrix@around(shoulders[s],rotate('Z',sign*3*math.sin(wave)))
            ds['flipper_'+s]=upper@flap_matrix;ds['flipper_tip_'+s]=ds['flipper_'+s]@around(mids[s],rotate('Y',sign*2.5*math.sin(wave)))
            if clip=='slide':
                # After prone-body pitch, lower each blade about world forward.
                # This sets the diagonal endpoint path; longitudinal roll below
                # independently exposes the paddle face to the chase camera.
                lower_blade=around(upper@shoulders[s],rotate('Y',-sign*18))
                ds['flipper_'+s]=lower_blade@ds['flipper_'+s]
                ds['flipper_tip_'+s]=lower_blade@ds['flipper_tip_'+s]
                # Exact-camera full-mesh study selects mirrored 60deg roll:
                # broad feathered face, restrained warm lower edge. Rotate
                # about actual skinned shoulder-to-tip so slope/wave stay put.
                fa,fb=parts['flipper_'+s];blade=posed_vertices(ds,fa,fb)
                blade_root=Vector(blade[:16].mean(0));blade_tip=Vector(blade[-1])
                blade_twist=around(blade_root,rotate((blade_tip-blade_root).normalized(),-sign*60))
                ds['flipper_'+s]=blade_twist@ds['flipper_'+s]
                ds['flipper_tip_'+s]=blade_twist@ds['flipper_tip_'+s]
        return ds,support
    frames={};metrics={};actions={};bone_samples={}
    for clip,info in CLIPS.items():
        count=round(info['duration']*FPS);action=bpy.data.actions.new(clip);rig.animation_data.action=action;actions[clip]=action
        samples=[];reports=[];pose_arrays=[]
        for frame in range(count+1):
            p=frame/count;ds,support=pose(clip,0 if info['loop'] and frame==count else p)
            globals_={name:ds[name]@rest_global[name] for name in names};locals_={}
            for name in names:
                local=globals_[parents[name]].inverted()@globals_[name] if parents[name] else globals_[name]
                locals_[name]=local
                pb=rig.pose.bones[name];pb.matrix=globals_[name];pb.rotation_mode='QUATERNION'
                pb.keyframe_insert('location',frame=frame,group=name);pb.keyframe_insert('rotation_quaternion',frame=frame,group=name);pb.keyframe_insert('scale',frame=frame,group=name)
                bpy.context.view_layer.update()
            sample={name:C@local@C.inverted() for name,local in locals_.items()};samples.append(sample)
            vertices=posed_vertices(ds);pose_arrays.append(vertices)
            report={'phase':p,'body_min_z_m':float(vertices[b0:b1,2].min()),'model_bounds_min':vertices.min(0).tolist(),'model_bounds_max':vertices.max(0).tolist(),'feet':{}}
            for s in ('L','R'):
                a,b=parts['foot_'+s];foot=vertices[a:b];sole=rest[a:b,2]<1e-5
                report['feet'][s]={'support':support[s],'min_z_m':float(foot[:,2].min()),'bounds_min_m':foot.min(0).tolist(),'bounds_max_m':foot.max(0).tolist(),'sole_z_range_m':[float(foot[sole,2].min()),float(foot[sole,2].max())],'planted_sole_max_displacement_m':float(np.max(np.linalg.norm(foot[sole]-rest[a:b][sole],axis=1))) if support[s] else None}
                heel=rest[a:b,2]<=.205
                rigid=transform_points(ds['foot_'+s],rest[a:b])[:,:3]
                report['feet'][s]['heel_rigid_max_vertex_error_m']=float(np.max(np.linalg.norm(foot[heel]-rigid[heel],axis=1)))
                report['feet'][s]['ankle_cap_separation_m']=float((ds['foot_'+s]@cap[s]-ds['hip_'+s]@cap[s]).length)
                report['feet'][s]['body_cap_containment_rays']=contained_by_closed_mesh(ds['hip_'+s]@cap[s],vertices[body_triangles])
                assert report['feet'][s]['heel_rigid_max_vertex_error_m']<2e-6,'Visible heel lost rigid volume'
                assert all(report['feet'][s]['body_cap_containment_rays']),'Ankle cap outside actual posed body'
                if clip in ('jump','slide'):assert report['feet'][s]['ankle_cap_separation_m']<2e-6,'Ankle cap detached from body'
            reports.append(report)
        samples[-1]=samples[0] if info['loop'] else samples[-1]
        loop_error=float(np.max(abs(pose_arrays[0]-pose_arrays[-1]))) if info['loop'] else None
        assert not info['loop'] or loop_error<1e-6
        if clip=='waddle':
            assert min(r['body_min_z_m'] for r in reports)>=.05
            for r in reports:
                assert any(v['support'] for v in r['feet'].values())
                for foot in r['feet'].values():
                    assert foot['min_z_m']>=-1e-6
                    if foot['support']:assert foot['planted_sole_max_displacement_m']<1e-6
        if clip=='slide':
            assert min(r['body_min_z_m'] for r in reports)>=.03
            assert min(r['model_bounds_min'][2] for r in reports)>=.01,'Prone appendage intersects floor'
            for r in reports:
                for foot in r['feet'].values():assert foot['min_z_m']>=.03,'Slide toe/web intersects floor'
        if clip=='jump':
            for r in reports:
                t=r['phase']*(2*9.4/27);ballistic=9.4*t-.5*27*t*t
                assert r['model_bounds_min'][2]*metadata['gameplay_scale']+ballistic>=-1e-5,'Jump appendage intersects gameplay floor'
        frames[clip]=samples;metrics[clip]={'frames':reports,'loop_endpoint_max_vertex_error_m':loop_error}
        action.use_fake_user=True
        for layer in action.layers:
            for strip in layer.strips:
                for slot in action.slots:
                    channelbag=strip.channelbag(slot)
                    if channelbag:
                        for curve in channelbag.fcurves:
                            for key in curve.keyframe_points:key.interpolation='LINEAR'
    rig.animation_data.action=None
    for pb in rig.pose.bones:pb.matrix_basis=Matrix.Identity(4)
    bpy.context.view_layer.update();scene.frame_start=0;scene.frame_end=36;scene.frame_set(0)
    rig['clips']='waddle,jump,slide';rig['forward_axis']='Blender +Y; glTF -Z';rig['ballistic_owner']='RunnerPlayer; animation adds no root flight arc'
    doc,binary=glb_read(BASE/'candidate.glb');original_binary=bytes(binary);prim=doc['meshes'][0]['primitives'][0];attrs={k:array(doc,binary,i) for k,i in prim['attributes'].items()}
    original_attrs=copy.deepcopy(prim['attributes']);original_indices=prim['indices'];original_images=copy.deepcopy(doc['images']);original_materials=copy.deepcopy(doc['materials'])
    spec=importlib.util.spec_from_file_location('penguin_motion_surface',ROOT/'tools/art/penguin_motion_surface.py');surface=importlib.util.module_from_spec(spec);spec.loader.exec_module(surface)
    material_revision=surface.apply_document(doc,binary)
    surface.apply_blender_material(mesh_obj,doc,binary,OUT)
    bpy.context.preferences.filepaths.save_version=0;bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source.blend'),check_existing=False)
    godot_rest=np.c_[baseline_rest[:,0],baseline_rest[:,2],-baseline_rest[:,1]].astype(np.float32);lookup={tuple(p):i for i,p in enumerate(godot_rest)}
    exported_source=[]
    for p in attrs['POSITION']:
        key=tuple(p)
        if key in lookup:exported_source.append(lookup[key])
        else:
            delta=np.linalg.norm(godot_rest-p,axis=1);i=int(delta.argmin());assert delta[i]<1e-6;exported_source.append(i)
    attrs,revised_indices,exported_source,mirrored_count=anatomy.patch_streams(attrs,array(doc,binary,original_indices),exported_source,parts)
    for name,kind in (('POSITION','VEC3'),('NORMAL','VEC3'),('TANGENT','VEC4'),('TEXCOORD_0','VEC2')):
        prim['attributes'][name]=add_accessor(doc,binary,attrs[name],kind,5126,34962)
    prim['indices']=add_accessor(doc,binary,revised_indices,'SCALAR',doc['accessors'][original_indices]['componentType'],34963)
    skinweights=weights[exported_source];joints=np.argsort(-skinweights,axis=1)[:,:4].astype('<u2');values=np.take_along_axis(skinweights,joints,axis=1).astype('<f4');values/=values.sum(1)[:,None];joints[values==0]=0
    prim['attributes']['JOINTS_0']=add_accessor(doc,binary,joints,'VEC4',5123,34962);prim['attributes']['WEIGHTS_0']=add_accessor(doc,binary,values,'VEC4',5126,34962)
    # One identity scene root contains the untouched mesh and fresh skeleton.
    doc['nodes'][0]['skin']=0;doc['nodes'][0]['name']='PenguinMotionMesh'
    container=len(doc['nodes']);doc['nodes'].append({'name':'PenguinMotionRig','children':[]})
    joint_nodes=[];rest_gltf={name:C@rest_global[name]@C.inverted() for name in names}
    for name in names:
        local=rest_gltf[parents[name]].inverted()@rest_gltf[name] if parents[name] else rest_gltf[name];loc,quat,scale=local.decompose()
        joint_nodes.append(len(doc['nodes']));doc['nodes'].append({'name':name,'translation':list(loc),'rotation':[quat.x,quat.y,quat.z,quat.w],'scale':list(scale)})
    for name,index in zip(names,joint_nodes):
        parent=container if parents[name] is None else joint_nodes[joint_index[parents[name]]]
        doc['nodes'][parent].setdefault('children',[]).append(index)
    ibm=np.array([np.array(rest_gltf[name].inverted()).T.reshape(-1) for name in names],np.float32)
    bind_accessor=add_accessor(doc,binary,ibm,'MAT4');doc['skins']=[{'name':'PenguinFreshSkin','joints':joint_nodes,'skeleton':joint_nodes[0],'inverseBindMatrices':bind_accessor}]
    # glTF skinned mesh is a scene root; implicit imported Scene owns both
    # mesh and identity armature, avoiding ignored mesh-parent transforms.
    doc['scenes'][0]['nodes']=[0,container];doc['scenes'][0]['name']='PenguinMotionCandidate'
    doc['animations']=[]
    for clip,info in CLIPS.items():
        count=len(frames[clip]);times=np.linspace(0,info['duration'],count,dtype=np.float32);time_accessor=add_accessor(doc,binary,times,'SCALAR');animation={'name':clip,'samplers':[],'channels':[],'extras':{'loop':info['loop'],'normalized_pose_clip':clip=='jump'}}
        for name,node in zip(names,joint_nodes):
            translations=[];rotations=[];scales=[];previous=None
            for sample in frames[clip]:
                location,rotation,scale=sample[name].decompose();q=np.array([rotation.x,rotation.y,rotation.z,rotation.w],np.float32)
                if previous is not None and q@previous<0:q=-q
                previous=q;translations.append(location);rotations.append(q);scales.append(scale)
            for path,data,kind in [('translation',translations,'VEC3'),('rotation',rotations,'VEC4'),('scale',scales,'VEC3')]:
                output=add_accessor(doc,binary,data,kind);sampler=len(animation['samplers']);animation['samplers'].append({'input':time_accessor,'output':output,'interpolation':'LINEAR'});animation['channels'].append({'sampler':sampler,'target':{'node':node,'path':path}})
        doc['animations'].append(animation)
    write_glb(OUT/'candidate.glb',doc,binary)
    assert bytes(binary[:len(original_binary)])==original_binary
    base_texture=doc['materials'][0]['pbrMetallicRoughness']['baseColorTexture']['index'];base_image=doc['textures'][base_texture]['source']
    for i,(before,after) in enumerate(zip(original_images,doc['images'])):
        if i!=base_image:assert before==after,'Protected normal/MR image changed'
    expected_materials=copy.deepcopy(original_materials);expected_materials[0].setdefault('extras',{})['ww_motion_surface']=material_revision
    assert doc['materials']==expected_materials,'Undeclared material change'
    # Accepted data remains literally preserved in the original buffer prefix.
    # New streams differ only at the declared mirrored left foot/flipper components.
    assert set(prim['attributes'])==set(original_attrs)|{'JOINTS_0','WEIGHTS_0'}
    out={k:metadata[k] for k in ['schema_version','material_contract','source_height_m','gameplay_height_m','gameplay_scale','author_axes','parts_vertex_ranges','surface_maps','material','atlas','reference_file','reference_sha256']}
    out.update(gate='rear-motion-v1',unrigged=False,animation_ready=True,production_ready=False,visual_approval='pending actual-game animation review',glb_sha256=sha(OUT/'candidate.glb'),source_sha256=sha(OUT/'source.blend'),builder_sha256=sha(__file__),rest_reference={'path':str((BASE/'candidate.glb').relative_to(ROOT)),'glb_sha256':REST_SHA},rig={'joints':names,'parents':parents,'root_joint':'motion_root','armature_node':'PenguinMotionRig','mesh_node':'PenguinMotionMesh','forward_axis':'Godot -Z / Blender +Y','up_axis':'Godot +Y / Blender +Z','fresh_design':True,'legacy_skeleton_reused':False},clips=CLIPS,triangles=14720,triangle_budget=15000,surfaces=1,vertices=len(attrs['POSITION']),source_vertices=len(rest),root_transform='identity',motion_contract={'waddle_roll_degrees':[-20,20],'rest_forward_lean_degrees':11,'waddle_cycle_seconds':1.2,'waddle_contact':'In-place clip. Planted soles remain fixed in avatar-local floor frame; gameplay forward motion remains external. Compact swing lift/fore-aft arc.','jump':'Normalized takeoff0/earlyair.2/apex.5/descent.8/landing1; no input-delay anticipation or root ballistic motion. Map to actual2*9.4/27=.696296s gameplay air.','slide':'Prone loop, additional65deg forward pitch over accepted11deg rest; actual belly-supported floor; independent alternating feet and subtle flippers; entry/exit external blend.','phase_markers':{'jump':{'takeoff':0,'early_air':.2,'apex':.5,'descent':.8,'landing':1}},'playback_scale_owner':'Runtime adapter; no gameplay speed or collider changes'},rendered_frames=0)
    out['material_revision']=material_revision
    out['anatomy_revision']=anatomy_revision
    out['anatomical_foot_direction']=metadata['anatomical_foot_direction']
    out['surface_maps']['base_color']['sha256']=material_revision['base_color_after_sha256']
    out['material']['specular']=material_revision['specular']
    out['motion_contract']['articulation_revision']={
        'reason':'User requested shared mirrored feet and flippers. Exact mirrored right anatomy replaces left image-fit asymmetry; both feet use matching anatomical articulation, rigid heels and attached ankles, while limbs retain independent motion.',
        'feet_pitch_axes':'Per-foot anatomical lateral axis from accepted forward landmarks.',
        'jump_additional_forward_pitch_degrees':24,
        'jump_head_counter_pitch_degrees':0,
        'jump_left_air_tuck_author_m':[0,0,0],
        'jump_foot_pitch_degrees':{'L':-54,'R':-54},
        'jump_flipper_spread_degrees':34,'jump_flipper_wave_degrees':4,
        'slide_left_forward_tuck_author_m':0,
        'slide_foot_pitch_degrees':{'L':-95,'R':-95},
        'slide_foot_abduction_author_m':{'L':-.07,'R':.07},
        'slide_foot_attachment_lift_author_m':0,
        'slide_foot_fan_world_forward_degrees':{'L':12,'R':-12},
        'slide_foot_spread_revision':'Symmetric slide-only whole hip/ankle/foot-chain offset. World Blender +Y fan rotation exposes outward web direction; no vertical lift or foot scaling. Caps remain inside actual posed body, with outer-toe clearance through opposite kicks. Waddle/jump curves unchanged.',
        'heel_weight_contract':'Rigid foot through sourceZ .205m; ankle blend .205-.250m and cap blend .218-.278m. Jump/slide rigid-foot cap coincides with attached hip-chain cap; slide caps shift laterally inside body without stretching heel or ankle.',
        'slide_flipper_world_forward_down_degrees':18,
        'slide_flipper_long_axis_twist_degrees':{'L':-60,'R':60},
        'slide_flipper_twist_axis':'Actual posed shoulder centroid to tip; endpoint/slope/paddle paths preserved. Fixed-camera full-mesh UV projection selects broad dark feather face with warm lower edge.',
        'waddle_right_swing_outward_arc_author_m':.075,
        'preserved':'Waddle body/stance/phase curves, body/head/right-foot/right-flipper/tail rest geometry and slide body/flipper curves. Left foot and flipper now exact mirrored right anatomy and donor UVs; no old left-foot-only angle or tuck compensation.',
        'floor_checks':'All sampled slide vertices >=.01m and foot vertices >=.03m; jump adds authoritative ballistic height only for verification.'}
    (OUT/'metadata.json').write_text(json.dumps(out,indent=2)+'\n')
    proof={'candidate_sha256':out['glb_sha256'],'source_sha256':out['source_sha256'],'rest_sha256':REST_SHA,'protected_rest_components_exact':True,'anatomy_revision':anatomy_revision,'mirrored_export_vertices':mirrored_count,'original_binary_payload_exact':True,'normal_metallic_roughness_maps_exact':True,'material_revision':material_revision,'skin_influences_max':int(np.count_nonzero(values>0,axis=1).max()),'weight_sum_max_error':float(abs(values.sum(1)-1).max()),'joint_count':len(names),'clips':metrics,'note':'Source skin math only. No engine frames or final motion appearance approval.'}
    (OUT/'motion-verification.json').write_text(json.dumps(proof,indent=2)+'\n');np.savez_compressed(OUT/'source-skin.npz',positions=rest,weights=weights,source_vertex_for_export=np.array(exported_source),joint_names=np.array(names))
    print('MOTION_READY '+json.dumps({'glb_sha256':out['glb_sha256'],'clips':CLIPS,'joints':len(names),'bytes':(OUT/'candidate.glb').stat().st_size}))
if __name__=='__main__':main()
