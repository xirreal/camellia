#ifndef TEXTURES_COPY_INCLUDE_GUARD
#define TEXTURES_COPY_INCLUDE_GUARD

#include "/lib/core/storage.glsl"
#include "/lib/scene/textures-common.glsl"

#ifdef ENTITY_TEXTURES
layout(rgba8) uniform writeonly image2D entityAtlasImg;
#ifdef ENTITY_PBR
layout(rgba8) uniform writeonly image2D entityNormalAtlasImg;
layout(rgba8) uniform writeonly image2D entitySpecularAtlasImg;
#endif
#endif

void copyEntityTexture(uvec4 job, ivec2 viewport, sampler2D albedo, sampler2D normals, sampler2D specular) {
#ifdef ENTITY_TEXTURES
   if (gl_HelperInvocation || job.w == 0u || job.w > 2u || !validEntityTextureRange(job.yz, job.x)) return;
   ivec2 size = entityCopyViewport(viewport);
   ivec2 pixel = ivec2(gl_FragCoord.xy);
   if (any(lessThanEqual(size, ivec2(0))) || any(lessThan(pixel, ivec2(0))) || any(greaterThanEqual(pixel, size))) return;
   uint stride = uint(size.x * size.y);
   uint count = job.y * job.z;
   if (count > stride * ENTITY_COPY_MAX_STEPS) return;
   ivec2 atlasSize = imageSize(entityAtlasImg);
   if (atlasSize.x != 16384 || uint(atlasSize.y) < (job.x + count + 16383u) / 16384u) return;
   if (job.w == 1u && any(notEqual(textureSize(albedo, 0), ivec2(job.yz)))) return;
#ifdef ENTITY_PBR
   if (job.w == 2u && (any(notEqual(imageSize(entityNormalAtlasImg), atlasSize)) ||
                      any(notEqual(imageSize(entitySpecularAtlasImg), atlasSize)))) return;
   ivec2 normalSize = textureSize(normals, 0);
   ivec2 specularSize = textureSize(specular, 0);
#endif
   // The validated count/stride bounds each fragment to at most 4096 texels.
   for (uint i = uint(pixel.y * size.x + pixel.x); i < count; i += stride) {
      ivec2 coord = ivec2(i % job.y, i / job.y);
      ivec2 atlasCoord = entityAtlasCoord(job.x + i);
      if (job.w == 1u) imageStore(entityAtlasImg, atlasCoord, texelFetch(albedo, coord, 0));
#ifdef ENTITY_PBR
      else {
         vec2 uv = (vec2(coord) + 0.5) / vec2(job.yz);
         vec4 normalValue = all(greaterThan(normalSize, ivec2(0)))
            ? texelFetch(normals, min(ivec2(uv * vec2(normalSize)), normalSize - 1), 0) : vec4(0.5, 0.5, 1.0, 1.0);
         vec4 specularValue = all(greaterThan(specularSize, ivec2(0)))
            ? texelFetch(specular, min(ivec2(uv * vec2(specularSize)), specularSize - 1), 0) : vec4(0.0, 0.04, 0.0, 0.0);
         imageStore(entityNormalAtlasImg, atlasCoord, normalValue);
         imageStore(entitySpecularAtlasImg, atlasCoord, specularValue);
      }
#endif
   }
#endif
}

#endif
