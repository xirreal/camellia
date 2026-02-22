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

bool intersectQuad(uint quadID, vec3 ro, vec3 rd, inout float tHit, out vec3 nHit, out vec2 hitUV, out vec4 hitVertexData, out uint hitBlockID, out uint hitTextureID) {
   Quad q = quads[quadID];
   vec3 p0 = q.v1.position;
   vec3 p1 = q.v2.position;
   vec3 p2 = q.v3.position;
   vec3 p3 = q.v4.position;

   float t;
   vec2 bary;
   bool hit = false;

   if (intersectTri(ro, rd, p0, p1, p2, t, bary) && t < tHit) {
      tHit = t;
      hit = true;
      nHit = normalize(cross(p1 - p0, p2 - p0));
      // Interpolate UVs: v0*(1-u-v) + v1*u + v2*v
      hitUV = q.v1.uv * (1.0 - bary.x - bary.y) + q.v2.uv * bary.x + q.v3.uv * bary.y;
      hitVertexData = decodeVertexData(q.v1.encodedVertex);
      hitBlockID = q.v1.blockID;
      hitTextureID = q.v1.textureID;
   }
   if (intersectTri(ro, rd, p0, p2, p3, t, bary) && t < tHit) {
      tHit = t;
      hit = true;
      nHit = normalize(cross(p2 - p0, p3 - p0));
      // Interpolate UVs: v0*(1-u-v) + v2*u + v3*v
      hitUV = q.v1.uv * (1.0 - bary.x - bary.y) + q.v3.uv * bary.x + q.v4.uv * bary.y;
      hitVertexData = decodeVertexData(q.v1.encodedVertex);
      hitBlockID = q.v1.blockID;
      hitTextureID = q.v1.textureID;
   }

   if (hit && dot(nHit, rd) > 0.0) nHit = -nHit;
   return hit;
}

// Load AABB for a child cluster ID with bounds checking.
// Returns false if the ID is invalid or out of range (sets degenerate AABB).
bool loadChildAABB(uint childID, uint numQuads, out vec3 bMin, out vec3 bMax) {
   if (childID == INVALID_ID) {
      bMin = vec3(RT_INF);
      bMax = vec3(-RT_INF);
      return false;
   }

   uint prim = getClusterPrimID(childID);

   if (isInternalNode(childID)) {
      if (prim >= control.numBVH2Nodes) {
         bMin = vec3(RT_INF);
         bMax = vec3(-RT_INF);
         return false;
      }
      BVH2Node n = bvh2Nodes[prim];
      bMin = n.aabbMin;
      bMax = n.aabbMax;
   } else {
      if (prim >= numQuads) {
         bMin = vec3(RT_INF);
         bMax = vec3(-RT_INF);
         return false;
      }
      AABB a = aabbs[prim];
      bMin = a.minBounds;
      bMax = a.maxBounds;
   }
   return true;
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
         // Leaf node - bounds check the quad index
         if (prim < numQuads) {
            vec3 nHit;
            vec2 hitUV;
            vec4 hitVD;
            uint hitBID;
            uint hitTextureID;
            #ifdef ALPHA_TEST
            float prevT = res.t;
            #endif
            if (intersectQuad(prim, ro, rd, res.t, nHit, hitUV, hitVD, hitBID, hitTextureID)) {
               #ifdef ALPHA_TEST
               bool transparent = false;
               if (hitTextureID == 0u) {
                  transparent = texture(blockAtlas, hitUV).a < ALPHA_THRESHOLD;
               }
               #ifdef ENTITY_TEXTURES
               else {
                  transparent = sampleEntityTexture(hitTextureID, hitUV).a < ALPHA_THRESHOLD;
               }
               #endif
               if (transparent) {
                  res.t = prevT;
               } else
               #endif
               {
                  res.normal = nHit;
                  res.hit = true;
                  res.depth = steps;
                  res.quadID = prim;
                  res.uv = hitUV;
                  res.vertexData = hitVD;
                  res.blockID = hitBID;
                  res.textureID = hitTextureID;
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

      vec3 b0min, b0max, b1min, b1max;
      loadChildAABB(c0, numQuads, b0min, b0max);
      loadChildAABB(c1, numQuads, b1min, b1max);

      float t0 = intersectAABB(b0min, b0max, ro, invRd, 0.0, res.t);
      float t1 = intersectAABB(b1min, b1max, ro, invRd, 0.0, res.t);

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

   return res;
}

bool traceShadow(vec3 ro, vec3 rd, float maxDist) {
   uint rootID = control.rootClusterID;
   if (rootID == INVALID_ID) return false;

   vec3 invRd = safeInvDir(rd);

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
            Quad q = quads[prim];
            vec3 p0 = q.v1.position;
            vec3 p1 = q.v2.position;
            vec3 p2 = q.v3.position;
            vec3 p3 = q.v4.position;

            float t;
            vec2 bary;
            if (intersectTri(ro, rd, p0, p1, p2, t, bary) && t < maxDist) {
               #ifdef ALPHA_TEST
               vec2 hitUV = q.v1.uv * (1.0 - bary.x - bary.y) + q.v2.uv * bary.x + q.v3.uv * bary.y;
               if (q.v1.textureID == 0u) {
                  if (texture(blockAtlas, hitUV).a >= ALPHA_THRESHOLD) return true;
               }
               else {
                  #ifdef ENTITY_TEXTURES
                  if (sampleEntityTexture(q.v1.textureID, hitUV).a >= ALPHA_THRESHOLD) return true;
                  #else
                  return true;
                  #endif
               }
               #else
               return true;
               #endif
            }
            if (intersectTri(ro, rd, p0, p2, p3, t, bary) && t < maxDist) {
               #ifdef ALPHA_TEST
               vec2 hitUV = q.v1.uv * (1.0 - bary.x - bary.y) + q.v3.uv * bary.x + q.v4.uv * bary.y;
               if (q.v1.textureID == 0u) {
                  if (texture(blockAtlas, hitUV).a >= ALPHA_THRESHOLD) return true;
               } else {
                  #ifdef ENTITY_TEXTURES
                  if (sampleEntityTexture(q.v1.textureID, hitUV).a >= ALPHA_THRESHOLD) return true;
                  #else
                  return true;
                  #endif
               }
               #else
               return true;
               #endif
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

      vec3 b0min, b0max, b1min, b1max;
      loadChildAABB(c0, numQuads, b0min, b0max);
      loadChildAABB(c1, numQuads, b1min, b1max);

      float t0 = intersectAABB(b0min, b0max, ro, invRd, 0.0, maxDist);
      float t1 = intersectAABB(b1min, b1max, ro, invRd, 0.0, maxDist);

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

   return false;
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

      vec3 b0min, b0max, b1min, b1max;
      loadChildAABB(c0, numQuads, b0min, b0max);
      loadChildAABB(c1, numQuads, b1min, b1max);

      float t0 = intersectAABB(b0min, b0max, ro, invRd, 0.001, closestT);
      float t1 = intersectAABB(b1min, b1max, ro, invRd, 0.001, closestT);

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
