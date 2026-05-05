#ifndef TEXTURE_DATA_BUFFER_INCLUDE_GUARD
#define TEXTURE_DATA_BUFFER_INCLUDE_GUARD

#ifndef TEXTURE_DATA_BUFFER_QUALIFIERS
#define TEXTURE_DATA_BUFFER_QUALIFIERS restrict readonly
#endif

layout(std430, binding = 9) TEXTURE_DATA_BUFFER_QUALIFIERS buffer TextureDataBuffer {
   uint textureData[];
};

#endif
