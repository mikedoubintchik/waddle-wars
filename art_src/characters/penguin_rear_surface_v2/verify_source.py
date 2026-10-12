"""Run with bundled Python/numpy/Pillow. No engine, renderer, or source mutation."""
from pathlib import Path
import ast,hashlib,json,struct,io
import numpy as np
from PIL import Image,ImageDraw
ROOT=Path(__file__).resolve().parents[3]
p=Path(__file__).resolve().parent;builder=ROOT/'tools/art/build_penguin_rear_surface_v2.py'
ns=dict(np=np,json=json,struct=struct,hashlib=hashlib)
for node in ast.parse(builder.read_text()).body:
    if isinstance(node,ast.FunctionDef) and node.name in ('glb_arrays','triangle_identity','component_identity'):
        exec(compile(ast.Module(body=[node],type_ignores=[]),str(builder),'exec'),ns)
sha=lambda x:hashlib.sha256(x.read_bytes()).hexdigest()
m=json.loads((p/'metadata.json').read_text());base=ROOT/m['geometry_reference']['path']
d,b,a,t=ns['glb_arrays'](p/'candidate.glb');bd,bb,ba,bt=ns['glb_arrays'](base)
assert sha(base)==m['geometry_reference']['glb_sha256']
parts=ns['component_identity'](a,t);prior_parts=ns['component_identity'](ba,bt)
for name in prior_parts:
    assert parts[name]['uv_triangles_sha256']==prior_parts[name]['uv_triangles_sha256']
    if name in m['scoped_geometry_identity']['protected']:assert parts[name]==prior_parts[name]
assert ns['triangle_identity'](a,t)==m['geometry_identity']['sha256']
assert len(t)==14720 and not d.get('skins') and not d.get('animations')
assert set(a)=={'POSITION','NORMAL','TANGENT','TEXCOORD_0'}
for values in a.values():assert np.isfinite(values).all()
normal_error=float(np.max(abs(np.linalg.norm(a['NORMAL'],axis=1)-1)))
tangent_error=float(np.max(abs(np.linalg.norm(a['TANGENT'][:,:3],axis=1)-1)))
ortho=float(np.max(abs(np.sum(a['NORMAL']*a['TANGENT'][:,:3],axis=1))))
assert normal_error<1e-5 and tangent_error<1e-3 and ortho<1e-3
assert np.all(np.isin(a['TANGENT'][:,3],[-1,1]))
assert a['TEXCOORD_0'].min()>=0 and a['TEXCOORD_0'].max()<=1
uv=a['TEXCOORD_0'][t];du=uv[:,1]-uv[:,0];dv=uv[:,2]-uv[:,0];area=np.abs(du[:,0]*dv[:,1]-du[:,1]*dv[:,0]);assert area.min()>0
verts,inverse=np.unique(a['POSITION'],axis=0,return_inverse=True);wt=inverse[t]
edges=np.sort(np.concatenate([wt[:,[0,1]],wt[:,[1,2]],wt[:,[2,0]]]),axis=1)
_,counts=np.unique(edges,axis=0,return_counts=True);assert np.all(counts==2)
mapreport={}
for slot,info in m['surface_maps'].items():
    im=d['images'][info['image_index']];assert im.get('mimeType')=='image/png' and not im.get('uri')
    view=d['bufferViews'][im['bufferView']];blob=b[view.get('byteOffset',0):view.get('byteOffset',0)+view['byteLength']]
    assert hashlib.sha256(blob).hexdigest()==info['sha256']
    img=Image.open(io.BytesIO(blob));pixels=np.array(img);assert img.size==(m['atlas']['size'],m['atlas']['size'])==(1024,1024) and img.mode=='RGB'
    if slot=='metallic_roughness':assert pixels[:,:,2].max()==0
    if slot=='normal':
        nn=pixels.astype(float)/127.5-1;err=float(np.max(abs(np.linalg.norm(nn,axis=2)-1)));assert err<.01 and pixels[:,:,2].min()>=127
    mapreport[slot]={'sha256':info['sha256'],'size':list(img.size),'mode':img.mode,'embedded_png':True,'channels_min':pixels.min(axis=(0,1)).tolist(),'channels_max':pixels.max(axis=(0,1)).tolist()}
assert m['glb_sha256']==sha(p/'candidate.glb') and m['source_sha256']==sha(p/'source.blend') and m['builder_sha256']==sha(builder)
assert 'errors=0 warnings=0 infos=0 hints=0' in (p/'gltf-validation.log').read_text()
report={'schema_version':1,'scope':'Source geometry and material data only; game appearance pending','passed':True,'glb_sha256':m['glb_sha256'],'source_sha256':m['source_sha256'],'builder_sha256':m['builder_sha256'],'verifier_sha256':sha(Path(__file__)),'geometry_reference':m['geometry_reference'],'geometry_identity':m['geometry_identity'],'scoped_geometry_identity':m['scoped_geometry_identity'],'triangles':len(t),'triangles_unchanged':True,'unique_positions':len(verts),'exported_vertices_with_uv_splits':len(a['POSITION']),'nonmanifold_welded_edges':int(np.count_nonzero(counts!=2)),'zero_area_uv_triangles':0,'minimum_uv_triangle_twice_area':float(area.min()),'normal_unit_max_error':normal_error,'tangent_unit_max_error':tangent_error,'tangent_normal_max_dot_error':ortho,'tangent_numerical_tolerance':.001,'color_owner':'sRGB baseColorTexture only; COLOR_0 absent; factor white','metallic_response_zero':True,'surface_maps':mapreport,'uv_padding_pixels':m['atlas']['padding_pixels'],'normal_map_unit_vector_max_quantization_error':err,'baseline_b21_and_v9_preserved':True,'khronos_validator':{'errors':0,'warnings':0,'infos':0,'hints':0,'log_sha256':sha(p/'gltf-validation.log')}}
(p/'geometry-verification.json').write_text(json.dumps(report,indent=2)+'\n')
# Atlas-only swatches. Downsample before enlarging. No scene rendering.
baseimg=Image.open(p/'base-color.png');normalimg=Image.open(p/'normal.png')
regions=[('Crown',(470,150,830,510)),('Mid back',(470,700,830,1060)),('Rump',(470,1320,830,1680)),('Flipper',(1320,150,1640,550)),('Tail',(1300,1555,1620,1775)),('Right heel',(1690,1100,1980,1430))]
canvas=Image.new('RGB',(1440,780),'#ebe9e5');draw=ImageDraw.Draw(canvas)
for i,(label,box) in enumerate(regions):
    box=tuple(round(v*m['atlas']['size']/2048) for v in box)
    x=i*240;draw.text((x+8,8),label,fill='black');crop=baseimg.crop(box)
    canvas.paste(crop.resize((224,224),Image.Resampling.LANCZOS),(x+8,30));draw.text((x+8,260),'Atlas base color crop',fill='black')
    norm=normalimg.crop(box);canvas.paste(norm.resize((224,224),Image.Resampling.LANCZOS),(x+8,284));draw.text((x+8,516),'Tangent normal crop',fill='black')
    for j,target in enumerate((54,18)):
        sample=crop.resize((target,target),Image.Resampling.BOX).resize((108,108),Image.Resampling.NEAREST)
        canvas.paste(sample,(x+8+j*116,540));draw.text((x+8+j*116,654),'~300px' if j==0 else '~100px',fill='black')
draw.text((10,690),'Atlas samples only. Approximate body UV density at300/100px total height; component samples are not game captures.',fill='black')
draw.text((10,715),'Game lighting, material import and screen-space appearance remain final checks. Normal diagnostic is not RGB appearance.',fill='black')
canvas.save(p/'atlas-diagnostics.png')
print(json.dumps({'glb':m['glb_sha256'],'geometry_pass':True,'unique_positions':len(verts),'triangles':len(t),'normal_error':normal_error,'tangent_error':tangent_error,'orthogonality_error':ortho}))

# Protected maps include whole accepted body chart and both feet, not color tests.
protected={}
for part in ('continuous_body_head','foot_L','foot_R'):
    x0,y0,x1,y1=m['atlas']['rectangles'][part];protected[part]={}
    for filename in ('base-color.png','normal.png','metallic-roughness.png'):
        now=np.array(Image.open(p/filename))[::-1][y0:y1,x0:x1]
        old=np.array(Image.open(base.parent/filename))[::-1][y0:y1,x0:x1]
        assert np.array_equal(now,old),(part,filename)
        protected[part][filename]={'pixels_bit_identical':True,'pixel_sha256':hashlib.sha256(now.tobytes()).hexdigest()}
receipt={'schema_version':1,'candidate_sha256':m['glb_sha256'],'source_sha256':m['source_sha256'],'builder_sha256':m['builder_sha256'],'scope':'Source scoped geometry/material proof; actual game appearance pending','geometry_contract':m['geometry_contract'],'protected_map_pixels':protected,'refinement':m['refinement'],'authored_source':m['atlas']['authored_source'],'mapping':m['atlas']['authored_mapping'],'atlas_diagnostics_sha256':sha(p/'atlas-diagnostics.png'),'geometry_verification_sha256':sha(p/'geometry-verification.json'),'khronos_log_sha256':sha(p/'gltf-validation.log'),'passed':True}
(p/'surface-verification.json').write_text(json.dumps(receipt,indent=2)+'\n')
print(json.dumps({'protected_body_feet_maps_exact':True,'scoped_geometry_pass':True,'candidate_bytes':(p/'candidate.glb').stat().st_size}))
