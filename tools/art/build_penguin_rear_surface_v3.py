#!/usr/bin/env python3
"""Pronounced tail fan and reference-fitted flippers over accepted b21 body/feet; Blender5.2, no renders.

blender --background --factory-startup --python tools/art/build_penguin_rear_surface_v3.py
Atlas pixels are deterministic surface pigment/relief, never baked scene lighting.
"""
from __future__ import annotations
import hashlib, json, math, struct, zlib
from pathlib import Path
import bpy
import bmesh
import numpy as np

ROOT=Path(__file__).resolve().parents[2]
SOURCE=ROOT/'art_src/characters/penguin_rear_blockout_v1'
OUT=ROOT/'art_src/characters/penguin_rear_surface_v3'
BASELINE=ROOT/'art_src/characters/penguin_rear_surface_v1'
BASELINE_SHA='b21ca5327a7798b31b1b5b7aa098a4452c623db2c95044244aa490fb72fc7484'
N=1024
PADDING=8
BASE_SHA='94f30dc898acb8abb85230ddad569e8e9530e8fca9bfe84a05a2ac8a34732fd1'
RECTS={
 'continuous_body_head':(16,16,1264,2032),
 'flipper_L':(1296,1040,1632,2032),'flipper_R':(1664,1040,2000,2032),
 'foot_L':(1296,528,1632,1008),'foot_R':(1664,528,2000,1008),
 'tail_top':(1296,272,1632,496),'tail_bottom':(1664,272,2000,496),
 'tail_edge':(1296,16,2000,240)}
RECTS={name:tuple(value//2 for value in rect) for name,rect in RECTS.items()}

def sha(p):return hashlib.sha256(Path(p).read_bytes()).hexdigest()
TAIL_ROWS=np.array([0,.18,.34,.50,.64,.75,.85,.93,1.0])
_TAIL_BODY_UV=None
_TAIL_ART_CACHE=None
def tail_half_width(t):
    smooth=lambda a,b,x: np.clip((x-a)/(b-a),0,1)**2*(3-2*np.clip((x-a)/(b-a),0,1))
    return .075+.073*smooth(.25,.76,t)-.083*smooth(.92,1,t)
def tail_height(t,u):return .47-.354*t+u*u*(.025*(1-t)+.035*t**4)
def png(path, data):
    a=np.asarray(data,dtype=np.uint8); h,w,c=a.shape
    def chunk(kind,b):return struct.pack('>I',len(b))+kind+b+struct.pack('>I',zlib.crc32(kind+b)&0xffffffff)
    # Lossless adaptive PNG scanline filters keep1024 maps within Web budget.
    # Only encoding changes; decoded8-bit RGB pixels remain exact.
    rows=[];previous=np.zeros(w*c,np.int16)
    for y in range(h-1,-1,-1):
        row=a[y].reshape(-1).astype(np.int16);left=np.r_[np.zeros(c,np.int16),row[:-c]];upper_left=np.r_[np.zeros(c,np.int16),previous[:-c]]
        estimate=left+previous-upper_left;dl=np.abs(estimate-left);du=np.abs(estimate-previous);dul=np.abs(estimate-upper_left)
        paeth=np.where((dl<=du)&(dl<=dul),left,np.where(du<=dul,previous,upper_left))
        filtered=[row,row-left,row-previous,row-(left+previous)//2,row-paeth]
        residual=[np.uint8(values%256) for values in filtered]
        scores=[np.abs(values.view(np.int8).astype(np.int16)).sum() for values in residual];kind=int(np.argmin(scores))
        rows.append(bytes([kind])+residual[kind].tobytes());previous=row
    raw=b''.join(rows)
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',w,h,8,2 if c==3 else 6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b''))

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
    neutral=np.repeat(luma[...,None],3,axis=2)*(np.array([1.28,1,.76],np.float32)*((np.array([1.10,1,.92])@np.array([.2126,.7152,.0722]))/(np.array([1.28,1,.76])@np.array([.2126,.7152,.0722]))))
    color[dark]=(color[dark]*.05+neutral[dark]*.95)*1.38
    return color,mask

_ART_CACHE=None

def blur_periodic(a,radius,passes=2):
    """Source-space low pass removes fine generated barb/shaft noise."""
    a=a.astype(np.float32)
    for _ in range(passes):
        for axis in (0,1):
            pad=[(0,0)]*a.ndim;pad[axis]=(radius,radius)
            padded=np.pad(a,pad,mode='wrap');cs=np.cumsum(padded,axis=axis,dtype=np.float64)
            z=list(cs.shape);z[axis]=1;cs=np.concatenate((np.zeros(z),cs),axis=axis)
            lo=[slice(None)]*a.ndim;hi=lo.copy();lo[axis]=slice(0,a.shape[axis]);hi[axis]=slice(2*radius+1,None)
            a=((cs[tuple(hi)]-cs[tuple(lo)])/(2*radius+1)).astype(np.float32)
    return a

def authored_source():
    global _ART_CACHE
    if _ART_CACHE is not None:return _ART_CACHE
    path=OUT/'material_sources/feather-source-v2.png'
    im=bpy.data.images.load(str(path),check_existing=False);im.colorspace_settings.name='Non-Color'
    w,h=im.size;raw=np.empty(w*h*4,np.float32);im.pixels.foreach_get(raw)
    # Blender pixels begin at bottom left; atlas arrays share that convention.
    # Positive source v and chart v both point up: generated downward tips stay down.
    raw=raw.reshape(h,w,4)[:,:,:3];gray=raw@np.array([.2126,.7152,.0722],np.float32)
    raw_percentiles=np.percentile(gray,[5,50,95]).tolist()
    assert .14<raw_percentiles[0]<.20 and .18<raw_percentiles[1]<.30,'Unexpected source color transfer for measured v2 PNG'
    # Narrow edge reconciliation makes periodic sampling continuous without
    # mirroring feather direction. Only the outer16 source pixels are blended.
    periodic=gray.copy()
    for axis in (0,1):
        for i in range(16):
            first=[slice(None)]*2;last=first.copy();first[axis]=i;last[axis]=-1-i
            first,last=tuple(first),tuple(last);mix=(1-i/16)*.5
            av,bv=periodic[first].copy(),periodic[last].copy()
            periodic[first]=av*(1-mix)+bv*mix;periodic[last]=bv*(1-mix)+av*mix
    pigment=blur_periodic(periodic,3)
    relief=blur_periodic(periodic,7)
    bpy.data.images.remove(im)
    _ART_CACHE=(pigment,relief,{'path':str(path.relative_to(ROOT)),'sha256':sha(path),'prompt_path':str((path.parent/'feather-source-v2-prompt.txt').relative_to(ROOT)),'prompt_sha256':sha(path.parent/'feather-source-v2-prompt.txt'),'generator':'OpenAI built-in ImageGen','original_path':'/Users/ninja/.codex/generated_images/01a12d09-d5ea-7952-8a60-3670fc421c94/exec-630cf216-24e4-48cf-82e1-17068bd9e3d1.png','dimensions':[w,h],'raw_luma_p5_p50_p95':raw_percentiles,'pigment_luma_p5_p50_p95':np.percentile(pigment,[5,50,95]).tolist(),'relief_luma_p5_p50_p95':np.percentile(relief,[5,50,95]).tolist(),'orientation':'Source PNG tips point down. Blender pixel array is bottom-left; all chart/source v derivatives positive. Atlas PNG row flip is serialization only.'})
    return _ART_CACHE

def periodic_sample(a,u,v):
    h,w=a.shape;x=(u%1)*w-.5;y=(v%1)*h-.5
    ix=np.floor(x).astype(int);iy=np.floor(y).astype(int);fx=x-ix;fy=y-iy
    return ((1-fy)*((1-fx)*a[iy%h,ix%w]+fx*a[iy%h,(ix+1)%w])+fy*((1-fx)*a[(iy+1)%h,ix%w]+fx*a[(iy+1)%h,(ix+1)%w])).astype(np.float32)

def body_art_coords(u,v):
    frequency=2.3+1.6*v
    return ((u-.5)*frequency+.53+.026*np.sin(math.tau*(v*1.4+.15)),
            1.75*v+.8*v*v+.17+.012*np.sin(math.tau*u*2))

def tail_chart_coordinates(w,h,edge=False):
    """Shared top/bottom/edge fan coordinates; same physical region across seams."""
    yy,xx=np.mgrid[0:h,0:w];v=(yy+.5)/h;u=2*(xx+.5)/w-1;t=np.interp(1-v,np.linspace(0,1,9),TAIL_ROWS)
    if edge:
        boundary=np.array([(0,c) for c in range(17)]+[(r,16) for r in range(1,9)]+[(8,c) for c in range(15,-1,-1)]+[(r,0) for r in range(7,0,-1)],float)
        boundary=np.vstack((boundary,boundary[0]));along=(xx+.5)/w*(len(boundary)-1)
        t=np.interp(np.interp(along,np.arange(len(boundary)),boundary[:,0])/8,np.linspace(0,1,9),TAIL_ROWS)
        u=np.interp(along,np.arange(len(boundary)),boundary[:,1])/8-1
    return u,t

def tail_body_coords(w,h,edge=False):
    """Barycentric closest-rump UV field: identical feather phase across emergence."""
    u,t=tail_chart_coordinates(w,h,edge)
    assert _TAIL_BODY_UV is not None
    fr=np.interp(t,TAIL_ROWS,np.arange(9));fc=np.clip((u+1)*8,0,16)
    r=np.minimum(fr.astype(int),7);c=np.minimum(fc.astype(int),15);dr=fr-r;dc=fc-c
    field=((1-dr)[...,None]*((1-dc)[...,None]*_TAIL_BODY_UV[r,c]+dc[...,None]*_TAIL_BODY_UV[r,c+1])+
           dr[...,None]*((1-dc)[...,None]*_TAIL_BODY_UV[r+1,c]+dc[...,None]*_TAIL_BODY_UV[r+1,c+1]))
    return field[...,0],field[...,1]

def feather_field(w,h,kind,seed):
    yy,xx=np.mgrid[0:h,0:w];v=(yy+.5)/h;u=(xx+.5)/w
    if kind=='foot':
        # Keep original foot maps byte-identical: posterior heel stays smooth.
        v=yy/h;u=xx/w
        line=np.exp(-((np.sin(math.tau*(v*7+.07*np.sin(u*math.tau*4))))/.17)**2)
        envelope=np.clip((v-.08)/.15,0,1)*np.clip((.86-v)/.2,0,1)
        return -line*.00016*envelope,1-line*.035*envelope
    pigment,relief,art_info=authored_source()
    if kind=='body':
        su,sv=body_art_coords(u,v)
        amplitude=.0020
    elif kind=='flipper':
        su=.08+u*.78+.025*np.sin(math.tau*v*.65)
        sv=.21+.56*v+.38*v*v+.013*np.sin(math.tau*u)
        amplitude=.0014
    else:
        # Same projected feather phase as adjoining rump, no dark border paint.
        bu,bv=tail_body_coords(w,h,kind=='tail_edge');su,sv=body_art_coords(bu,bv)
        amplitude=.0020
    art=periodic_sample(pigment,su,sv)
    # V2 source is deliberately shallow. Normalize measured face spread,
    # preserving its mean instead of copying v1's stronger sculpted cavities.
    lo,med,hi=art_info['pigment_luma_p5_p50_p95']
    gain=.40/(hi-lo)
    tone=np.clip(1+(art-med)*gain,.72,1.28)
    tone/=float(np.clip(1+(pigment-med)*gain,.72,1.28).mean())
    guide=periodic_sample(relief,su,sv)
    lo,med,hi=art_info['relief_luma_p5_p50_p95']
    # Low-pass face span supplies restrained broad relief; shaft noise excluded.
    height=np.clip((guide-med)/(hi-lo),-.60,.60)*amplitude*.72
    return height,tone

def tail_fan_field(w,h,edge=False):
    """Few broad authored coverts, independently legible below unchanged root."""
    global _TAIL_ART_CACHE
    if _TAIL_ART_CACHE is None:
        path=OUT/'material_sources/feather-source-v1.png'
        im=bpy.data.images.load(str(path),check_existing=False);im.colorspace_settings.name='Non-Color'
        iw,ih=im.size;raw=np.empty(iw*ih*4,np.float32);im.pixels.foreach_get(raw)
        gray=raw.reshape(ih,iw,4)[:,:,:3]@np.array([.2126,.7152,.0722],np.float32)
        pigment=blur_periodic(gray,3);relief=blur_periodic(gray,7);bpy.data.images.remove(im)
        _TAIL_ART_CACHE=(pigment,relief,{'path':str(path.relative_to(ROOT)),'sha256':sha(path),'prompt_path':str((path.parent/'feather-source-v1-prompt.txt').relative_to(ROOT)),'prompt_sha256':sha(path.parent/'feather-source-v1-prompt.txt'),'generator':'OpenAI built-in ImageGen','original_path':'/Users/ninja/.codex/generated_images/01a12d09-d5ea-7952-8a60-3670fc421c94/exec-3f10be60-46d7-4217-97cb-1e6e8c9ee8e5.png','dimensions':[iw,ih],'scope':'Local rounded tail coverts only; accepted body and flippers use irregular v2 source','orientation':'Source and chart +v both up; feather free tips point down'})
    pigment,relief,info=_TAIL_ART_CACHE
    signed_u,t=tail_chart_coordinates(w,h,edge);u=(signed_u+1)/2;v=1-np.interp(t,TAIL_ROWS,np.arange(9))/8
    # Wider rounded faces (1.5x) and1.18x taller; leading center rises while
    # flanking faces sit lower. Preserve exact root fade and contrast recipe.
    su=.505+(u-.5)*(.26+.08*v)+.017*np.sin(math.tau*v)
    sv=.2232+(.37/1.18)*v-.015*np.cos(math.pi*(u-.5))
    face=periodic_sample(pigment,su,sv);lo,hi=np.percentile(pigment,[10,90])
    q=np.clip((face-lo)/(hi-lo),0,1)
    tone=.72+2.10*q**.85
    guide=periodic_sample(relief,su,sv);rlo,rhi=np.percentile(relief,[10,90])
    height=(np.clip((guide-rlo)/(rhi-rlo),0,1)-.5)*.0032
    smooth=lambda a,b,x:np.clip((x-a)/(b-a),0,1)**2*(3-2*np.clip((x-a)/(b-a),0,1))
    weight=1-smooth(.42,.72,v)
    # No encircling outline or root rim; broad lower faces taper into margin.
    weight*=1-.30*smooth(.83,1,np.abs(signed_u))
    return height,tone,weight,info

def maps(mesh,uv):
    color,covered=raster_palette(mesh,uv);normal=np.zeros((N,N,3),np.float32);normal[...,2]=1
    rough=np.full((N,N),.88,np.float32);height_diagnostic=np.zeros((N,N),np.float32)
    # Broad muted warm-gray ventral/inner wrap; retain charcoal outer rim.
    # UV u=.25 is the inward edge, u=.5 center rear, v=1 shoulder.
    smooth_field=lambda a,b,x: np.clip((x-a)/(b-a),0,1)**2*(3-2*np.clip((x-a)/(b-a),0,1))
    underside_srgb=np.array([145,139,123],np.float32)/255
    underside=np.where(underside_srgb<=.04045,underside_srgb/12.92,((underside_srgb+.055)/1.055)**2.4)
    inner_fields={}
    inner_knots={
      'flipper_L':([0,.07,.184,.325,.453,.580,.638,.670,1],[.36,.34,.315,.287,.273,.344,.378,.384,.384],[.37,.39,.413,.399,.395,.386,.390,.384,.384]),
      'flipper_R':([0,.065,.166,.318,.457,.595,.697,.735,1],[.40,.36,.339,.291,.333,.375,.398,.416,.416],[.40,.48,.492,.491,.461,.434,.433,.416,.416])}
    for name in ('flipper_L','flipper_R'):
        fx0,fy0,fx1,fy1=RECTS[name];yy,xx=np.mgrid[0:fy1-fy0,0:fx1-fx0];u=(xx+.5)/(fx1-fx0);v=(yy+.5)/(fy1-fy0)
        levels,lower,upper=inner_knots[name];lo=np.interp(v,levels,lower);hi=np.interp(v,levels,upper)
        wrap=smooth_field(lo-.013,lo+.013,u)*(1-smooth_field(hi-.013,hi+.013,u))
        wrap*=smooth_field(.045,.105,v)*(1-smooth_field(.638 if name.endswith('L') else .697,.670 if name.endswith('L') else .735,v))
        inner_fields[name]=wrap
        section=color[fy0:fy1,fx0:fx1];section[:]=section*(1-wrap[:,:,None])+underside*wrap[:,:,None]
    # Tail inherits rump pigment evaluated at matching original X/height.
    # Shape, vertex palette source, feet and UV coordinates remain untouched.
    bx0,by0,bx1,by1=RECTS['continuous_body_head'];body_pigment=color[by0:by1,bx0:bx1].copy()
    for name in ('tail_top','tail_bottom','tail_edge'):
        tx0,ty0,tx1,ty1=RECTS[name];bu,bv=tail_body_coords(tx1-tx0,ty1-ty0,name=='tail_edge')
        color[ty0:ty1,tx0:tx1]=np.stack([periodic_sample(body_pigment[:,:,ch],bu,bv) for ch in range(3)],axis=2)
    for i,(name,(x0,y0,x1,y1)) in enumerate(RECTS.items()):
        w,h=x1-x0,y1-y0;kind='body' if name=='continuous_body_head' else 'flipper' if name.startswith('flipper') else 'foot' if name.startswith('foot') else 'tail'
        ht,tone=feather_field(w,h,'tail_edge' if name=='tail_edge' else kind,417+i*103)
        if kind=='body':
            pigment=color[y0:y1,x0:x1].max(2)
            detail_gain=.35+.65*(1-np.clip((pigment-.12)/.12,0,1))
            applied_tone=1+(tone-1)*detail_gain
        else:applied_tone=tone
        if kind=='flipper':
            applied_tone=1+(applied_tone-1)*(1-.45*inner_fields[name]);ht*=1-.40*inner_fields[name]
        if kind=='tail':
            v=(np.arange(h)+.5)/h;headroom=1+.18*(1-smooth_field(.18,.50,v))
            applied_tone=applied_tone*headroom[:,None]
            # Relief develops below the near-flush root; no tangent-map shelf.
            ht*= (.20+.80*(1-smooth_field(.30,.72,v)))[:,None]
            fan_ht,fan_tone,fan_weight,fan_source=tail_fan_field(w,h,name=='tail_edge')
            applied_tone=applied_tone*(1-fan_weight)+fan_tone*fan_weight
            ht=ht*(1-fan_weight)+fan_ht*fan_weight
        color[y0:y1,x0:x1]*=applied_tone[...,None];height_diagnostic[y0:y1,x0:x1]=ht
        meter_u,meter_v={'body':(2.7,1.69),'flipper':(.48,.86),'tail':(.28,.32),'foot':(.9,.285)}[kind]
        dy,dx=np.gradient(ht);nn=np.stack((-dx/(meter_u/w),-dy/(meter_v/h),np.ones_like(ht)),axis=2);nn/=np.linalg.norm(nn,axis=2,keepdims=True)
        normal[y0:y1,x0:x1]=nn
        rough[y0:y1,x0:x1]=({'body':.87,'flipper':.86,'tail':.87,'foot':.76}[kind]+np.clip((1-tone)*.22,-.025,.035))
    # Extrude8px at1024, same normalized margin as16px at2048.
    packed=np.dstack((color,normal,rough));valid=covered.copy()
    for _ in range(PADDING):
        total=np.zeros_like(packed);count=np.zeros((N,N),np.float32)
        for axis,shift in ((0,-1),(0,1),(1,-1),(1,1)):
            mm=np.roll(valid,shift,axis);total+=np.roll(packed,shift,axis)*mm[...,None];count+=mm
        fill=(~valid)&(count>0);packed[fill]=total[fill]/count[fill,None];valid|=fill
    color=packed[:,:,:3];normal=packed[:,:,3:6];rough=packed[:,:,6]
    normal/=np.maximum(np.linalg.norm(normal,axis=2,keepdims=True),1e-8)
    srgb=np.where(color<=.0031308,color*12.92,1.055*np.maximum(color,0)**(1/2.4)-.055)
    base=np.uint8(np.clip(srgb*255+.5,0,255));norm=np.uint8(np.clip((normal*.5+.5)*255+.5,0,255))
    mr=np.zeros((N,N,3),np.uint8);mr[:,:,0]=255;mr[:,:,1]=np.uint8(np.clip(rough*255+.5,0,255))
    png(OUT/'base-color.png',base);png(OUT/'normal.png',norm);png(OUT/'metallic-roughness.png',mr)
    png(OUT/'relief-diagnostic.png',np.repeat(np.uint8(np.clip(height_diagnostic/.003*180+48,0,255))[...,None],3,axis=2))
    return {'covered_texels':int(covered.sum()),'padding_pixels':PADDING,'normal_convention':'OpenGL tangent +Y; image UV origin bottom-left','color_adjustment':'Charcoal95% warm-neutralized atRGB1.28:1:.76, normalized to previous1.10:1:.92 luminance; same1.38 value factor; ivory/gold/orange unchanged','roughness_range':[float(rough[covered].min()),float(rough[covered].max())],'feather_recipe':'v5 same accepted body/feet; broad warmgray innerflippers, rounded featherfan withburiedroot andstaggered coverts','authored_source':authored_source()[2],'authored_mapping':{'body_source_u_periods':'2.3 at rump to3.9 crown; source widths vary12–14 across; approximately18–24 visible midback faces','body_source_v':'1.75*v+.8*v^2+.17; derivative1.75..3.35 >0','flipper_underside_srgb':[145,139,123],'flipper_inner_face_uv_knots':inner_knots,'flipper_inner_face_source':'Exact c380 visible UV samples at reference row intervals; dark shoulder ceiling v.670L/.735R, soft .026u boundary; restrained innerface relief','flipper_section_roll_max_degrees':28,'flipper_source_span':[.78,.94],'flipper_source_v_derivative':'0.56 distal to1.32 root; true overlap/free-tip intervals','tail_mapping':'Closest actual rump triangle barycentric UV at fan vertices; interpolated over unchanged chart, matching source feather phase; pigment lift delayed until lower fan','tail_tiers':3,'tail_lower_linear_pigment_multiplier':1.18,'tail_authored_source':fan_source,'tail_fan_recipe':'Distinct local rounded coverts: about3 broad faces across with leading center and offset side coverts; motif1.5x wider/1.18x taller, center raised bylocalphase; shallow outward warp; root v>=.72 exactly retains62239; faces .72..2.82 linear body pigment, partial narrow cavities, no outer border; inferred3.2mm face/valley height span','tail_design':'Rounded exposed covertfan withroot buried; mainreference envelope about50px wide at304px character height','normal_guide':'Two-pass7px source box low pass; inferred shallow face relief, not recovered physical height','pigment_filter':'Two-pass3px source box low pass; v2 filtered p5..p95 mapped to40% linear face spread, mean-normalized; extrema clamped .72..1.28','relief_strength':'Filtered v2 p5..p95 supplies72% of2mm body height span; no change to global material normalScale','foot_maps':'Body and both feet chart pixels exact to acceptedb21 in all3maps'}}

def component_identity(attrs,indices):
    positions,inverse=np.unique(attrs['POSITION'],axis=0,return_inverse=True)
    parent=list(range(len(positions)))
    def root(i):
        while parent[i]!=i:parent[i]=parent[parent[i]];i=parent[i]
        return i
    for tri in inverse[indices]:
        a,b,c=map(int,tri);ra=root(a);parent[root(b)]=ra;parent[root(c)]=ra
    ids=np.array([root(i) for i in range(len(positions))]);result={}
    for group in np.unique(ids):
        vi=np.where(ids==group)[0];n=len(vi);side='L' if positions[vi,0].mean()<0 else 'R'
        name='continuous_body_head' if n==2258 else 'short_tail_fan' if n==306 else 'flipper_'+side if n==482 else 'foot_'+side if n==1922 else None
        assert name and name not in result
        subset=indices[ids[inverse[indices[:,0]]]==group]
        uvrows=[]
        for tri in subset:
            corner=[attrs['TEXCOORD_0'][i].astype('<f4').tobytes() for i in tri]
            uvrows.append(min(b''.join(corner[k:]+corner[:k]) for k in range(3)))
        result[name]={'unique_positions':n,'triangles':len(subset),'position_normal_sha256':triangle_identity(attrs,subset),'uv_triangles_sha256':hashlib.sha256(b''.join(sorted(uvrows))).hexdigest()}
    return result

def freeze_tail_diagonals(mesh,metadata):
    """Preserve accepted UV diagonals before rounded fan changes quad shape."""
    mesh.calc_loop_triangles();start,end=metadata['parts_vertex_ranges']['short_tail_fan'];choices=[]
    for poly in mesh.polygons:
        if min(poly.vertices)<start or len(poly.vertices)!=4:continue
        tris=[set(t.vertices) for t in mesh.loop_triangles if t.polygon_index==poly.index]
        diag=tris[0]&tris[1];corners=list(poly.vertices)
        method='FIXED' if diag=={corners[0],corners[2]} else 'FIXED_ALTERNATE'
        choices.append((poly.index,method))
    before=np.array([v.co[:] for v in mesh.vertices],np.float32)
    bm=bmesh.new();bm.from_mesh(mesh);bm.faces.ensure_lookup_table();targets=[(bm.faces[i],method) for i,method in choices]
    for face,method in targets:bmesh.ops.triangulate(bm,faces=[face],quad_method=method,ngon_method='EAR_CLIP')
    bm.to_mesh(mesh);bm.free();mesh.update();mesh.calc_loop_triangles()
    assert np.array_equal(before,np.array([v.co[:] for v in mesh.vertices],np.float32))

def triangle_topology_set(triangles):
    return sorted(min(tuple(t[k:])+tuple(t[:k]) for k in range(3)) for t in map(list,triangles))

def refine_tail_flippers(mesh,metadata,config):
    """Scoped deformations only; actual body surface supplies buried tail join."""
    global _TAIL_BODY_UV
    angle=math.radians(config['forward_lean_degrees']);c,s=math.cos(angle),math.sin(angle);py,pz=config['lean_pivot_yz']
    original=np.array([v.co[:] for v in mesh.vertices],float);unlean=original.copy()
    y=original[:,1]-py;z=original[:,2]-pz;unlean[:,1]=py+c*y-s*z;unlean[:,2]=pz+s*y+c*z
    b0,b1=metadata['parts_vertex_ranges']['continuous_body_head'];mesh.calc_loop_triangles()
    bodyfaces=[t for t in mesh.loop_triangles if max(t.vertices)<b1]
    bodytri=np.array([t.vertices[:] for t in bodyfaces]);q=unlean[bodytri];a,b,cc=q[:,0],q[:,1],q[:,2]
    bx0,by0,bx1,by1=RECTS['continuous_body_head'];uvdata=mesh.uv_layers['RearSurfaceAtlas'].data
    bodyuv=np.array([[uvdata[i].uv[:] for i in tri.loops] for tri in bodyfaces])*N
    bodyuv=(bodyuv-np.array([bx0,by0]))/np.array([bx1-bx0,by1-by0])
    body_normals=np.array([v.normal[:] for v in mesh.vertices])[bodytri]
    det=(b[:,2]-cc[:,2])*(a[:,0]-cc[:,0])+(cc[:,0]-b[:,0])*(a[:,2]-cc[:,2])
    def body_rear(x,z):
        with np.errstate(divide='ignore',invalid='ignore'):
            w0=((b[:,2]-cc[:,2])*(x-cc[:,0])+(cc[:,0]-b[:,0])*(z-cc[:,2]))/det
            w1=((cc[:,2]-a[:,2])*(x-cc[:,0])+(a[:,0]-cc[:,0])*(z-cc[:,2]))/det;w2=1-w0-w1
        valid=(abs(det)>1e-12)&(w0>=-1e-5)&(w1>=-1e-5)&(w2>=-1e-5)
        assert valid.any(),(x,z)
        ys=w0*a[:,1]+w1*b[:,1]+w2*cc[:,1];face=int(np.argmin(np.where(valid,ys,np.inf)));weights=np.array([w0[face],w1[face],w2[face]])
        nn=weights@body_normals[face];nn/=np.linalg.norm(nn)
        return float(ys[face]),weights@bodyuv[face],nn
    smooth=lambda a,b,x: np.clip((x-a)/(b-a),0,1)**2*(3-2*np.clip((x-a)/(b-a),0,1))
    start,end=metadata['parts_vertex_ranges']['short_tail_fan'];join=[];closest_normals={};_TAIL_BODY_UV=np.zeros((9,17,2))
    for layer in range(2):
        for row in range(9):
            t=float(TAIL_ROWS[row]);emerge=float(smooth(.23,.52,t))
            for column in range(17):
                u=-1+column/8;lateral=math.sqrt(max(0,1-u*u))
                x=u*float(tail_half_width(t))
                z=tail_height(t,u)
                # Broad blunt free ends; small irregular lobes, no saw teeth.
                z-=.009*(.5+.5*math.cos(4*math.pi*u+.35))*smooth(.70,1,t)*lateral
                rear,body_uv,body_normal=body_rear(x,z)
                if layer==0:_TAIL_BODY_UV[row,column]=body_uv
                outward=.052*emerge*(.30+.70*lateral)*(1-.22*t*t)
                # Three shallow overlapping covert groups, not a single flat plate.
                coverts=.0045*sum(math.exp(-((t-center-.028*math.cos(3*math.pi*u+phase))/.075)**2)*(.35+.65*math.cos(2.5*math.pi*u+phase)**2) for center,phase in ((.48,0),(.69,1.3),(.89,.4)))*lateral
                buried=.018*(1-emerge)
                old_depth=outward+coverts-buried
                # Remove the abrupt first-visible +4mm to +50mm ramp.
                # Smoothly stagger the crossing; preserve lower fan positions.
                soft_depth=np.interp(t,TAIL_ROWS,[-.018,-.005,-.0007,.009,.027,.044,.043,.040,.035])
                soft_depth*=.30+.70*lateral
                soft_depth+=.0015*math.sin(3*math.pi*u+.3)*float(smooth(.18,.34,t))*(1-float(smooth(.50,.75,t)))
                blend=float(smooth(.64,.75,t));depth=soft_depth*(1-blend)+old_depth*blend
                y=rear-depth+(0 if layer==0 else .014)
                idx=start+layer*153+row*17+column;unlean[idx]=(x,y,z)
                if layer==0:closest_normals[idx]=(body_normal,1-float(smooth(.38,.72,t)))
                if layer==0:join.append({'row':row,'column':column,'body_rear_y':rear,'surface_y':y,'outward_m':rear-y})
    # Target masks require broader mid/distal blades and5–6px extra length.
    # Roll the section so broad warm ventral-inner face is visible from behind.
    for name in ('flipper_L','flipper_R'):
        start,end=metadata['parts_vertex_ranges'][name];segments=config['flipper_cross_segments'];side=-1 if name.endswith('L') else 1
        ts=sorted(set([i/config['flipper_rings'] for i in range(config['flipper_rings'])]+[.97,.989]))
        for row,t in enumerate(ts):
            first=start+row*segments+(1 if row else 0);ring=unlean[first:first+segments].copy();center=ring.mean(axis=0)
            width_axis=ring[0]-ring[segments//2];width_axis[1]=0;width_axis/=np.linalg.norm(width_axis)
            roll=math.radians(28)*math.sin(math.pi*t);cr,sr=math.cos(roll),math.sin(roll)
            width_scale=1+(.45 if side<0 else .35)*math.sin(math.pi*t)
            for i in range(segments):
                d=ring[i]-center;pdist=float(d@width_axis)*width_scale;qdist=d[1]
                rotated_width=pdist*cr-qdist*sr;rotated_depth=pdist*sr+qdist*cr
                point=center+width_axis*rotated_width;point[1]=center[1]+rotated_depth
                point[0]+=side*(.012 if side<0 else .018)*t*t
                point[2]-=(.030 if side<0 else .034)*t*t
                unlean[first+i]=point
        # End cap follows the same grounded body-independent blade extension.
        unlean[end-1,0]+=side*(.012 if side<0 else .018);unlean[end-1,2]-=(.030 if side<0 else .034)
    changed=[]
    for name in ('flipper_L','flipper_R','short_tail_fan'):
        start,end=metadata['parts_vertex_ranges'][name]
        for i in range(start,end):
            x,y,z=unlean[i];mesh.vertices[i].co=(x,py+c*(y-py)+s*(z-pz),pz-s*(y-py)+c*(z-pz))
        changed.append({'part':name,'max_displacement_m':float(np.linalg.norm(np.array([mesh.vertices[i].co[:] for i in range(start,end)])-original[start:end],axis=1).max())})
    mesh.update();mesh.calc_loop_triangles()
    # Explicit smooth root shading, actual closest-body normals; auto normals
    # remain untouched elsewhere (zero custom normals mean use automatic).
    custom=[]
    for loop in mesh.loops:
        if loop.vertex_index in closest_normals:
            target,weight=closest_normals[loop.vertex_index];normal=np.array(mesh.corner_normals[loop.index].vector)
            normal=(1-weight)*normal+weight*target;normal/=np.linalg.norm(normal);custom.append(tuple(normal))
        else:custom.append((0.,0.,0.))
    mesh.normals_split_custom_set(custom);mesh.update();mesh.calc_loop_triangles()
    for name in ('continuous_body_head','foot_L','foot_R'):
        start,end=metadata['parts_vertex_ranges'][name];assert np.array_equal(np.array([mesh.vertices[i].co[:] for i in range(start,end)]),original[start:end])
    return {'scope':'Rounded lower fan retained; staggered near-flush root develops gradually into lower volume, closest-body root normals and barycentric artwork phase; reference-fitted flipper geometry retained.','changes':changed,'tail_source_join_samples':join,'protected_vertices_exact':True,'triangle_topology_unchanged':True}

def preserve_untouched_export_normals(path):
    """Tail custom normals trigger Blender quantization globally; restore exact
    unchanged exported normals/tangents by POSITION+UV, never weaken guards."""
    baseline=OUT/'build_inputs/preserved_normals_c380.glb'
    digest='c380a0f91dd2149936f9dd6bb5de9a8fb4e2a6631090a8e27e731d47a1a01dc5'
    assert sha(baseline)==digest
    _,_,old,_=glb_arrays(baseline);doc,_,current,_=glb_arrays(path)
    def is_tail(uv):return uv[0]>=648/1024-1e-7 and uv[1]>=1-248/1024-1e-7
    reference={}
    for i in range(len(old['POSITION'])):
        if not is_tail(old['TEXCOORD_0'][i]):
            key=old['POSITION'][i].tobytes()+old['TEXCOORD_0'][i].tobytes()
            val=(old['NORMAL'][i],old['TANGENT'][i])
            if key in reference:assert all(np.array_equal(a,b) for a,b in zip(reference[key],val))
            reference[key]=val
    raw=bytearray(path.read_bytes());offset=12
    while offset<len(raw):
        length,kind=struct.unpack_from('<II',raw,offset)
        if kind==0x004e4942:binary_start=offset+8;break
        offset+=8+length
    primitive=doc['meshes'][0]['primitives'][0];streams={}
    for name,width in [('NORMAL',3),('TANGENT',4)]:
        accessor=doc['accessors'][primitive['attributes'][name]];view=doc['bufferViews'][accessor['bufferView']]
        streams[name]=np.ndarray((accessor['count'],width),dtype='<f4',buffer=raw,offset=binary_start+view.get('byteOffset',0)+accessor.get('byteOffset',0),strides=(view.get('byteStride',width*4),4))
    count=0;max_delta=0.
    for i in range(len(current['POSITION'])):
        if not is_tail(current['TEXCOORD_0'][i]):
            key=current['POSITION'][i].tobytes()+current['TEXCOORD_0'][i].tobytes();assert key in reference
            normal,tangent=reference[key];max_delta=max(max_delta,float(np.max(abs(current['NORMAL'][i]-normal))))
            streams['NORMAL'][i]=normal;streams['TANGENT'][i]=tangent;count+=1
    path.write_bytes(raw)
    return {'baseline_path':str(baseline.relative_to(ROOT)),'baseline_sha256':digest,'method':'Restore unchanged body/feet/flipper NORMAL+TANGENT by exact POSITION+UV after custom-tail normal export; geometry/materials untouched','restored_export_vertices':count,'max_export_normal_quantization_delta':max_delta}

def main():
    assert tuple(bpy.app.version[:3])==(5,2,0)
    assert sha(SOURCE/'candidate.glb')==BASE_SHA
    assert sha(BASELINE/'candidate.glb')==BASELINE_SHA
    OUT.mkdir(parents=True,exist_ok=True)
    metadata=json.loads((SOURCE/'metadata.json').read_text());config=json.loads((SOURCE/'config.json').read_text())
    bpy.ops.wm.open_mainfile(filepath=str(SOURCE/'source.blend'))
    obj=bpy.data.objects['RearBlockout'];mesh=obj.data;mesh.calc_loop_triangles()
    before=np.array([v.co[:] for v in mesh.vertices],np.float32);source_triangles=np.array([t.vertices[:] for t in mesh.loop_triangles])
    uv=uv_layout(mesh,metadata,config);freeze_tail_diagonals(mesh,metadata);uv=mesh.uv_layers['RearSurfaceAtlas'];refinement=refine_tail_flippers(mesh,metadata,config);diagnostic=maps(mesh,uv)
    for attr in list(mesh.color_attributes):mesh.color_attributes.remove(attr)
    mesh.materials.clear();mat=bpy.data.materials.new('RearSurfaceMattePBR');mat.use_nodes=True;nodes=mat.node_tree.nodes;links=mat.node_tree.links;p=nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(1,1,1,1);p.inputs['Metallic'].default_value=1;p.inputs['Roughness'].default_value=1
    textures={}
    for slot,file,space in [('base_color','base-color.png','sRGB'),('normal','normal.png','Non-Color'),('metallic_roughness','metallic-roughness.png','Non-Color')]:
        image=bpy.data.images.load(str(OUT/file));image.colorspace_settings.name=space;image.pack();node=nodes.new('ShaderNodeTexImage');node.image=image;node.interpolation='Linear';node.extension='EXTEND';node.label=slot;textures[slot]=node
    links.new(textures['base_color'].outputs['Color'],p.inputs['Base Color'])
    normal=nodes.new('ShaderNodeNormalMap');normal.space='TANGENT';normal.uv_map=uv.name;normal.inputs['Strength'].default_value=.65;links.new(textures['normal'].outputs['Color'],normal.inputs['Color']);links.new(normal.outputs['Normal'],p.inputs['Normal'])
    split=nodes.new('ShaderNodeSeparateColor');split.mode='RGB';links.new(textures['metallic_roughness'].outputs['Color'],split.inputs['Color']);links.new(split.outputs['Green'],p.inputs['Roughness']);links.new(split.outputs['Blue'],p.inputs['Metallic'])
    mesh.materials.append(mat);obj['gate']='rear-surface-v2'
    mesh.calc_loop_triangles();assert triangle_topology_set(source_triangles)==triangle_topology_set([t.vertices[:] for t in mesh.loop_triangles])
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'source.blend'),check_existing=False)
    bpy.ops.export_scene.gltf(filepath=str(OUT/'candidate.glb'),check_existing=False,export_format='GLB',use_selection=True,export_yup=True,export_apply=False,export_materials='EXPORT',export_normals=True,export_tangents=True,export_texcoords=True,export_vertex_color='NONE',export_all_vertex_colors=False,export_skins=False,export_animations=False,export_morph=False,export_cameras=False,export_lights=False,export_extras=False)
    refinement['unchanged_normal_export_preservation']=preserve_untouched_export_normals(OUT/'candidate.glb')
    old,_,oa,oi=glb_arrays(BASELINE/'candidate.glb');doc,binary,attrs,indices=glb_arrays(OUT/'candidate.glb')
    old_id,new_id=triangle_identity(oa,oi),triangle_identity(attrs,indices)
    prior_parts=component_identity(oa,oi);new_parts=component_identity(attrs,indices)
    for name in prior_parts:
        assert prior_parts[name]['uv_triangles_sha256']==new_parts[name]['uv_triangles_sha256'],name
        if name in ('continuous_body_head','foot_L','foot_R'):assert prior_parts[name]==new_parts[name],name
    assert len(indices)==14720 and set(attrs)=={'POSITION','NORMAL','TANGENT','TEXCOORD_0'}
    material=doc['materials'][0];pbr=material['pbrMetallicRoughness'];surface_maps={}
    for slot,index in [('base_color',pbr['baseColorTexture']['index']),('normal',material['normalTexture']['index']),('metallic_roughness',pbr['metallicRoughnessTexture']['index'])]:
        ii=doc['textures'][index]['source'];im=doc['images'][ii];view=doc['bufferViews'][im['bufferView']];payload=binary[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
        assert payload.startswith(b'\x89PNG\r\n\x1a\n') and struct.unpack_from('>II',payload,16)==(N,N)
        surface_maps[slot]={'image_index':ii,'sha256':hashlib.sha256(payload).hexdigest(),'width':N,'height':N,'color_space':'srgb' if slot=='base_color' else 'linear','channels':'RGB color' if slot=='base_color' else 'RGB tangent-space XYZ' if slot=='normal' else 'R unused255; G roughness; B metallic0'}
    out={k:metadata[k] for k in ['source_height_m','gameplay_height_m','gameplay_scale','author_axes','bounds_author_m','root_transform','pose','parts_vertex_ranges','anatomical_foot_direction']}
    out.update({'schema_version':1,'gate':'rear-surface-v2','geometry_contract':'tail-flippers-only-v1','material_contract':'rear-surface-pbr-v1','unrigged':True,'production_ready':False,'animation_ready':False,'visual_approval':'pending actual-game surface review','glb_sha256':sha(OUT/'candidate.glb'),'source_sha256':sha(OUT/'source.blend'),'builder_sha256':sha(__file__),'reference_file':'art_src/characters/reference_boards/penguin-gameplay-v2-20261011/animatics-strong-lean/waddle-frame-04.png','geometry_reference':{'path':str((BASELINE/'candidate.glb').relative_to(ROOT)),'glb_sha256':BASELINE_SHA},'geometry_identity':{'method':'Scoped exact oriented POSITION+NORMAL triangles; body/feet protected, tail/flippers allowed','sha256':new_id,'source_sha256':old_id,'passed':True},'scoped_geometry_identity':{'protected':['continuous_body_head','foot_L','foot_R'],'allowed':['flipper_L','flipper_R','short_tail_fan'],'baseline':prior_parts,'candidate':new_parts,'passed':True},'refinement':refinement,'triangles':len(indices),'triangle_budget':15000,'vertices':len(attrs['POSITION']),'source_vertices':len(before),'surfaces':1,'surface_maps':surface_maps,'material':{'name':mat.name,'base_color_factor':[1,1,1,1],'effective_metallic':0,'metallic_factor':pbr.get('metallicFactor',1),'roughness_factor':pbr.get('roughnessFactor',1),'normal_scale':material['normalTexture'].get('scale',1),'color_owner':'baseColorTexture only; no vertex colors'},'atlas':{'size':N,'rectangles':RECTS,**diagnostic},'rendered_frames':0,'deferred':['rig and animation','front face/podium authoring','runtime promotion']})
    out['reference_sha256']=sha(ROOT/out['reference_file'])
    (OUT/'metadata.json').write_text(json.dumps(out,indent=2)+'\n')
    print('SURFACE_METADATA '+json.dumps(out,sort_keys=True))

if __name__=='__main__':main()
