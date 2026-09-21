#ifndef TEXTURES_READ_INCLUDE_GUARD
#define TEXTURES_READ_INCLUDE_GUARD

#include "/lib/scene/textures-common.glsl"
#include "/lib/buffers/texture-infos.glsl"

#ifdef ENTITY_TEXTURES
uniform sampler2D entityAtlas;
#ifdef ENTITY_PBR
uniform sampler2D entityNormalAtlas;
uniform sampler2D entitySpecularAtlas;
#endif
#endif

vec4 sampleEntityAtlas(uint textureID, vec2 uv, uint layer, vec4 fallback) {
#ifdef ENTITY_TEXTURES
   if (textureID == 0u || textureID > MAX_TEXTURES) return fallback;
   TextureInfo entry = textureMap[textureID - 1u];
   uvec2 size = uvec2(entry.sizeX, entry.sizeY);
   if (entry.key == 0u || !validEntityTextureRange(size, entry.baseOffset) ||
       any(isnan(uv)) || any(isinf(uv))) return fallback;
#ifdef ENTITY_PBR
   if (layer != 0u && entry.pbrPendingFrame != INVALID_ID) return fallback;
#endif
   uvec2 texel = min(uvec2(clamp(uv, 0.0, 1.0) * vec2(size)), size - 1u);
   uint address = entry.baseOffset + texel.y * size.x + texel.x;
   ivec2 coord = entityAtlasCoord(address);
#ifdef ENTITY_PBR
   if (layer == 1u) return texelFetch(entityNormalAtlas, coord, 0);
   if (layer == 2u) return texelFetch(entitySpecularAtlas, coord, 0);
#endif
   return texelFetch(entityAtlas, coord, 0);
#else
   return fallback;
#endif
}

vec4 sampleEntityTexture(uint textureID, vec2 uv) {
   return sampleEntityAtlas(textureID, uv, 0u, vec4(1.0));
}

#ifdef ENTITY_PBR
vec4 sampleEntityNormal(uint textureID, vec2 uv) {
   return sampleEntityAtlas(textureID, uv, 1u, vec4(0.5, 0.5, 1.0, 1.0));
}

vec4 sampleEntitySpecular(uint textureID, vec2 uv) {
   return sampleEntityAtlas(textureID, uv, 2u, vec4(0.0, 0.04, 0.0, 0.0));
}
#endif

#endif
