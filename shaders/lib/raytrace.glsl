#ifndef RAYTRACE_INCLUDE_GUARD
#define RAYTRACE_INCLUDE_GUARD

#include "/lib/textures.glsl"

#define ALPHA_TEST

#ifdef ALPHA_TEST
const float ALPHA_THRESHOLD = 0.5;
#endif

const int BVH_STACK_SIZE = 32;
const float RT_INF = 3.402823466e+38;

struct TraceResult {
   float t;
   vec3 normal;
   bool hit;
   uint depth; // BVH depth at hit
   uint quadID; // quad index that was hit
   vec2 uv; // interpolated texture coordinate at hit
   vec4 vertexData; // decoded vertex data (rgb=color, a=emission)
   uint blockID; // block ID at hit
   uint textureID; // 0 = block atlas, >0 = entity texture slot+1
   vec2 bary; // barycentric coordinates of hit (for deferred computation)
   int triIndex; // 0 = tri(p0,p1,p2), 1 = tri(p0,p2,p3)
   bool translucent; // translucent surface (glass-like, IOR 1.5)
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
   float w = 1.0 - bary.x - bary.y;
   if (triIndex == 0) {
      return quads[quadID].v1.uv * w + quads[quadID].v2.uv * bary.x + quads[quadID].v3.uv * bary.y;
   } else {
      return quads[quadID].v1.uv * w + quads[quadID].v3.uv * bary.x + quads[quadID].v4.uv * bary.y;
   }
}

const float DIAGONAL = sqrt(3.0);

TraceResult traceBVH(vec3 ro, vec3 rd) {
   TraceResult res;
   res.t = (8.0 + (far * 16.0)) * DIAGONAL;
   res.normal = vec3(0.0);
   res.hit = false;
   res.depth = 0u;
   res.quadID = INVALID_ID;
   res.uv = vec2(0.0);
   res.vertexData = vec4(0.0);
   res.blockID = 0u;
   res.textureID = 0u;
   res.bary = vec2(0.0);
   res.triIndex = 0;
   res.translucent = false;

   uint rootID = control.rootClusterID;
   if (rootID == INVALID_ID) return res;

   vec3 invRd = safeInvDir(rd);

   uint stack[BVH_STACK_SIZE];
   int sp = 0;

   uint nodeID = rootID;
   uint numQuads = control.sortTotal;
   uint steps = 0u;

   for (int iter = 0; iter < 512; iter++) {
      if (nodeID == INVALID_ID) {
         if (sp == 0) break;
         --sp;
         nodeID = stack[sp];
         continue;
      }

      steps++;
      uint prim = getClusterPrimID(nodeID);

      if (!isInternalNode(nodeID)) {
         if (prim < numQuads) {
            #ifdef ALPHA_TEST
            float prevT = res.t;
            #endif
            vec2 hitBary;
            int hitTri;
            if (intersectQuadGeom(prim, ro, rd, res.t, hitBary, hitTri)) {
               #ifdef ALPHA_TEST
               bool transparent = false;
               if (isAlphaTested(quads[prim].v1.encodedVertex)) {
                  vec2 hitUV = interpolateQuadUV(prim, hitBary, hitTri);
                  uint hitTexID = quads[prim].v1.textureID;
                  if (hitTexID == 0u) {
                     transparent = texture(blockAtlas, hitUV).a < ALPHA_THRESHOLD;
                  }
                  #ifdef ENTITY_TEXTURES
                  else {
                     transparent = sampleEntityTexture(hitTexID, hitUV).a < ALPHA_THRESHOLD;
                  }
                  #endif
               }
               if (transparent) {
                  res.t = prevT;
               } else
               #endif
               {
                  res.hit = true;
                  res.depth = steps;
                  res.quadID = prim;
                  res.bary = hitBary;
                  res.triIndex = hitTri;
               }
            }
         }
         nodeID = INVALID_ID;
         continue;
      }

      // Internal node - bounds check the BVH node index
      if (prim >= control.numBVH2Nodes) {
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
            stack[sp] = farID;
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

      res.uv = interpolateQuadUV(res.quadID, res.bary, res.triIndex);
      res.vertexData = decodeVertexData(quads[res.quadID].v1.encodedVertex);
      res.blockID = quads[res.quadID].v1.blockID;
      res.textureID = quads[res.quadID].v1.textureID;
      res.translucent = isTranslucent(quads[res.quadID].v1.encodedVertex);
   }

   return res;
}

vec3 traceShadowTinted(vec3 ro, vec3 rd, float maxDist) {
   uint rootID = control.rootClusterID;
   if (rootID == INVALID_ID) return vec3(1.0);

   vec3 invRd = safeInvDir(rd);
   vec3 tint = vec3(1.0);

   uint stack[BVH_STACK_SIZE];
   int sp = 0;

   uint nodeID = rootID;
   uint numQuads = control.sortTotal;

   for (int iter = 0; iter < 512; iter++) {
      if (nodeID == INVALID_ID) {
         if (sp == 0) break;
         --sp;
         nodeID = stack[sp];
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
               if (isTranslucent(encoded)) {
                  vec2 hitUV = interpolateQuadUV(prim, bary, 0);
                  uint hitTexID = quads[prim].v1.textureID;
                  vec4 texSample = (hitTexID == 0u) ? texture(blockAtlas, hitUV) : vec4(1.0);
                  float transparency = 1.0 - texSample.a;
                  tint *= mix(vec3(0.0), texSample.rgb * decodeVertexData(encoded).rgb, transparency);
                  if (tint == vec3(0.0)) return vec3(0.0);
               } else {
                  #ifdef ALPHA_TEST
                  if (!isAlphaTested(encoded)) return vec3(0.0);
                  vec2 hitUV = interpolateQuadUV(prim, bary, 0);
                  uint hitTexID = quads[prim].v1.textureID;
                  if (hitTexID == 0u) {
                     if (texture(blockAtlas, hitUV).a >= ALPHA_THRESHOLD) return vec3(0.0);
                  } else {
                     #ifdef ENTITY_TEXTURES
                     if (sampleEntityTexture(hitTexID, hitUV).a >= ALPHA_THRESHOLD) return vec3(0.0);
                     #else
                     return vec3(0.0);
                     #endif
                  }
                  #else
                  return vec3(0.0);
                  #endif
               }
            }
            if (intersectTri(ro, rd, p0, p2, p3, t, bary) && t < maxDist) {
               if (isTranslucent(encoded)) {
                  vec2 hitUV = interpolateQuadUV(prim, bary, 1);
                  uint hitTexID = quads[prim].v1.textureID;
                  vec4 texSample = (hitTexID == 0u) ? texture(blockAtlas, hitUV) : vec4(1.0);
                  float transparency = 1.0 - texSample.a;
                  tint *= mix(vec3(0.0), texSample.rgb * decodeVertexData(encoded).rgb, transparency);
                  if (tint == vec3(0.0)) return vec3(0.0);
               } else {
                  #ifdef ALPHA_TEST
                  if (!isAlphaTested(encoded)) return vec3(0.0);
                  vec2 hitUV = interpolateQuadUV(prim, bary, 1);
                  uint hitTexID = quads[prim].v1.textureID;
                  if (hitTexID == 0u) {
                     if (texture(blockAtlas, hitUV).a >= ALPHA_THRESHOLD) return vec3(0.0);
                  } else {
                     #ifdef ENTITY_TEXTURES
                     if (sampleEntityTexture(hitTexID, hitUV).a >= ALPHA_THRESHOLD) return vec3(0.0);
                     #else
                     return vec3(0.0);
                     #endif
                  }
                  #else
                  return vec3(0.0);
                  #endif
               }
            }
         }
         nodeID = INVALID_ID;
         continue;
      }

      if (prim >= control.numBVH2Nodes) {
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
            stack[sp] = farID;
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

bool traceShadow(vec3 ro, vec3 rd, float maxDist) {
   return traceShadowTinted(ro, rd, maxDist) == vec3(0.0);
}

// Debug: trace BVH and return box color based on AABB surface area of first hit
vec4 traceBVHDebugBoxes(vec3 ro, vec3 rd) {
   uint rootID = control.rootClusterID;
   if (rootID == INVALID_ID) return vec4(0.0);

   vec3 invRd = safeInvDir(rd);
   float maxT = (8.0 + (far * 16.0)) * DIAGONAL;
   uint numQuads = control.sortTotal;

   uint stack[BVH_STACK_SIZE];
   int sp = 0;

   uint nodeID = rootID;
   float closestT = maxT;
   float closestSA = 0.0; // surface area of the closest-hit AABB
   bool anyHit = false;

   for (int iter = 0; iter < 512; iter++) {
      if (nodeID == INVALID_ID) {
         if (sp == 0) break;
         --sp;
         nodeID = stack[sp];
         continue;
      }

      uint prim = getClusterPrimID(nodeID);

      if (!isInternalNode(nodeID)) {
         // Leaf - test its AABB for debug visualization
         if (prim < numQuads) {
            AABB a = aabbs[prim];
            float t = intersectAABB(a.minBounds, a.maxBounds, ro, invRd, 0.001, closestT);
            if (t != RT_INF && t < closestT) {
               closestT = t;
               closestSA = computeSurfaceArea(a.minBounds, a.maxBounds);
               anyHit = true;
            }
         }
         nodeID = INVALID_ID;
         continue;
      }

      if (prim >= control.numBVH2Nodes) {
         nodeID = INVALID_ID;
         continue;
      }

      BVH2Node node = bvh2Nodes[prim];
      uint c0 = node.leftChild;
      uint c1 = node.rightChild;

      float t0 = intersectAABB(node.c0Min, node.c0Max, ro, invRd, 0.001, closestT);
      float t1 = intersectAABB(node.c1Min, node.c1Max, ro, invRd, 0.001, closestT);

      bool h0 = (t0 != RT_INF);
      bool h1 = (t1 != RT_INF);

      if (h0 && h1) {
         bool leftFirst = (t0 <= t1);
         uint nearID = leftFirst ? c0 : c1;
         uint farID = leftFirst ? c1 : c0;

         if (sp < BVH_STACK_SIZE) {
            stack[sp] = farID;
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

   if (anyHit) {
      // Color by AABB surface area: small (blue) -> medium (green) -> large (red)
      // log scale for better distribution; 1 block² to ~4096 block² range
      float logSA = clamp(log2(max(closestSA, 1.0)) / 12.0, 0.0, 1.0);
      vec3 color;
      if (logSA < 0.5) {
         color = mix(vec3(0.2, 0.4, 1.0), vec3(0.2, 1.0, 0.2), logSA * 2.0);
      } else {
         color = mix(vec3(0.2, 1.0, 0.2), vec3(1.0, 0.2, 0.2), (logSA - 0.5) * 2.0);
      }
      return vec4(color, 0.6);
   }
   return vec4(0.0);
}

#endif
