#!/usr/bin/env python3
"""Independent GLB linear-blend skin evaluation; resource test input, not a render."""
from __future__ import annotations
import argparse
import bisect
import copy
import importlib.util
import json
import math
from pathlib import Path

import numpy as np

_spec=importlib.util.spec_from_file_location('motion_contract',Path(__file__).with_name('motion_candidate_export.py'))
motion=importlib.util.module_from_spec(_spec);_spec.loader.exec_module(motion)
PHASES=(0.,.25,.5,.75,1.)


def interpolate(times,values,time,rotation=False):
    """glTF LINEAR uses vector lerp or shortest-arc normalized quaternion slerp."""
    if time<=times[0]:return list(values[0])
    if time>=times[-1]:return list(values[-1])
    i=bisect.bisect_right(times,time)-1;t=(time-times[i])/(times[i+1]-times[i])
    a=np.asarray(values[i],dtype=np.float64);b=np.asarray(values[i+1],dtype=np.float64)
    if not rotation:return (a+(b-a)*t).tolist()
    dot=float(a@b)
    if dot<0:b=-b;dot=-dot
    dot=min(1.,max(-1.,dot))
    if dot>.9995:q=a+(b-a)*t
    else:
        angle=math.acos(dot);q=(math.sin((1-t)*angle)*a+math.sin(t*angle)*b)/math.sin(angle)
    return (q/np.linalg.norm(q)).tolist()


def generate(package:Path)->dict:
    checked=motion.validate_package(package)
    doc,binary=motion.shape.glb_data(checked['files']['candidate.glb'])
    primitive=doc['meshes'][0]['primitives'][0];attrs=primitive['attributes'];skin=doc['skins'][0]
    vertices=np.asarray(motion.accessor(doc,binary,attrs['POSITION']),dtype=np.float64)
    normals=motion.accessor(doc,binary,attrs['NORMAL']);uv=motion.accessor(doc,binary,attrs['TEXCOORD_0'])
    joints=np.asarray(motion.accessor(doc,binary,attrs['JOINTS_0']),dtype=np.int64)
    weights=np.asarray(motion.accessor(doc,binary,attrs['WEIGHTS_0']),dtype=np.float64)
    ibms=np.asarray([motion.column_matrix(row) for row in motion.accessor(doc,binary,skin['inverseBindMatrices'])])
    parents={child:i for i,node in enumerate(doc['nodes']) for child in node.get('children',[])}
    points=np.c_[vertices,np.ones(len(vertices))];clips={}
    for animation in doc['animations']:
        name=animation['name'];duration=checked['clips'][name]['duration'];samples=[]
        tracks=[]
        for channel in animation['channels']:
            sampler=animation['samplers'][channel['sampler']]
            tracks.append((channel['target'],[row[0] for row in motion.accessor(doc,binary,sampler['input'])],motion.accessor(doc,binary,sampler['output'])))
        for phase in PHASES:
            nodes=copy.deepcopy(doc['nodes'])
            for target,times,values in tracks:
                node=nodes[target['node']]
                if 'matrix' in node:raise ValueError('Animated node cannot mix matrix and TRS')
                node[target['path']]=interpolate(times,values,phase*duration,target['path']=='rotation')
            worlds={}
            def world(i):
                if i not in worlds:
                    local=np.asarray(motion.node_matrix(nodes[i]))
                    worlds[i]=world(parents[i])@local if i in parents else local
                return worlds[i]
            matrices=np.asarray([world(j)@bind for j,bind in zip(skin['joints'],ibms)])
            transformed=np.einsum('nvij,nj->nvi',matrices[joints],points)
            posed=np.einsum('nv,nvi->ni',weights,transformed)[:,:3]
            if not np.isfinite(posed).all():raise ValueError('Nonfinite source skin evaluation')
            samples.append({'phase':phase,'time':phase*duration,'positions':posed.tolist()})
        clips[name]={'duration':duration,'loop':checked['clips'][name]['loop'],'samples':samples}
    return {'schema_version':1,'candidate_sha256':checked['metadata']['glb_sha256'],
        'generator_sha256':motion.digest(Path(__file__).read_bytes()),
        'scope':'Independent source GLB skin evaluation in model/world identity coordinates; no holder scale/controller jump height or rendered pixels',
        'vertex_match_tolerance_m':1e-5,'normal_match_tolerance':0.00015,'uv_match_tolerance':1e-5,
        'pose_tolerance_m':0.00015,
        'normal_match_policy':'Imported octahedral normal quantization measured across8095vertices: maximum vector distance0.0001254136; positions and UV errors exactly0. Only normal matching bound changed; posed-position bound unchanged',
        'rest_vertices':[list(p)+list(n)+list(t) for p,n,t in zip(vertices.tolist(),normals,uv)],'clips':clips}


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('package',type=Path);parser.add_argument('output',type=Path);a=parser.parse_args()
    result=generate(a.package.resolve());a.output.parent.mkdir(parents=True,exist_ok=True)
    with a.output.open('x') as f:json.dump(result,f,separators=(',',':'));f.write('\n')
    print(json.dumps({'output':str(a.output.resolve()),'candidate_sha256':result['candidate_sha256'],'vertices':len(result['rest_vertices']),'samples':sum(len(c['samples']) for c in result['clips'].values()),'bytes':a.output.stat().st_size}))
if __name__=='__main__':main()
