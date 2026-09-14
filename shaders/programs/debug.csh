layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba32f) uniform writeonly image2D colorimg5;

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform sampler2D blockAtlas;

#include "/lib/core/storage.glsl"
#include "/lib/bvh/hploc.glsl"
#include "/lib/bvh/raytrace.glsl"

vec3 TurboColormap(float x) {
   const vec4 kRedVec4 = vec4(0.13572138, 4.61539260, -42.66032258, 132.13108234);
   const vec4 kGreenVec4 = vec4(0.09140261, 2.19418839, 4.84296658, -14.18503333);
   const vec4 kBlueVec4 = vec4(0.10667330, 12.64194608, -60.58204836, 110.36276771);
   const vec2 kRedVec2 = vec2(-152.94239396, 59.28637943);
   const vec2 kGreenVec2 = vec2(4.27729857, 2.82956604);
   const vec2 kBlueVec2 = vec2(-89.90310912, 27.34824973);

   x = clamp(x, 0.0, 1.0);
   vec4 v4 = vec4(1.0, x, x * x, x * x * x);
   vec2 v2 = v4.zw * v4.z;

   return vec3(
      dot(v4, kRedVec4) + dot(v2, kRedVec2),
      dot(v4, kGreenVec4) + dot(v2, kGreenVec2),
      dot(v4, kBlueVec4) + dot(v2, kBlueVec2)
   );
}

vec3 debugBVH(vec3 ro, vec3 rd, bool skipPlayer) {
   uint costCounter = 0;
   float hitT = (8.0 + (far * 16.0)) * DIAGONAL;

   uint sceneRoot = control.rootClusterID;
   if (sceneRoot == INVALID_ID) return TurboColormap(0.0);

   vec3 invRd = safeInvDir(rd);
   vec3 rayOffset = -ro * invRd;
   bool overflow = false;

   {
      BVHTraversalState traversal;
      bvhTraversalInit(traversal, sceneRoot);
      while (true) {
      costCounter += 1;

      uint prim = getClusterPrimID(traversal.nodeID);

      if (!isInternalNode(traversal.nodeID)) {
         if (skipPlayer && quadPlayerModel(prim)) {
            if (bvhTraversalPop(traversal)) break;
            continue;
         }

         QuadGeometry qg = quadGeometry[prim];
         vec3 p0, p1, p2, p3;
         unpackQuadGeometryPositions(qg, p0, p1, p2, p3);

         float t;
         vec2 bary;

         costCounter += 5;

         if (intersectTri(ro, rd, p0, p1, p2, t, bary) && t < hitT) {
            hitT = t;
         }

         if (intersectTri(ro, rd, p0, p2, p3, t, bary) && t < hitT) {
            hitT = t;
         }
         if (bvhTraversalPop(traversal)) break;
         continue;
      }

      if (bvhTraverseNode(traversal, invRd, rayOffset, hitT)) break;
      }
      overflow = overflow || bvhTraversalOverflow(traversal);
   }

   if (overflow) return vec3(1.0, 0.0, 1.0);
   return TurboColormap(float(costCounter) / 150.0);
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   vec2 uv = (vec2(coord) + 0.5) / vec2(viewWidth, viewHeight);
   vec2 ndc = uv * 2.0 - 1.0;

   vec4 clipDir = vec4(ndc, 1.0, 1.0);
   vec4 viewDir = gbufferProjectionInverse * clipDir;
   viewDir.xyz /= viewDir.w;
   vec3 rd = normalize((mat3(gbufferModelViewInverse) * viewDir.xyz));
   vec3 ro = gbufferModelViewInverse[3].xyz;

   imageStore(colorimg5, coord, vec4(debugBVH(ro, rd, true), 1.0));
}
