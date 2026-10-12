"""Independent source skin evaluator checks with analytically known motion."""
import importlib.util
from pathlib import Path
import tempfile
import unittest
import numpy as np
from tests.test_motion_candidate_export import package_fixture

spec=importlib.util.spec_from_file_location('motion_poses',Path(__file__).resolve().parents[1]/'tools/qa/motion_candidate_pose_expectations.py')
poses=importlib.util.module_from_spec(spec);spec.loader.exec_module(poses)

class PoseExpectationTests(unittest.TestCase):
    def test_shortest_arc_quaternion_and_vector_interpolation(self):
        np.testing.assert_allclose(poses.interpolate([0,1],[(0,0,0),(2,4,6)],.25),[.5,1,1.5])
        np.testing.assert_allclose(poses.interpolate([0,1],[(0,0,0,1),(0,0,1,0)],.5,True),[0,0,2**-.5,2**-.5])
        np.testing.assert_allclose(poses.interpolate([0,1],[(0,0,0,1),(0,0,0,-1)],.5,True),[0,0,0,1])

    def test_weighted_vertices_match_analytic_half_weight_translation(self):
        with tempfile.TemporaryDirectory() as temp:
            package,_d,_b,_m=package_fixture(Path(temp));proof=poses.generate(package)
            rest=np.asarray(proof['rest_vertices'])[:,:3]
            for clip in proof['clips'].values():
                for sample in clip['samples']:
                    phase=sample['phase'];x=.01*(2*phase if phase<=.5 else 2*(1-phase))
                    np.testing.assert_allclose(np.asarray(sample['positions']),rest+np.array([x,0,0]),atol=2e-9,rtol=0)

if __name__=='__main__':unittest.main()
