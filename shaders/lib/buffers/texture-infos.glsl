#ifndef TEXTURE_INFOS_BUFFER_INCLUDE_GUARD
#define TEXTURE_INFOS_BUFFER_INCLUDE_GUARD

#ifndef TEXTURE_INFOS_BUFFER_QUALIFIERS
#define TEXTURE_INFOS_BUFFER_QUALIFIERS restrict readonly
#endif

layout(std430, binding = 8) TEXTURE_INFOS_BUFFER_QUALIFIERS buffer TextureInfosBuffer {
   uint textureDataOffset;
   TextureInfo textureMap[];
};

#endif
