#ifndef RAYTRACE_INCLUDE_GUARD
#define RAYTRACE_INCLUDE_GUARD

#include "/lib/textures.glsl"

#define ALPHA_TEST

#ifdef ALPHA_TEST
uniform float alphaTestRef = 0.1;
#endif

// Water absorption coefficients (per-block distance) for Beer-Lambert
const vec3 WATER_ABSORPTION = vec3(0.45, 0.07, 0.04);

const int BVH_STACK_SIZE = 24;
const int BVH_WG_SIZE = 64;
shared uint shared_stack[BVH_STACK_SIZE * BVH_WG_SIZE];
const float RT_INF = 3.402823466e+38;

struct TraceResult {
   float t;
   vec3 normal;
   bool hit;
   uint quadID; // quad index that was hit
   vec2 uv; // interpolated texture coordinate at hit
   vec4 vertexData; // decoded vertex data (rgb=color, a=emission)
   uint textureID; // 0 = block atlas, >0 = entity texture slot+1
   int triIndex; // 0 = tri(p0,p1,p2), 1 = tri(p0,p2,p3)
   bool translucent; // translucent surface (glass-like, IOR 1.5)
   bool waterSurface; // water surface (block ID 1)
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
   p0 = qp.d0.xyz;
   p1 = vec3(qp.d0.w, qp.d1.xy);
   p2 = vec3(qp.d1.zw, qp.d2.x);
   p3 = qp.d2.yzw;
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

vec2 interpolateQuadUV(uint quadID, vec2 bary, int triIndex) {
   vec2 uv1 = quads[quadID].v1.uv;
   float w = 1.0 - bary.x - bary.y;
   if (triIndex == 0) {
      return uv1 * w + quads[quadID].v2.uv * bary.x + quads[quadID].v3.uv * bary.y;
   } else {
      return uv1 * w + quads[quadID].v3.uv * bary.x + quads[quadID].v4.uv * bary.y;
   }
}

const float DIAGONAL = sqrt(3.0);

TraceResult traceBVH(vec3 ro, vec3 rd, bool skipPlayer) {
   TraceResult res;
   res.t = (8.0 + (far * 16.0)) * DIAGONAL;
   res.hit = false;
   res.quadID = INVALID_ID;

   uint rootID = control.rootClusterID;
   if (rootID == INVALID_ID) return res;

   vec3 invRd = safeInvDir(rd);

   int sp = 0;
   uint tid = gl_LocalInvocationIndex;

   uint nodeID = rootID;
   uint numQuads = control.sortTotal;
   vec2 resBary = vec2(0.0);

   for (int iter = 0; iter < BVH_STACK_SIZE * BVH_STACK_SIZE; iter++) {
      if (nodeID == INVALID_ID) {
         if (sp == 0) break;
         --sp;
         nodeID = shared_stack[sp * BVH_WG_SIZE + tid];
         continue;
      }

      uint prim = getClusterPrimID(nodeID);

      if (!isInternalNode(nodeID)) {
         if (prim < numQuads) {
            #ifdef ALPHA_TEST
            float prevT = res.t;
            uint encoded = quads[prim].v1.encodedVertex; // prefetch before intersection
            #else
            uint encoded = quads[prim].v1.encodedVertex;
            #endif
            if (skipPlayer && isPlayerModel(encoded)) {
               nodeID = INVALID_ID;
               continue;
            }
            vec2 hitBary;
            int hitTri;
            if (intersectQuadGeom(prim, ro, rd, res.t, hitBary, hitTri)) {
               #ifdef ALPHA_TEST
               bool transparent = false;
               if (isAlphaTested(encoded)) {
                  vec2 hitUV = interpolateQuadUV(prim, hitBary, hitTri);
                  uint hitTexID = quads[prim].v1.textureID;
                  if (hitTexID == 0u) {
                     transparent = texture(blockAtlas, hitUV).a < alphaTestRef;
                  }
                  #ifdef ENTITY_TEXTURES
                  else {
                     transparent = sampleEntityTexture(hitTexID, hitUV).a < alphaTestRef;
                  }
                  #endif
               }
               if (transparent) {
                  res.t = prevT;
               } else
               #endif
               {
                  res.hit = true;
                  res.quadID = prim;
                  res.triIndex = hitTri;
                  resBary = hitBary;
               }
            }
         }
         nodeID = INVALID_ID;
         continue;
      }

      BVH2Node node = bvh2Nodes[prim];
      uint c0 = node.leftChild;
      uint c1 = node.rightChild;

      float t0 = intersectAABB(node.c0Min, node.c0Max, ro, invRd, 0.0, res.t);
      float t1 = intersectAABB(node.c1Min, node.c1Max, ro, invRd, 0.0, res.t);

      bool h0 = (t0 != RT_INF);
      bool h1 = (t1 != RT_INF);

      if (h0 && h1) {
         bool leftFirst = (t0 <= t1);
         uint nearID = leftFirst ? c0 : c1;
         uint farID = leftFirst ? c1 : c0;

         if (sp < BVH_STACK_SIZE) {
            shared_stack[sp * BVH_WG_SIZE + tid] = farID;
            sp++;
         }
         nodeID = nearID;
      } else if (h0) {
         nodeID = c0;
      } else if (h1) {
         nodeID = c1;
      } else {
         nodeID = INVALID_ID;
      }
   }

   if (res.hit) {
      vec3 p0, p1, p2, p3;
      decodeQuadPositions(res.quadID, p0, p1, p2, p3);

      if (res.triIndex == 0) {
         res.normal = normalize(cross(p1 - p0, p2 - p0));
      } else {
         res.normal = normalize(cross(p2 - p0, p3 - p0));
      }
      if (dot(res.normal, rd) > 0.0) res.normal = -res.normal;

      res.uv = interpolateQuadUV(res.quadID, resBary, res.triIndex);
      uint encoded = quads[res.quadID].v1.encodedVertex;
      res.vertexData = decodeVertexData(encoded);
      res.textureID = quads[res.quadID].v1.textureID;
      res.translucent = isTranslucent(encoded);
      res.waterSurface = quads[res.quadID].v1.blockID == 1u;
   }

   return res;
}

TraceResult traceBVH(vec3 ro, vec3 rd) {
   return traceBVH(ro, rd, false);
}

// Evaluate a shadow tri hit for the tinted shadow ray.
// Returns true if the ray is fully blocked (tint zeroed or opaque hit).
bool shadowTriHit(uint prim, uint encoded, vec2 bary, int triIndex, float hitT, inout vec3 tint) {
   if (isTranslucent(encoded)) {
      // Water: apply absorption-based tinting
      if (quads[prim].v1.blockID == 1u) {
         vec3 waterTint = pow(decodeVertexData(encoded).rgb, vec3(2.2));
         tint *= waterTint * exp(-WATER_ABSORPTION * max(hitT, 0.5));
         return tint == vec3(0.0);
      }
      vec2 hitUV = interpolateQuadUV(prim, bary, triIndex);
      uint hitTexID = quads[prim].v1.textureID;
      vec4 texSample = (hitTexID == 0u) ? texture(blockAtlas, hitUV) : vec4(1.0);
      float transparency = 1.0 - texSample.a;
      tint *= mix(vec3(0.0), pow(texSample.rgb * decodeVertexData(encoded).rgb, vec3(2.2)), transparency);
      return tint == vec3(0.0);
   } else {
      #ifdef ALPHA_TEST
      if (!isAlphaTested(encoded)) return true;
      vec2 hitUV = interpolateQuadUV(prim, bary, triIndex);
      uint hitTexID = quads[prim].v1.textureID;
      if (hitTexID == 0u) {
         return texture(blockAtlas, hitUV).a >= alphaTestRef;
      } else {
         #ifdef ENTITY_TEXTURES
         return sampleEntityTexture(hitTexID, hitUV).a >= alphaTestRef;
         #else
         return true;
         #endif
      }
      #else
      return true;
      #endif
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
         --sp;
         nodeID = shared_stack[sp * BVH_WG_SIZE + tid];
         continue;
      }

      uint prim = getClusterPrimID(nodeID);

      if (!isInternalNode(nodeID)) {
         if (prim < numQuads) {
            vec3 p0, p1, p2, p3;
            decodeQuadPositions(prim, p0, p1, p2, p3);
            uint encoded = quads[prim].v1.encodedVertex;

            float t;
            vec2 bary;
            if (intersectTri(ro, rd, p0, p1, p2, t, bary) && t < maxDist) {
               if (shadowTriHit(prim, encoded, bary, 0, t, tint)) return vec3(0.0);
            }
            if (intersectTri(ro, rd, p0, p2, p3, t, bary) && t < maxDist) {
               if (shadowTriHit(prim, encoded, bary, 1, t, tint)) return vec3(0.0);
            }
         }
         nodeID = INVALID_ID;
         continue;
      }

      BVH2Node node = bvh2Nodes[prim];
      uint c0 = node.leftChild;
      uint c1 = node.rightChild;

      float t0 = intersectAABB(node.c0Min, node.c0Max, ro, invRd, 0.0, maxDist);
      float t1 = intersectAABB(node.c1Min, node.c1Max, ro, invRd, 0.0, maxDist);

      bool h0 = (t0 != RT_INF);
      bool h1 = (t1 != RT_INF);

      if (h0 && h1) {
         bool leftFirst = (t0 <= t1);
         uint nearID = leftFirst ? c0 : c1;
         uint farID = leftFirst ? c1 : c0;

         if (sp < BVH_STACK_SIZE) {
            shared_stack[sp * BVH_WG_SIZE + tid] = farID;
            sp++;
         }
         nodeID = nearID;
      } else if (h0) {
         nodeID = c0;
      } else if (h1) {
         nodeID = c1;
      } else {
         nodeID = INVALID_ID;
      }
   }

   return tint;
}

#endif
