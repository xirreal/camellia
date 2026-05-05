#ifndef RAYTRACE_INCLUDE_GUARD
#define RAYTRACE_INCLUDE_GUARD

#ifndef CONTROL_BUFFER_QUALIFIERS
#define CONTROL_BUFFER_QUALIFIERS restrict readonly
#endif
#ifndef BVH2_NODE_BUFFER_QUALIFIERS
#define BVH2_NODE_BUFFER_QUALIFIERS restrict readonly
#endif
#ifndef QUAD_POS_READ_BUFFER_QUALIFIERS
#define QUAD_POS_READ_BUFFER_QUALIFIERS restrict readonly
#endif

#include "/lib/buffers/control.glsl"
#include "/lib/quad-read.glsl"
#include "/lib/buffers/bvh2-node.glsl"
#include "/lib/buffers/quad-pos-read.glsl"
#include "/lib/hploc.glsl"
#include "/lib/textures-read.glsl"

#define ALPHA_TEST

#ifdef ALPHA_TEST
uniform float alphaTestRef = 0.1;
#endif

const vec3 WATER_ABSORPTION = vec3(0.45, 0.07, 0.04);

const int BVH_STACK_SIZE = 24;
const int BVH_WG_SIZE = 64;
shared uint shared_stack[BVH_STACK_SIZE * BVH_WG_SIZE];
const float RT_INF = 3.402823466e+38;

struct TraceResult {
   float t;
   vec3 normal;
   bool hit;
   uint quadID;
   vec2 uv;
   vec4 vertexData;
   uint textureID;
   int triIndex;
   bool translucent;
   bool waterSurface;
};

vec3 safeInvDir(vec3 d) {
   vec3 ad = max(abs(d), vec3(1e-19));
   return sign(d + vec3(1e-30)) / ad;
}

float intersectAABB(vec3 bMin, vec3 bMax, vec3 ro, vec3 invRd, float tMinRay, float tMaxRay) {
   vec3 t0 = (bMin - ro) * invRd;
   vec3 t1 = (bMax - ro) * invRd;
   vec3 tsmaller = min(t0, t1);
   vec3 tbigger = max(t0, t1);

   float tmin = max(max(tsmaller.x, tsmaller.y), max(tsmaller.z, tMinRay));
   float tmax = min(min(tbigger.x, tbigger.y), min(tbigger.z, tMaxRay));

   return (tmax >= tmin) ? tmin : RT_INF;
}

bool intersectTri(vec3 ro, vec3 rd, vec3 v0, vec3 v1, vec3 v2, out float t, out vec2 bary) {
   vec3 e1 = v1 - v0;
   vec3 e2 = v2 - v0;
   vec3 p = cross(rd, e2);
   float det = dot(e1, p);

   if (abs(det) < 1e-8) return false;
   float invDet = 1.0 / det;

   vec3 s = ro - v0;
   float u = dot(s, p) * invDet;
   if (u < 0.0 || u > 1.0) return false;

   vec3 q = cross(s, e1);
   float v = dot(rd, q) * invDet;
   if (v < 0.0 || u + v > 1.0) return false;

   float tt = dot(e2, q) * invDet;
   if (tt <= 0.0) return false;

   t = tt;
   bary = vec2(u, v);
   return true;
}

void decodeQuadPositions(uint quadID, out vec3 p0, out vec3 p1, out vec3 p2, out vec3 p3) {
   QuadPositions qp = quadPositions[quadID];
   unpackQuadPositions(qp, p0, p1, p2, p3);
}

bool intersectQuadGeom(uint quadID, vec3 ro, vec3 rd, inout float tHit, out vec2 hitBary, out int hitTri) {
   vec3 p0, p1, p2, p3;
   decodeQuadPositions(quadID, p0, p1, p2, p3);

   float t;
   vec2 bary;
   bool hit = false;

   if (intersectTri(ro, rd, p0, p1, p2, t, bary) && t < tHit) {
      tHit = t;
      hitBary = bary;
      hitTri = 0;
      hit = true;
   }
   if (intersectTri(ro, rd, p0, p2, p3, t, bary) && t < tHit) {
      tHit = t;
      hitBary = bary;
      hitTri = 1;
      hit = true;
   }
   return hit;
}

// Local QuadData helpers — load once, read fields from local copy
uint qdMaterialBits(QuadData qd) {
   return qd.encodedMaterial >> 24u;
}
uint qdBlockID(QuadData qd) {
   return qd.encodedMaterial & 0x00FFFFFFu;
}
float qdEmission(QuadData qd) {
   return float(qdMaterialBits(qd) & 0x0Fu);
}
bool qdAlphaTested(QuadData qd) {
   return (qdMaterialBits(qd) & 0x10u) != 0u;
}
bool qdTranslucent(QuadData qd) {
   return (qdMaterialBits(qd) & 0x20u) != 0u;
}
bool qdPlayerModel(QuadData qd) {
   return (qdMaterialBits(qd) & 0x40u) != 0u;
}

vec2 qdUV(QuadData qd, uint i) {
   uint p = (i == 0u) ? qd.uv0 :
      (i == 1u) ? qd.uv1 :
      (i == 2u) ? qd.uv2 : qd.uv3;
   return unpackHalf2x16(p);
}

vec3 qdTint(QuadData qd, uint i) {
   uint w = (i < 2u) ? qd.tint01 : qd.tint23;
   uint s = (i & 1u) * 16u;
   return unpackRGB565((w >> s) & 0xFFFFu);
}

vec2 interpolateUV(QuadData qd, vec2 bary, int triIndex) {
   vec2 uv0 = qdUV(qd, 0u);
   float w = 1.0 - bary.x - bary.y;
   if (triIndex == 0) {
      return uv0 * w + qdUV(qd, 1u) * bary.x + qdUV(qd, 2u) * bary.y;
   } else {
      return uv0 * w + qdUV(qd, 2u) * bary.x + qdUV(qd, 3u) * bary.y;
   }
}

vec3 interpolateTint(QuadData qd, vec2 bary, int triIndex) {
   vec3 c0 = qdTint(qd, 0u);
   float w = 1.0 - bary.x - bary.y;
   if (triIndex == 0) {
      return c0 * w + qdTint(qd, 1u) * bary.x + qdTint(qd, 2u) * bary.y;
   } else {
      return c0 * w + qdTint(qd, 2u) * bary.x + qdTint(qd, 3u) * bary.y;
   }
}

vec4 sampleQuadTexture(QuadData qd, vec2 uv) {
   uint texID = qd.textureID;
   if (texID == 0u) {
      return texture(blockAtlas, uv);
   }

   #ifdef ENTITY_TEXTURES
   return sampleEntityTexture(texID, uv);
   #else
   return vec4(1.0);
   #endif
}

bool quadAlphaSkipsIntersection(QuadData qd, vec2 bary, int triIndex) {
   #ifdef ALPHA_TEST
   bool alphaTested = qdAlphaTested(qd);
   bool translucentCutout = qdTranslucent(qd) && qdBlockID(qd) != 1u;
   if (!alphaTested && !translucentCutout) return false;

   vec2 uv = interpolateUV(qd, bary, triIndex);
   return sampleQuadTexture(qd, uv).a < alphaTestRef;
   #else
   return false;
   #endif
}

// Keep SSBO-based helpers for pt.csh backward compatibility
vec2 interpolateQuadUV(uint quadID, vec2 bary, int triIndex) {
   return interpolateUV(quadData[quadID], bary, triIndex);
}

vec3 interpolateQuadTint(uint quadID, vec2 bary, int triIndex) {
   return interpolateTint(quadData[quadID], bary, triIndex);
}

const float DIAGONAL = sqrt(3.0);

TraceResult traceBVH(vec3 ro, vec3 rd, bool skipPlayer) {
   float tHit = (8.0 + (far * 16.0)) * DIAGONAL;
   uint hitQuad = INVALID_ID;
   vec2 hitBary = vec2(0.0);
   int hitTri = 0;

   uint rootID = control.rootClusterID;
   if (rootID != INVALID_ID) {
      vec3 invRd = safeInvDir(rd);
      int sp = 0;
      uint tid = gl_LocalInvocationIndex;
      uint nodeID = rootID;
      uint numQuads = control.sortTotal;

      for (int iter = 0; iter < BVH_STACK_SIZE * BVH_STACK_SIZE; iter++) {
         if (nodeID == INVALID_ID) {
            if (sp == 0) break;
            nodeID = shared_stack[(--sp) * BVH_WG_SIZE + tid];
            continue;
         }

         uint prim = getClusterPrimID(nodeID);

         if (!isInternalNode(nodeID)) {
            if (prim < numQuads) {
               QuadData qd = quadData[prim];
               uint mat = qdMaterialBits(qd);

               if (skipPlayer && ((mat & 0x40u) != 0u)) {
                  nodeID = INVALID_ID;
                  continue;
               }

               vec2 bary;
               int tri;
               #ifdef ALPHA_TEST
               float prevT = tHit;
               #endif
               if (intersectQuadGeom(prim, ro, rd, tHit, bary, tri)) {
                  #ifdef ALPHA_TEST
                  if (quadAlphaSkipsIntersection(qd, bary, tri)) {
                     tHit = prevT;
                     nodeID = INVALID_ID;
                     continue;
                  }
                  #endif
                  hitQuad = prim;
                  hitBary = bary;
                  hitTri = tri;
               }
            }
            nodeID = INVALID_ID;
            continue;
         }

         BVH2Node node = bvh2Nodes[prim];

         float t0 = intersectAABB(node.c0Min, node.c0Max, ro, invRd, 0.0, tHit);
         float t1 = intersectAABB(node.c1Min, node.c1Max, ro, invRd, 0.0, tHit);

         bool h0 = (t0 != RT_INF);
         bool h1 = (t1 != RT_INF);

         if (h0 && h1) {
            bool leftFirst = (t0 <= t1);
            uint nearID = leftFirst ? node.leftChild : node.rightChild;
            uint farID = leftFirst ? node.rightChild : node.leftChild;

            if (sp < BVH_STACK_SIZE) {
               shared_stack[sp * BVH_WG_SIZE + tid] = farID;
               ++sp;
            }
            nodeID = nearID;
         } else if (h0) {
            nodeID = node.leftChild;
         } else if (h1) {
            nodeID = node.rightChild;
         } else {
            nodeID = INVALID_ID;
         }
      }
   }

   TraceResult res;
   res.t = tHit;
   res.quadID = hitQuad;
   res.triIndex = hitTri;
   res.hit = (hitQuad != INVALID_ID);

   if (res.hit) {
      QuadData qd = quadData[hitQuad];
      QuadPositions qp = quadPositions[hitQuad];

      vec3 p0, p1, p2, p3;
      unpackQuadPositions(qp, p0, p1, p2, p3);

      vec3 n = (hitTri == 0)
         ? normalize(cross(p1 - p0, p2 - p0)) : normalize(cross(p2 - p0, p3 - p0));
      if (dot(n, rd) > 0.0) n = -n;
      res.normal = n;

      res.uv = interpolateUV(qd, hitBary, hitTri);
      res.vertexData = vec4(interpolateTint(qd, hitBary, hitTri), qdEmission(qd));
      res.textureID = qd.textureID;
      res.translucent = qdTranslucent(qd);
      res.waterSurface = qdBlockID(qd) == 1u;
   } else {
      res.normal = vec3(0.0);
      res.uv = vec2(0.0);
      res.vertexData = vec4(0.0);
      res.textureID = 0u;
      res.translucent = false;
      res.waterSurface = false;
   }

   return res;
}

TraceResult traceBVH(vec3 ro, vec3 rd) {
   return traceBVH(ro, rd, false);
}

bool shadowTriHit(QuadData qd, vec2 bary, int triIndex, float hitT, inout vec3 tint) {
   if (quadAlphaSkipsIntersection(qd, bary, triIndex)) return false;

   if (qdTranslucent(qd)) {
      if (qdBlockID(qd) == 1u) {
         vec3 waterTint = pow(interpolateTint(qd, bary, triIndex), vec3(2.2));
         tint *= waterTint * exp(-WATER_ABSORPTION * max(hitT, 0.5));
         return tint == vec3(0.0);
      }
      vec2 hitUV = interpolateUV(qd, bary, triIndex);
      vec4 texSample = sampleQuadTexture(qd, hitUV);
      float transparency = 1.0 - texSample.a;
      tint *= mix(vec3(0.0), pow(texSample.rgb * interpolateTint(qd, bary, triIndex), vec3(2.2)), transparency);
      return tint == vec3(0.0);
   } else {
      return true;
   }
}

vec3 traceShadowTinted(vec3 ro, vec3 rd, float maxDist) {
   uint rootID = control.rootClusterID;
   if (rootID == INVALID_ID) return vec3(1.0);

   vec3 invRd = safeInvDir(rd);
   vec3 tint = vec3(1.0);

   int sp = 0;
   uint tid = gl_LocalInvocationIndex;

   uint nodeID = rootID;
   uint numQuads = control.sortTotal;

   for (int iter = 0; iter < 512; iter++) {
      if (nodeID == INVALID_ID) {
         if (sp == 0) break;
         nodeID = shared_stack[(--sp) * BVH_WG_SIZE + tid];
         continue;
      }

      uint prim = getClusterPrimID(nodeID);

      if (!isInternalNode(nodeID)) {
         if (prim < numQuads) {
            vec3 p0, p1, p2, p3;
            decodeQuadPositions(prim, p0, p1, p2, p3);

            float t0, t1;
            vec2 b0, b1;
            bool h0 = intersectTri(ro, rd, p0, p1, p2, t0, b0) && t0 < maxDist;
            bool h1 = intersectTri(ro, rd, p0, p2, p3, t1, b1) && t1 < maxDist;

            if (h0 || h1) {
               QuadData qd = quadData[prim];
               if (h0 && shadowTriHit(qd, b0, 0, t0, tint)) return vec3(0.0);
               if (h1 && shadowTriHit(qd, b1, 1, t1, tint)) return vec3(0.0);
            }
         }
         nodeID = INVALID_ID;
         continue;
      }

      BVH2Node node = bvh2Nodes[prim];

      float t0 = intersectAABB(node.c0Min, node.c0Max, ro, invRd, 0.0, maxDist);
      float t1 = intersectAABB(node.c1Min, node.c1Max, ro, invRd, 0.0, maxDist);

      bool h0 = (t0 != RT_INF);
      bool h1 = (t1 != RT_INF);

      if (h0 && h1) {
         bool leftFirst = (t0 <= t1);
         uint nearID = leftFirst ? node.leftChild : node.rightChild;
         uint farID = leftFirst ? node.rightChild : node.leftChild;

         if (sp < BVH_STACK_SIZE) {
            shared_stack[sp * BVH_WG_SIZE + tid] = farID;
            ++sp;
         }
         nodeID = nearID;
      } else if (h0) {
         nodeID = node.leftChild;
      } else if (h1) {
         nodeID = node.rightChild;
      } else {
         nodeID = INVALID_ID;
      }
   }

   return tint;
}

#endif
