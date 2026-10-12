#!/usr/bin/env python3
"""UV/PBR surface authoring over exact accepted V9 geometry; Blender 5.2, no renders.

blender --background --factory-startup --python tools/art/build_penguin_rear_surface.py
Atlas pixels are deterministic surface pigment/relief, never baked scene lighting.
"""
from __future__ import annotations
import hashlib, json, math, struct, zlib
from pathlib import Path
import bpy
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'art_src/characters/penguin_rear_blockout_v1'
OUT=ROOT/'art_src/characters/penguin_rear_surface_v1'
N=2048
BASE_SHA='94f30dc898acb8abb85230ddad569e8e9530e8fca9bfe84a05a2ac8a34732fd1'
RECTS={
 'continuous_body_head':(16,16,1264,2032),
 'flipper_L':(1296,1040,1632,2032),'flipper_R':(1664,1040,2000,2032),
 'foot_L':(1296,528,1632,1008),'foot_R':(1664,528,2000,1008),
 'tail_top':(1296,272,1632,496),'tail_bottom':(1664,272,2000,496),
 'tail_edge':(1296,16,2000,240)}

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
def png(path, data):
    a=np.asarray(data,dtype=np.uint8); h,w,c=a.shape
    def chunk(kind,b):return struct.pack('>I',len(b))+kind+b+struct.pack('>I',zlib.crc32(kind+b)&0xffffffff)
    raw=b''.join(b'\0'+a[y].tobytes() for y in range(h-1,-1,-1))
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2 if c==3 else 6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,7))+chunk(b'IEND',b''))

def glb_arrays(path):
    raw=path.read_bytes(); off=12; chunks={}
    while off<len(raw):
        length,kind=struct.unpack_from('<II',raw,off);chunks[kind]=raw[off+8:off+8+length];off+=8+length
    doc=json.loads(chunks[0x4e4f534a]); binary=chunks[0x004e4942]
    def accessor(i):
        a=doc['accessors'][i];v=doc['bufferViews'][a['bufferView']];dt=np.dtype({5126:'<f4',5125:'<u4',5123:'<u2'}[a['componentType']]);w={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4}[a['type']]
        return np.ndarray((a['count'],w),dtype=dt,buffer=binary,offset=v.get('byteOffset',0)+a.get('byteOffset',0),strides=(v.get('byteStride',dt.itemsize*w),dt.itemsize)).copy()
    p=doc['meshes'][0]['primitives'][0]
    return doc,binary,{k:accessor(i) for k,i in p['attributes'].items()},accessor(p['indices']).reshape(-1,3)

def triangle_identity(attrs, indices):
    # Canonical cyclic corner sequence: seam duplication and exporter reordering
    # are irrelevant, but winding, triangle diagonals and normals must be exact.
    rows=[]
    for tri in indices:
        corner=[np.r_[attrs['POSITION'][i],attrs['NORMAL'][i]].astype('<f4').tobytes() for i in tri]
        rows.append(min(b''.join(corner[k:]+corner[:k]) for k in range(3)))
    return hashlib.sha256(b''.join(sorted(rows))).hexdigest()

def uv_layout(mesh, metadata, config):
    uv=mesh.uv_layers.new(name='RearSurfaceAtlas')
    local={};part_of={};caps=set()
    def rings(name,count,segments,values,seam):
        start,end=metadata['parts_vertex_ranges'][name]
        for row in range(count):
            first=start+row*segments+(1 if row else 0)
            for i in range(segments):local[first+i]=(((i-seam)%segments)/segments,values[row]);part_of[first+i]=name
        low=start+segments;high=end-1
        local[low]=(.5,values[0]);local[high]=(.5,values[-1]);caps.update((low,high));part_of[low]=part_of[high]=name
    rings('continuous_body_head',config['body_rings']-1,config['body_segments'],[.5-.5*math.cos(math.pi*(i+1)/config['body_rings']) for i in range(config['body_rings']-1)],config['body_segments']//4)
    for name in ('flipper_L','flipper_R'):
        ts=sorted(set([i/config['flipper_rings'] for i in range(config['flipper_rings'])]+[.97,.989]))
        rings(name,len(ts),config['flipper_cross_segments'],[1-t for t in ts],config['flipper_cross_segments']//4)
    for name in ('foot_L','foot_R'):
        count=config['foot_shape']['height_rings'];rings(name,count,config['foot_shape']['ring_segments'],[.5-.5*math.cos(math.pi*i/count) for i in range(count)],config['foot_shape']['ring_segments']//2)
    # Cap UV v differs from adjacent ring; avoid zero-area pole triangles.
    for name in ('continuous_body_head','foot_L','foot_R'):
        start,end=metadata['parts_vertex_ranges'][name];segments=config['body_segments'] if name=='continuous_body_head' else config['foot_shape']['ring_segments']
        local[start+segments]=(.5,-.008 if name.startswith('foot') else 0);local[end-1]=(.5,1)
    for name in ('flipper_L','flipper_R'):
        start,end=metadata['parts_vertex_ranges'][name];local[start+config['flipper_cross_segments']]=(.5,1.002);local[end-1]=(.5,0)
    tail_start=metadata['parts_vertex_ranges']['short_tail_fan'][0]
    boundary=[(0,c) for c in range(17)]+[(r,16) for r in range(1,9)]+[(8,c) for c in range(15,-1,-1)]+[(r,0) for r in range(7,0,-1)]
    bindex={r*17+c:i/len(boundary) for i,(r,c) in enumerate(boundary)}
    for poly in mesh.polygons:
        ids=list(poly.vertices)
        if ids[0]>=tail_start:
            layers=[(i-tail_start)//153 for i in ids]
            if len(set(layers))==1:
                name='tail_top' if layers[0]==0 else 'tail_bottom';coords=[((i-tail_start)%17/16,1-((i-tail_start)%153//17)/8) for i in ids]
            else:name='tail_edge';coords=[(bindex[(i-tail_start)%153],float((i-tail_start)//153)) for i in ids]
        else:
            name=part_of[ids[0]];coords=[local[i] for i in ids]
        us=[u for i,(u,v) in zip(ids,coords) if i not in caps]
        crossing=max(us)-min(us)>.5 if us else False
        if crossing:coords=[(u+1 if u<.5 and i not in caps else u,v) for i,(u,v) in zip(ids,coords)]
        noncap=[u for i,(u,v) in zip(ids,coords) if i not in caps]
        coords=[(sum(noncap)/len(noncap),v) if i in caps else (u,v) for i,(u,v) in zip(ids,coords)]
        x0,y0,x1,y1=RECTS[name]
        for li,(u,v) in zip(poly.loop_indices,coords):uv.data[li].uv=((x0+u*(x1-x0))/N,(y0+v*(y1-y0))/N)
    return uv

def raster_palette(mesh,uv):
    color=np.zeros((N,N,3),np.float32);mask=np.zeros((N,N),bool)
    source=mesh.color_attributes['COLOR_0']
    for tri in mesh.loop_triangles:
        xy=np.array([uv.data[i].uv for i in tri.loops],np.float64)*N
        lo=np.floor(xy.min(0)).astype(int).clip(0,N-1);hi=np.ceil(xy.max(0)).astype(int).clip(0,N-1)
        xx,yy=np.meshgrid(np.arange(lo[0],hi[0]+1)+.5,np.arange(lo[1],hi[1]+1)+.5)
        a,b,c=xy;det=(b[1]-c[1])*(a[0]-c[0])+(c[0]-b[0])*(a[1]-c[1])
        if abs(det)<1e-9:continue
        w0=((b[1]-c[1])*(xx-c[0])+(c[0]-b[0])*(yy-c[1]))/det
        w1=((c[1]-a[1])*(xx-c[0])+(a[0]-c[0])*(yy-c[1]))/det;w2=1-w0-w1
        valid=(w0>=-1e-6)&(w1>=-1e-6)&(w2>=-1e-6)
        rgb=np.array([source.data[i].color[:3] for i in tri.vertices]);out=w0[...,None]*rgb[0]+w1[...,None]*rgb[1]+w2[...,None]*rgb[2]
        section=color[lo[1]:hi[1]+1,lo[0]:hi[0]+1];section[valid]=out[valid];mask[lo[1]:hi[1]+1,lo[0]:hi[0]+1]|=valid
    # Warm neutral charcoal, no illumination baked in. Gold/ivory/orange retain hue.
    dark=(color.max(2)<.12)&(color[...,2]>color[...,0])&mask
    luma=color@np.array([.2126,.7152,.0722],np.float32)
    neutral=np.repeat(luma[...,None],3,axis=2)*np.array([1.02,1,.985],np.float32)
    color[dark]=(color[dark]*.35+neutral[dark]*.65)*1.12
    return color,mask

def feather_field(w,h,kind,seed):
    rng=np.random.default_rng(seed);height=np.zeros((h,w),np.float32);tone=np.ones((h,w),np.float32)
    def feather(cx,cy,ww,ll,angle,strength):
        radius=int(max(ww,ll)*1.2);x0=max(0,int(cx-radius));x1=min(w,int(cx+radius+1));y0=max(0,int(cy-radius));y1=min(h,int(cy+radius+1))
        if x1<=x0 or y1<=y0:return
        xx,yy=np.meshgrid(np.arange(x0,x1)-cx,np.arange(y0,y1)-cy);ca,sa=math.cos(angle),math.sin(angle)
        dx=xx*ca+yy*sa;dy=-xx*sa+yy*ca
        t=(dy/ll)+.5;inside=(t>0)&(t<1)
        # Open tapered sides; no closed outline or regular fish-scale cells.
        width=ww*(.24+.76*np.sin(np.pi*np.clip(t,0,1))**.6)
        q=np.abs(dx)/np.maximum(width,.001);leaf=inside&(q<1)
        body=np.maximum(0,1-q*q)*np.sin(np.pi*np.clip(t,0,1))
        ridge=np.exp(-((q-.87)/.08)**2)*inside*(1-np.clip((t-.58)/.35,0,1))
        shaft=np.exp(-(dx/(ww*.11+1))**2)*np.sin(np.pi*np.clip(t,0,1))*.12
        relief=(body*.65+shaft-ridge*.2)*leaf*strength
        region=height[y0:y1,x0:x1];region[:]=np.maximum(region,relief)
        tint=1+body*.023-ridge*.16*strength/.00055
        region=tone[y0:y1,x0:x1];region[leaf]=region[leaf]*.55+tint[leaf]*.45
    if kind=='body':
        # Jittered positions and length hierarchy, not uniform closed rows.
        for row in range(33):
            v=(row+.5)/33
            scale=.58+.64*(1-v)
            for column in range(31):
                u=(column+.5+rng.uniform(-.45,.45))/31;vv=v+rng.uniform(-.012,.012)
                angle=rng.uniform(-.25,.25)+.15*math.sin(math.tau*u)
                feather(u*w,vv*h,w*rng.uniform(.011,.019)*scale,h*rng.uniform(.038,.060)*scale,angle,.00055*(.45+.55*(1-v)))
    elif kind=='flipper':
        for row in range(5):
            for col in range(13):
                feather((col+.5+rng.uniform(-.25,.25))*w/13,(row+.4+rng.uniform(-.15,.15))*h/5,w*rng.uniform(.025,.040),h*rng.uniform(.22,.34),rng.uniform(-.055,.055),.00055)
    elif kind=='tail':
        for col in range(9):
            u=(col+.5)/9
            for row in range(2):feather(u*w,(row+.5)*h/2,w*.062,h*.62,(u-.5)*.18,.00075)
    else:
        yy,xx=np.mgrid[0:h,0:w];v=yy/h;u=xx/w
        # Shallow horizontal scutes, never posterior vertical false toe creases.
        line=np.exp(-((np.sin(math.tau*(v*7+.07*np.sin(u*math.tau*4))))/.17)**2)
        envelope=np.clip((v-.08)/.15,0,1)*np.clip((.86-v)/.2,0,1)
        height=-line*.00016*envelope;tone=1-line*.035*envelope
    return height,tone

def maps(mesh,uv):
    color,covered=raster_palette(mesh,uv);normal=np.zeros((N,N,3),np.float32);normal[...,2]=1
    rough=np.full((N,N),.88,np.float32);height_diagnostic=np.zeros((N,N),np.float32)
    for i,(name,(x0,y0,x1,y1)) in enumerate(RECTS.items()):
        w,h=x1-x0,y1-y0;kind='body' if name=='continuous_body_head' else 'flipper' if name.startswith('flipper') else 'foot' if name.startswith('foot') else 'tail'
        ht,tone=feather_field(w,h,kind,417+i*103)
        color[y0:y1,x0:x1]*=tone[...,None];height_diagnostic[y0:y1,x0:x1]=ht
        meter_u,meter_v={'body':(2.7,1.69),'flipper':(.48,.86),'tail':(.28,.32),'foot':(.9,.285)}[kind]
        dy,dx=np.gradient(ht);nn=np.stack((-dx/(meter_u/w),-dy/(meter_v/h),np.ones_like(ht)),axis=2);nn/=np.linalg.norm(nn,axis=2,keepdims=True)
        normal[y0:y1,x0:x1]=nn
        rough[y0:y1,x0:x1]=({'body':.87,'flipper':.86,'tail':.90,'foot':.76}[kind]+np.clip((1-tone)*.22,-.025,.035))
    # Extrude true texels16px around each island, including cap gaps, for mips.
    packed=np.dstack((color,normal,rough));valid=covered.copy()
    for _ in range(16):
        total=np.zeros_like(packed);count=np.zeros((N,N),np.float32)
        for axis,shift in ((0,-1),(0,1),(1,-1),(1,1)):
            mm=np.roll(valid,shift,axis);total+=np.roll(packed,shift,axis)*mm[...,None];count+=mm
        fill=(~valid)&(count>0);packed[fill]=total[fill]/count[fill,None];valid|=fill
    color=packed[:,:,:3];normal=packed[:,:,3:6];rough=packed[:,:,6]
    srgb=np.where(color<=.0031308,color*12.92,1.055*np.maximum(color,0)**(1/2.4)-.055)
    base=np.uint8(np.clip(srgb*255+.5,0,255));norm=np.uint8(np.clip((normal*.5+.5)*255+.5,0,255))
    mr=np.zeros((N,N,3),np.uint8);mr[:,:,0]=255;mr[:,:,1]=np.uint8(np.clip(rough*255+.5,0,255))
    png(OUT/'base-color.png',base);png(OUT/'normal.png',norm);png(OUT/'metallic-roughness.png',mr)
    png(OUT/'relief-diagnostic.png',np.repeat(np.uint8(np.clip(height_diagnostic/.0008*200+28,0,255))[...,None],3,axis=2))
    return {'covered_texels':int(covered.sum()),'padding_pixels':16,'normal_convention':'OpenGL tangent +Y; image UV origin bottom-left','color_adjustment':'Charcoal65% neutralized,12% linear value lift; existing ivory/gold/orange hue retained','roughness_range':[float(rough[covered].min()),float(rough[covered].max())]}

def main():
    assert tuple(bpy.app.version[:3])==(5,2,0)
    assert sha(SOURCE/'candidate.glb')==BASE_SHA
    OUT.mkdir(parents=True,exist_ok=True)
    metadata=json.loads((SOURCE/'metadata.json').read_text());config=json.loads((SOURCE/'config.json').read_text())
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'source.blend'))
    obj=bpy.data.objects['RearBlockout'];mesh=obj.data;mesh.calc_loop_triangles()
    before=np.array([v.co[:] for v in mesh.vertices],np.float32);source_triangles=np.array([t.vertices[:] for t in mesh.loop_triangles])
    uv=uv_layout(mesh,metadata,config);diagnostic=maps(mesh,uv)
    for attr in list(mesh.color_attributes):mesh.color_attributes.remove(attr)
    mesh.materials.clear();mat=bpy.data.materials.new('RearSurfaceMattePBR');mat.use_nodes=True;nodes=mat.node_tree.nodes;links=mat.node_tree.links;p=nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(1,1,1,1);p.inputs['Metallic'].default_value=1;p.inputs['Roughness'].default_value=1
    textures={}
    for slot,file,space in [('base_color','base-color.png','sRGB'),('normal','normal.png','Non-Color'),('metallic_roughness','metallic-roughness.png','Non-Color')]:
        image=bpy.data.images.load(str(OUT/file));image.colorspace_settings.name=space;image.pack();node=nodes.new('ShaderNodeTexImage');node.image=image;node.interpolation='Linear';node.extension='EXTEND';node.label=slot;textures[slot]=node
    links.new(textures['base_color'].outputs['Color'],p.inputs['Base Color'])
    normal=nodes.new('ShaderNodeNormalMap');normal.space='TANGENT';normal.uv_map=uv.name;normal.inputs['Strength'].default_value=.65;links.new(textures['normal'].outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],p.inputs['Normal'])
    split=nodes.new('ShaderNodeSeparateColor');split.mode='RGB';links.new(textures['metallic_roughness'].outputs['Color'],split.inputs['Color']);links.new(split.outputs['Green'],p.inputs['Roughness']);links.new(split.outputs['Blue'],p.inputs['Metallic'])
    mesh.materials.append(mat);obj['gate']='rear-surface-v1'
    assert np.array_equal(before,np.array([v.co[:] for v in mesh.vertices],np.float32));mesh.calc_loop_triangles();assert np.array_equal(source_triangles,np.array([t.vertices[:] for t in mesh.loop_triangles]))
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source.blend'),check_existing=False)
    bpy.ops.export_scene.gltf(filepath=str(OUT/'candidate.glb'),check_existing=False,export_format='GLB',use_selection=True,export_yup=True,export_apply=False,export_materials='EXPORT',export_normals=True,export_tangents=True,export_texcoords=True,export_vertex_color='NONE',export_all_vertex_colors=False,export_skins=False,export_animations=False,export_morph=False,export_cameras=False,export_lights=False,export_extras=False)
    old,_,oa,oi=glb_arrays(SOURCE/'candidate.glb');doc,binary,attrs,indices=glb_arrays(OUT/'candidate.glb')
    old_id,new_id=triangle_identity(oa,oi),triangle_identity(attrs,indices)
    assert old_id==new_id,'Triangle POSITION/NORMAL identity changed'
    assert len(indices)==14720 and set(attrs)=={'POSITION','NORMAL','TANGENT','TEXCOORD_0'}
    material=doc['materials'][0];pbr=material['pbrMetallicRoughness'];surface_maps={}
    for slot,index in [('base_color',pbr['baseColorTexture']['index']),('normal',material['normalTexture']['index']),('metallic_roughness',pbr['metallicRoughnessTexture']['index'])]:
        ii=doc['textures'][index]['source'];im=doc['images'][ii];view=doc['bufferViews'][im['bufferView']];payload=binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
        assert payload.startswith(b'\x89PNG\r\n\x1a\n') and struct.unpack_from('>II',payload,16)==(N,N)
        surface_maps[slot]={'image_index':ii,'sha256':hashlib.sha256(payload).hexdigest(),'width':N,'height':N,'color_space':'srgb' if slot=='base_color' else 'linear','channels':'RGB color' if slot=='base_color' else 'RGB tangent-space XYZ' if slot=='normal' else 'R unused255; G roughness; B metallic0'}
    out={k:metadata[k] for k in ['source_height_m','gameplay_height_m','gameplay_scale','author_axes','bounds_author_m','root_transform','pose','parts_vertex_ranges','anatomical_foot_direction']}
    out.update({'schema_version':1,'gate':'rear-surface-v1','material_contract':'rear-surface-pbr-v1','unrigged':True,'production_ready':False,'animation_ready':False,'visual_approval':'pending actual-game surface review','glb_sha256':sha(OUT/'candidate.glb'),'source_sha256':sha(OUT/'source.blend'),'builder_sha256':sha(__file__),'reference_file':'art_src/characters/reference_boards/penguin-gameplay-v2-20261011/animatics-strong-lean/waddle-frame-04.png','geometry_reference':{'path':str((SOURCE/'candidate.glb').relative_to(ROOT)),'glb_sha256':BASE_SHA},'geometry_identity':{'method':'Exact float32 POSITION+NORMAL per triangle, cyclic orientation canonicalized; UV seam vertex duplication allowed','sha256':new_id,'source_sha256':old_id,'passed':True},'triangles':len(indices),'triangle_budget':15000,'vertices':len(attrs['POSITION']),'source_vertices':len(before),'surfaces':1,'surface_maps':surface_maps,'material':{'name':mat.name,'base_color_factor':[1,1,1,1],'effective_metallic':0,'metallic_factor':pbr.get('metallicFactor',1),'roughness_factor':pbr.get('roughnessFactor',1),'normal_scale':material['normalTexture'].get('scale',1),'color_owner':'baseColorTexture only; no vertex colors'},'atlas':{'size':N,'rectangles':RECTS,**diagnostic},'rendered_frames':0,'deferred':['rig and animation','front face/podium authoring','runtime promotion']})
    out['reference_sha256']=sha(ROOT/out['reference_file'])
    (OUT/'metadata.json').write_text(json.dumps(out,indent=2)+'\n')
    print('SURFACE_METADATA '+json.dumps(out,sort_keys=True))

if __name__=='__main__':main()
