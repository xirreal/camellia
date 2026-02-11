#ifndef RAYTRACE_INCLUDE_GUARD
#define RAYTRACE_INCLUDE_GUARD

const int BVH_STACK_SIZE = 32;
const float RT_INF = 1.0 / 0.0;

struct TraceResult {
   float t;
   vec3 normal;
   bool hit;
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

bool intersectTri(vec3 ro, vec3 rd, vec3 v0, vec3 v1, vec3 v2, out float t) {
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
   return true;
}

bool intersectQuad(uint quadID, vec3 ro, vec3 rd, inout float tHit, out vec3 nHit) {
   Quad q = quads[quadID];
   vec3 p0 = q.v1.position;
   vec3 p1 = q.v2.position;
   vec3 p2 = q.v3.position;
   vec3 p3 = q.v4.position;

   float t;
   bool hit = false;

   if (intersectTri(ro, rd, p0, p1, p2, t) && t < tHit) {
      tHit = t;
      hit = true;
      nHit = normalize(cross(p1 - p0, p2 - p0));
   }
   if (intersectTri(ro, rd, p0, p2, p3, t) && t < tHit) {
      tHit = t;
      hit = true;
      nHit = normalize(cross(p2 - p0, p3 - p0));
   }

   if (hit && dot(nHit, rd) > 0.0) nHit = -nHit;
   return hit;
}

const float DIAGONAL = sqrt(3.0);

TraceResult traceBVH(vec3 ro, vec3 rd) {
   TraceResult res;
   res.t = (8.0 + (far * 16.0)) * DIAGONAL;
   res.normal = vec3(0.0);
   res.hit = false;

   uint nodeCount = control.numBVH2Nodes;
   if (nodeCount == 0u) return res;

   vec3 invRd = safeInvDir(rd);

   uint stack[BVH_STACK_SIZE];
   int sp = 0;

   uint nodeID = makeClusterID(nodeCount - 1u, GEOM_ID_BVH2);

   for (int iter = 0; iter < 256; iter++) {
      if (nodeID == INVALID_ID) {
         if (sp == 0) break;
         nodeID = stack[--sp];
         continue;
      }

      uint geom = getClusterGeomID(nodeID);
      uint prim = getClusterPrimID(nodeID);

      if (geom != GEOM_ID_BVH2) {
         vec3 nHit;
         if (intersectQuad(prim, ro, rd, res.t, nHit)) {
            res.normal = nHit;
            res.hit = true;
         }
         nodeID = INVALID_ID;
         continue;
      }

      BVH2Node node = bvh2Nodes[prim];

      vec3 b0min, b0max, b1min, b1max;
      uint c0 = node.leftChild;
      uint c1 = node.rightChild;

      uint g0 = getClusterGeomID(c0);
      uint p0 = getClusterPrimID(c0);
      if (g0 == GEOM_ID_BVH2) {
         BVH2Node n0 = bvh2Nodes[p0];
         b0min = n0.aabbMin;
         b0max = n0.aabbMax;
      } else {
         AABB a0 = aabbs[p0];
         b0min = a0.minBounds;
         b0max = a0.maxBounds;
      }

      uint g1 = getClusterGeomID(c1);
      uint p1 = getClusterPrimID(c1);
      if (g1 == GEOM_ID_BVH2) {
         BVH2Node n1 = bvh2Nodes[p1];
         b1min = n1.aabbMin;
         b1max = n1.aabbMax;
      } else {
         AABB a1 = aabbs[p1];
         b1min = a1.minBounds;
         b1max = a1.maxBounds;
      }

      float t0 = intersectAABB(b0min, b0max, ro, invRd, 0.0, res.t);
      float t1 = intersectAABB(b1min, b1max, ro, invRd, 0.0, res.t);

      bool h0 = (t0 != RT_INF);
      bool h1 = (t1 != RT_INF);

      if (h0 && h1) {
         bool leftFirst = (t0 <= t1);
         uint nearID = leftFirst ? c0 : c1;
         uint farID = leftFirst ? c1 : c0;

         if (sp < BVH_STACK_SIZE) {
            stack[sp++] = farID;
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

#endif
