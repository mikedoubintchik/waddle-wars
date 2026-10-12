import root from '../certificates/AppleIncRootCertificate.cer';
import g2 from '../certificates/AppleRootCA-G2.cer';
import g3 from '../certificates/AppleRootCA-G3.cer';
import { appleServices, createHandler } from './verification.mjs';

export default {
  fetch: createHandler((env) => appleServices(env, [root, g2, g3])),
};
