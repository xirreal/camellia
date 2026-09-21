"""Compare traced banner albedo to Iris's raster blending on the GPU.

Save shaders/composite18.csh, then replace it with this script's --shader output.
Use MODE=4, ENABLE_GBUFFER_CAPTURE=true, ENTITY_TEXTURES=true, and a visible
banner with a gradient pattern. Reload in Iris, wait 10 frames, and use
Viewfinder to dump colortex5 with raw=true. Run this script with that .bin path.
Restore composite18.csh and the original options afterward. Test BVH_WIDTH=2/4.
"""

import math
import struct
import sys
from pathlib import Path


SHADER = """#version 460
layout(local_size_x = 8, local_size_y = 4) in;
layout(rgba32f) uniform writeonly image2D colorimg5;
uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform sampler2D blockAtlas;
uniform sampler2D colortex8;
#include "/lib/core/storage.glsl"
#define BVH_WG_SIZE 32
#include "/lib/bvh/raytrace.glsl"

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   if (any(greaterThanEqual(coord, ivec2(viewWidth, viewHeight)))) return;
   imageStore(colorimg5, coord, vec4(0.0));
   vec2 ndc = (vec2(coord) + 0.5) / vec2(viewWidth, viewHeight) * 2.0 - 1.0;
   vec4 viewDir = gbufferProjectionInverse * vec4(ndc, 1.0, 1.0);
   vec3 rd = normalize(mat3(gbufferModelViewInverse) * (viewDir.xyz / viewDir.w));
   vec3 ro = gbufferModelViewInverse[3].xyz;
   TraceResult hit = traceBVH(ro, rd, true);
   if (!hit.hit || quadBlockID(hit.quadID) != 4u) return;
   vec3 raster = texelFetch(colortex8, coord, 0).rgb;
   // Ignore texture/silhouette edges affected by compressed geometry and UVs.
   for (int y = -2; y <= 2; y++) {
      for (int x = -2; x <= 2; x++) {
         ivec2 neighbor = clamp(coord + ivec2(x, y), ivec2(0), ivec2(viewWidth, viewHeight) - 1);
         if (any(greaterThan(abs(texelFetch(colortex8, neighbor, 0).rgb - raster), vec3(0.001)))) return;
      }
   }
   vec4 texColor = sampleQuadTexture(quadAttributes[hit.quadID], hit.uv);
   vec3 traced = sampleHitAlbedo(hit, ro, rd, texColor);
   imageStore(colorimg5, coord, vec4(abs(traced - raster), texColor.a < 1.0 ? 2.0 : 1.0));
}
"""


if __name__ == "__main__":
    if sys.argv[1:] == ["--shader"]:
        print(SHADER, end="")
    else:
        assert len(sys.argv) == 2, "usage: check_banner_blending.py --shader | colortex5.bin"
        pixels = list(struct.iter_unpack("<4f", Path(sys.argv[1]).read_bytes()))
        errors = [max(r, g, b) for r, g, b, a in pixels if a > 0.0]
        partial = sum(a == 2.0 for _, _, _, a in pixels)
        assert partial > 100, "Need a visible banner with partial-alpha patterns"
        assert all(math.isfinite(e) for e in errors), "Non-finite banner albedo"
        # RGB565 tint compression plus RGBA8 framebuffer blend rounding.
        assert max(errors) < 0.05, f"Banner albedo error: {max(errors):.6f}"
        print(f"PASS: {len(errors)} banner pixels ({partial} partial), max error {max(errors):.6f}")
