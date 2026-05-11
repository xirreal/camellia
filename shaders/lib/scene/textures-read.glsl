#ifndef TEXTURES_READ_INCLUDE_GUARD
#define TEXTURES_READ_INCLUDE_GUARD

#ifndef TEXTURE_INFOS_BUFFER_QUALIFIERS
#define TEXTURE_INFOS_BUFFER_QUALIFIERS restrict readonly
#endif
#ifndef TEXTURE_DATA_BUFFER_QUALIFIERS
#define TEXTURE_DATA_BUFFER_QUALIFIERS restrict readonly
#endif

#include "/lib/scene/textures-common.glsl"
#include "/lib/buffers/texture-infos.glsl"
#include "/lib/buffers/texture-data.glsl"

vec4 sampleEntityTexture(uint textureID, vec2 uv) {
   uint slot = textureID - 1u;
   TextureInfo entry = textureMap[slot];

   uv = clamp(uv, vec2(0.0), vec2(1.0));
   ivec2 texel = clamp(
         ivec2(uv * vec2(float(entry.sizeX), float(entry.sizeY))),
         ivec2(0),
         ivec2(int(entry.sizeX) - 1, int(entry.sizeY) - 1)
      );

   uint idx = morton2D(uint(texel.x), uint(texel.y));
   return unpackUnorm4x8(textureData[entry.baseOffset + idx]);
}

#ifdef ENTITY_PBR

vec4 sampleEntityNormal(uint textureID, vec2 uv) {
   uint slot = textureID - 1u;
   TextureInfo entry = textureMap[slot];

   uint paddedDim = nextPow2(max(entry.sizeX, entry.sizeY));
   uint texelCount = paddedDim * paddedDim;

   uv = clamp(uv, vec2(0.0), vec2(1.0));
   ivec2 texel = clamp(
         ivec2(uv * vec2(float(entry.sizeX), float(entry.sizeY))),
         ivec2(0),
         ivec2(int(entry.sizeX) - 1, int(entry.sizeY) - 1)
      );

   uint idx = morton2D(uint(texel.x), uint(texel.y));
   return unpackUnorm4x8(textureData[entry.baseOffset + texelCount + idx]);
}

vec4 sampleEntitySpecular(uint textureID, vec2 uv) {
   uint slot = textureID - 1u;
   TextureInfo entry = textureMap[slot];

   uint paddedDim = nextPow2(max(entry.sizeX, entry.sizeY));
   uint texelCount = paddedDim * paddedDim;

   uv = clamp(uv, vec2(0.0), vec2(1.0));
   ivec2 texel = clamp(
         ivec2(uv * vec2(float(entry.sizeX), float(entry.sizeY))),
         ivec2(0),
         ivec2(int(entry.sizeX) - 1, int(entry.sizeY) - 1)
      );

   uint idx = morton2D(uint(texel.x), uint(texel.y));
   return unpackUnorm4x8(textureData[entry.baseOffset + 2u * texelCount + idx]);
}

#endif

#endif
