#version 460

layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f) uniform writeonly image2D colorimg5;

uniform float viewWidth;
uniform float viewHeight;
uniform mat4 gbufferProjectionInverse;
uniform mat4 gbufferModelViewInverse;
uniform vec3 shadowLightPosition;
uniform int frameCounter;
uniform bool firstPersonCamera;

uniform sampler2D blockAtlas;

uniform float near;

#include "/lib/storage.glsl"
#include "/lib/hploc.glsl"
#include "/lib/encoding.glsl"
#include "/lib/raytrace.glsl"

const float CLOSE_SHADOW_BIAS = 0.000001;
const float FAR_SHADOW_BIAS = 0.0001;
const float SHADOW_MAX_DIST = 256.0;
const float SKY_BRIGHTNESS = 0.75;
const float SUN_BRIGHTNESS = 1.25;

uint rngState;

void initRNG(ivec2 coord, int frame) {
   rngState = uint(coord.x * 1973 + coord.y * 9277 + frame * 26699) | 1u;
}

uint pcgHash() {
   uint state = rngState;
   rngState = rngState * 747796405u + 2891336453u;
   uint word = ((state >> ((state >> 28u) + 4u)) ^ state) * 277803737u;
   return (word >> 22u) ^ word;
}

float rand() {
   return float(pcgHash()) / 4294967295.0;
}

vec3 getSkyColor(vec3 rd, vec3 lightDir) {
   float sun = max(dot(rd, lightDir), 0.0);
   float sky = max(rd.y * 0.5 + 0.5, 0.0);
   vec3 skyColor = mix(vec3(0.5, 0.6, 0.8), vec3(0.2, 0.4, 0.9), sky) * SKY_BRIGHTNESS;
   skyColor += vec3(1.0, 0.95, 0.8) * pow(sun, 256.0) * SUN_BRIGHTNESS;
   return skyColor;
}

void main() {
   ivec2 coord = ivec2(gl_GlobalInvocationID.xy);
   if (coord.x >= int(viewWidth) || coord.y >= int(viewHeight)) return;

   initRNG(coord, frameCounter);

   vec2 uv = (vec2(coord) + 0.5) / vec2(viewWidth, viewHeight);
   vec2 ndc = uv * 2.0 - 1.0;

   vec4 clipDir = vec4(ndc, 1.0, 1.0);
   vec4 viewDir = gbufferProjectionInverse * clipDir;
   viewDir.xyz /= viewDir.w;
   vec3 rd = normalize((mat3(gbufferModelViewInverse) * viewDir.xyz));

   vec3 ro = gbufferModelViewInverse[3].xyz;

   if (firstPersonCamera) {
      vec3 extents = vec3(0.6);
      vec3 safeRd = rd + step(abs(rd), vec3(1e-8)) * 1e-8;
      vec3 t1 = (-extents - ro) / safeRd;
      vec3 t2 = (extents - ro) / safeRd;
      vec3 tMax = max(t1, t2);
      float tExit = min(tMax.x, min(tMax.y, tMax.z));

      if (tExit > 0.0) {
         ro += rd * (tExit + 0.001);
      }
   }

   TraceResult hit = traceBVH(ro, rd);

   vec3 lightDir = normalize((gbufferModelViewInverse * vec4(0.01 * shadowLightPosition, 0.0)).xyz);

   if (!hit.hit) {
      vec3 sky = getSkyColor(rd, lightDir);
      imageStore(colorimg5, coord, vec4(sky, 1.0));
      return;
   }

   vec4 texColor;
   if (hit.textureID == 0u) {
      texColor = texture(blockAtlas, hit.uv);
   } else {
      #ifdef ENTITY_TEXTURES
      texColor = sampleEntityTexture(hit.textureID, hit.uv);
      #else
      texColor = vec4(1.0);
      #endif
   }
   vec3 albedo = pow(texColor.rgb * hit.vertexData.rgb, vec3(2.2));

   float NdotL = max(dot(hit.normal, lightDir), 0.0);

   vec3 shadow = vec3(1.0);

   if (NdotL > 0.0) {
      vec3 hitPos = ro + rd * hit.t;
      vec3 shadowOrigin = hitPos + hit.normal * mix(CLOSE_SHADOW_BIAS, FAR_SHADOW_BIAS, hit.t / SHADOW_MAX_DIST);

      int NUM_SAMPLES = 4;
      float lightSpread = 0.007;

      vec3 shadowAccum = vec3(0.0);
      float weightAccum = 0.0;

      vec3 up = abs(lightDir.z) < 0.999 ? vec3(0.0, 0.0, 1.0) : vec3(1.0, 0.0, 0.0);
      vec3 tangent = normalize(cross(up, lightDir));
      vec3 bitangent = cross(lightDir, tangent);

      float seed = rand() * 6.28318530718;

      for (int i = 0; i < NUM_SAMPLES; i++) {
         float r = sqrt((float(i) + 0.5) / float(NUM_SAMPLES));
         float theta = float(i) * 2.3999632 + seed;

         vec2 diskPos = vec2(r * cos(theta), r * sin(theta));

         vec3 sampleDir = normalize(lightDir + (tangent * diskPos.x + bitangent * diskPos.y) * lightSpread);
         float sampleNdotL = dot(hit.normal, sampleDir);

         if (sampleNdotL > 0.0) {
            vec3 tint = traceShadowTinted(shadowOrigin, sampleDir, SHADOW_MAX_DIST);
            shadowAccum += tint * sampleNdotL;
            weightAccum += sampleNdotL;
         }
      }

      shadow = shadowAccum / weightAccum;
   }

   vec3 sunLight = NdotL * shadow * SUN_BRIGHTNESS * vec3(0.9, 1.1, 1.5);
   vec3 ambient = vec3(SKY_BRIGHTNESS * 0.18);
   vec3 lighting = sunLight + ambient;

   float emission = hit.vertexData.a;
   if (emission > 0.0) {
      float emitter = pow(length(albedo * 1.5), 5.6) * 0.5;
      lighting += albedo * emitter * emission * 2.0;
   }

   imageStore(colorimg5, coord, vec4(albedo * lighting, 1.0));
}
