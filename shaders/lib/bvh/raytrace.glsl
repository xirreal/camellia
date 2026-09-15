#ifndef RAYTRACE_INCLUDE_GUARD
#define RAYTRACE_INCLUDE_GUARD

#ifndef CONTROL_BUFFER_QUALIFIERS
#define CONTROL_BUFFER_QUALIFIERS restrict readonly
#endif
#include "/lib/core/settings.glsl"
#include "/lib/buffers/control.glsl"
#include "/lib/buffers/quad-geometry.glsl"
#include "/lib/scene/quad-read.glsl"
#include "/lib/bvh/hploc.glsl"
#include "/lib/scene/textures-read.glsl"
#if BVH_WIDTH == 4
#include "/lib/bvh/wide.glsl"
#else
#include "/lib/buffers/bvh2-node.glsl"
#endif

#define ALPHA_TEST

uniform float alphaTestRef = 0.1;

const vec3 WATER_ABSORPTION = vec3(0.45, 0.07, 0.04);

const float RT_INF = 3.402823466e+38;
const int BVH_STACK_SIZE = 64;
#ifndef BVH_WG_SIZE
#define BVH_WG_SIZE 64
#endif

#if BVH_STACK_MODE == 1
layout(r32ui) uniform uimage2D bvhStackImg;
#elif BVH_STACK_MODE == 2
uint local_stack[BVH_STACK_SIZE];
#else
shared uint shared_stack[BVH_STACK_SIZE * BVH_WG_SIZE];
#endif

struct BVHTraversalState {
   uint nodeID;
   int sp;
   bool overflow;
};

void bvhTraversalInit(out BVHTraversalState state, uint rootID) {
   state.nodeID = rootID;
   state.sp = 0;
   state.overflow = false;
}

bool bvhTraversalOverflow(BVHTraversalState state) {
   return state.overflow;
}

#if BVH_STACK_MODE == 1
ivec2 bvhImageStackCoord(int depth) {
   ivec2 invocation = ivec2(gl_GlobalInvocationID.xy);
   return ivec2(invocation.x * 8 + (depth & 7), invocation.y * 8 + (depth >> 3));
}
#endif

// Returns true once the traversal stack has been exhausted.
bool bvhTraversalPop(inout BVHTraversalState state) {
   if (state.sp == 0) return true;
#if BVH_STACK_MODE == 1
   state.nodeID = imageLoad(bvhStackImg, bvhImageStackCoord(--state.sp)).x;
#elif BVH_STACK_MODE == 2
   state.nodeID = local_stack[--state.sp];
#else
   state.nodeID = shared_stack[(--state.sp) * BVH_WG_SIZE + gl_LocalInvocationIndex];
#endif
   return false;
}

void bvhTraversalDescendBoth(inout BVHTraversalState state, uint nearID, uint farID) {
   if (state.sp >= BVH_STACK_SIZE) {
      state.overflow = true;
      state.nodeID = INVALID_ID;
      return;
   }
#if BVH_STACK_MODE == 1
   imageStore(bvhStackImg, bvhImageStackCoord(state.sp), uvec4(farID));
#elif BVH_STACK_MODE == 2
   local_stack[state.sp] = farID;
#else
   shared_stack[state.sp * BVH_WG_SIZE + gl_LocalInvocationIndex] = farID;
#endif
   ++state.sp;
   state.nodeID = nearID;
}

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

float intersectAABBPrecomputed(
   vec3 bMin, vec3 bMax, vec3 invRd, vec3 rayOffset,
   float tMinRay, float tMaxRay
) {
   vec3 t0 = fma(bMin, invRd, rayOffset);
   vec3 t1 = fma(bMax, invRd, rayOffset);
   vec3 tNear = min(t0, t1);
   vec3 tFar = max(t0, t1);
   float tmin = max(max(tNear.x, tNear.y), max(tNear.z, tMinRay));
   float tmax = min(min(tFar.x, tFar.y), min(tFar.z, tMaxRay));
   return (tmax >= tmin) ? tmin : RT_INF;
}

#if BVH_WIDTH == 4
void bvhSortPair(inout float a, inout float b, inout uint ia, inout uint ib) {
   if (a > b) {
      float t = a; a = b; b = t;
      uint id = ia; ia = ib; ib = id;
   }
}

// Test four children together, sort once, and visit front-to-back.
bool bvhTraverseNode(inout BVHTraversalState state, vec3 invRd, vec3 rayOffset, float tMax) {
   BVH4Node node = loadBVH4(getClusterPrimID(state.nodeID));
   vec4 x0 = fma(node.minX, vec4(invRd.x), vec4(rayOffset.x));
   vec4 x1 = fma(node.maxX, vec4(invRd.x), vec4(rayOffset.x));
   vec4 y0 = fma(node.minY, vec4(invRd.y), vec4(rayOffset.y));
   vec4 y1 = fma(node.maxY, vec4(invRd.y), vec4(rayOffset.y));
   vec4 z0 = fma(node.minZ, vec4(invRd.z), vec4(rayOffset.z));
   vec4 z1 = fma(node.maxZ, vec4(invRd.z), vec4(rayOffset.z));
   vec4 nearT = max(max(min(x0, x1), min(y0, y1)), max(min(z0, z1), vec4(0.0)));
   vec4 farT = min(min(max(x0, x1), max(y0, y1)), min(max(z0, z1), vec4(tMax)));
   uvec4 ids = node.children;
   vec4 t = mix(vec4(RT_INF), nearT, greaterThanEqual(farT, nearT));
   t = mix(t, vec4(RT_INF), equal(ids, uvec4(INVALID_ID)));
   bvhSortPair(t.x, t.y, ids.x, ids.y);
   bvhSortPair(t.z, t.w, ids.z, ids.w);
   bvhSortPair(t.x, t.z, ids.x, ids.z);
   bvhSortPair(t.y, t.w, ids.y, ids.w);
   bvhSortPair(t.y, t.z, ids.y, ids.z);
   if (t.x == RT_INF) return bvhTraversalPop(state);
   if (t.w != RT_INF) bvhTraversalDescendBoth(state, ids.x, ids.w);
   if (t.z != RT_INF) bvhTraversalDescendBoth(state, ids.x, ids.z);
   if (t.y != RT_INF) bvhTraversalDescendBoth(state, ids.x, ids.y);
   state.nodeID = ids.x;
   return state.overflow;
}
#else
bool bvhTraverseNode(inout BVHTraversalState state, vec3 invRd, vec3 rayOffset, float tMax) {
   BVH2Node node = bvh2Nodes[getClusterPrimID(state.nodeID)];
   float leftT = intersectAABBPrecomputed(node.leftMin, node.leftMax, invRd, rayOffset, 0.0, tMax);
   float rightT = intersectAABBPrecomputed(node.rightMin, node.rightMax, invRd, rayOffset, 0.0, tMax);
   if (min(leftT, rightT) == RT_INF) return bvhTraversalPop(state);
   bool leftNear = leftT <= rightT;
   uint nearID = leftNear ? node.leftChild : node.rightChild;
   if (max(leftT, rightT) != RT_INF) {
      bvhTraversalDescendBoth(state, nearID, leftNear ? node.rightChild : node.leftChild);
   } else {
      state.nodeID = nearID;
   }
   return state.overflow;
}
#endif

bool bvhNextLeaf(inout BVHTraversalState state, vec3 invRd, vec3 rayOffset, float tMax) {
   while (isInternalNode(state.nodeID)) {
      if (bvhTraverseNode(state, invRd, rayOffset, tMax)) return false;
   }
   return true;
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

bool intersectQuadGeom(QuadGeometry qg, vec3 ro, vec3 rd, inout float tHit, out vec2 hitBary, out int hitTri) {
   vec3 p0, p1, p2, p3;
   unpackQuadGeometryPositions(qg, p0, p1, p2, p3);

   float t;
   vec2 bary;

   if (intersectTri(ro, rd, p0, p1, p2, t, bary) && t < tHit) {
      tHit = t;
      hitBary = bary;
      hitTri = 0;
      return true;
   }
   if (intersectTri(ro, rd, p0, p2, p3, t, bary) && t < tHit) {
      tHit = t;
      hitBary = bary;
      hitTri = 1;
      return true;
   }
   return false;
}

// Local helpers — load each stream once, then read fields from the local copy.
uint qaMaterialBits(QuadAttributes qa) {
   return (qa.materialTexture >> 8u) & 0x7Fu;
}
uint qaBlockID(QuadAttributes qa) {
   return qa.materialTexture & 0xFFu;
}
float qaEmission(QuadAttributes qa) {
   return float(qaMaterialBits(qa) & 0x0Fu);
}
bool qaAlphaTested(QuadAttributes qa) {
   return (qaMaterialBits(qa) & 0x10u) != 0u;
}
bool qaTranslucent(QuadAttributes qa) {
   return (qaMaterialBits(qa) & 0x20u) != 0u;
}
bool qaPlayerModel(QuadAttributes qa) {
   return (qaMaterialBits(qa) & 0x40u) != 0u;
}

vec2 qaUV(QuadAttributes qa, uint i) {
   vec2 uv0 = unpackHalf2x16(qa.uv0);
   if (i == 0u) return uv0;
   vec2 uv1 = unpackHalf2x16(qa.uv1);
   if (i == 1u) return uv1;
   vec2 uv2 = unpackHalf2x16(qa.uv2);
   if (i == 2u || (qa.materialTexture & 0x80000000u) != 0u) return uv2;
   return uv0 + uv2 - uv1;
}

vec3 qgTint(QuadGeometry qg) {
   return unpackRGB565(qg.d3zTint >> 16u);
}

vec2 interpolateUV(QuadAttributes qa, vec2 bary, int triIndex) {
   vec2 uv0 = qaUV(qa, 0u);
   float w = 1.0 - bary.x - bary.y;
   if (triIndex == 0) {
      return uv0 * w + qaUV(qa, 1u) * bary.x + qaUV(qa, 2u) * bary.y;
   } else {
      return uv0 * w + qaUV(qa, 2u) * bary.x + qaUV(qa, 3u) * bary.y;
   }
}

vec3 interpolateTint(QuadGeometry qg) {
   return qgTint(qg);
}

vec4 sampleQuadTexture(QuadAttributes qa, vec2 uv) {
   uint texID = (qa.materialTexture >> 15u) & 0xFFFFu;
   if (texID == 0u) {
      return texture(blockAtlas, uv);
   }

   #ifdef ENTITY_TEXTURES
   return sampleEntityTexture(texID, uv);
   #else
   return vec4(1.0);
   #endif
}

bool quadAlphaSkipsIntersection(QuadAttributes qa, vec2 bary, int triIndex) {
   #ifdef ALPHA_TEST
   bool alphaTested = qaAlphaTested(qa);
   if (!alphaTested) return false;

   vec2 uv = interpolateUV(qa, bary, triIndex);
   return sampleQuadTexture(qa, uv).a < alphaTestRef;
   #else
   return false;
   #endif
}

const float DIAGONAL = sqrt(3.0);

TraceResult traceBVH(vec3 ro, vec3 rd, bool skipPlayer) {
   float tHit = (8.0 + (far * 16.0)) * DIAGONAL;
   uint hitQuad = INVALID_ID;
   vec2 hitBary = vec2(0.0);
   int hitTri = 0;

   uint sceneRoot = control.rootClusterID;
   if (sceneRoot != INVALID_ID) {
      vec3 invRd = safeInvDir(rd);
      vec3 rayOffset = -ro * invRd;
      uint numQuads = control.sortTotal;
      BVHTraversalState traversal;
      bvhTraversalInit(traversal, sceneRoot);
      while (bvhNextLeaf(traversal, invRd, rayOffset, tHit)) {
         uint prim = getClusterPrimID(traversal.nodeID);
         if (prim < numQuads) {
            QuadGeometry qg = quadGeometry[prim];
            vec2 bary;
            int tri;
            float candidateT = tHit;
            if (intersectQuadGeom(qg, ro, rd, candidateT, bary, tri)) {
               QuadAttributes qa = quadAttributes[prim];
               if (!(skipPlayer && qaPlayerModel(qa)) && !quadAlphaSkipsIntersection(qa, bary, tri)) {
                  tHit = candidateT;
                  hitQuad = prim;
                  hitBary = bary;
                  hitTri = tri;
               }
            }
         }
         if (bvhTraversalPop(traversal)) break;
      }
   }

   TraceResult res;
   res.t = tHit;
   res.quadID = hitQuad;
   res.triIndex = hitTri;
   res.hit = (hitQuad != INVALID_ID);

   if (res.hit) {
      QuadGeometry qg = quadGeometry[hitQuad];
      QuadAttributes qa = quadAttributes[hitQuad];

      vec3 p0, p1, p2, p3;
      unpackQuadGeometryPositions(qg, p0, p1, p2, p3);

      vec3 n = (hitTri == 0)
         ? normalize(cross(p1 - p0, p2 - p0)) : normalize(cross(p2 - p0, p3 - p0));
      if (dot(n, rd) > 0.0) n = -n;
      res.normal = n;

      res.uv = interpolateUV(qa, hitBary, hitTri);
      res.vertexData = vec4(interpolateTint(qg), qaEmission(qa));
      res.textureID = (qa.materialTexture >> 15u) & 0xFFFFu;
      res.translucent = qaTranslucent(qa);
      res.waterSurface = qaBlockID(qa) == 1u;
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

bool shadowTriHit(QuadGeometry qg, QuadAttributes qa, vec2 bary, int triIndex, inout vec3 tint) {
   if (quadAlphaSkipsIntersection(qa, bary, triIndex)) return false;

   if (qaTranslucent(qa)) {
      if (qaBlockID(qa) == 1u) {
         return false;
      }
      vec2 hitUV = interpolateUV(qa, bary, triIndex);
      vec4 texSample = sampleQuadTexture(qa, hitUV);
      vec3 vertexTint = interpolateTint(qg);
      vec3 texTint = mix(vec3(1.0), texSample.rgb, step(alphaTestRef, texSample.a));
      float transparency = 1.0 - texSample.a;
      tint *= mix(vec3(0.0), pow(texTint * vertexTint, vec3(2.2)), transparency);
      return tint == vec3(0.0);
   } else {
      return true;
   }
}

bool traceHardShadowVisible(vec3 ro, vec3 rd, float maxDist) {
   uint sceneRoot = control.rootClusterID;
   if (sceneRoot == INVALID_ID) return true;

   vec3 invRd = safeInvDir(rd);
   vec3 rayOffset = -ro * invRd;
   vec3 tint = vec3(1.0);

   uint numQuads = control.sortTotal;
   BVHTraversalState traversal;
   bvhTraversalInit(traversal, sceneRoot);
   while (bvhNextLeaf(traversal, invRd, rayOffset, maxDist)) {
      uint prim = getClusterPrimID(traversal.nodeID);
      if (prim < numQuads) {
         QuadGeometry qg = quadGeometry[prim];
         vec3 p0, p1, p2, p3;
         unpackQuadGeometryPositions(qg, p0, p1, p2, p3);
         float t0, t1;
         vec2 b0, b1;
         bool h0 = intersectTri(ro, rd, p0, p1, p2, t0, b0) && t0 < maxDist;
         bool h1 = intersectTri(ro, rd, p0, p2, p3, t1, b1) && t1 < maxDist;
         if (h0 || h1) {
            QuadAttributes qa = quadAttributes[prim];
            if (h0) {
               if (shadowTriHit(qg, qa, b0, 0, tint)) return false;
               if (any(lessThan(tint, vec3(0.999)))) return false;
            }
            if (h1) {
               if (shadowTriHit(qg, qa, b1, 1, tint)) return false;
               if (any(lessThan(tint, vec3(0.999)))) return false;
            }
         }
      }
      if (bvhTraversalPop(traversal)) break;
   }

   return true;
}

#endif
