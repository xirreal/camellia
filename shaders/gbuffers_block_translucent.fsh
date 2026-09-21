#version 460 compatibility

/* RENDERTARGETS: 6,7,8 */

#define GBUFFERS_VERTEX_EMISSION
#define GBUFFERS_TEXTURE_PBR
#define GBUFFERS_ALPHA_TEST
#define GBUFFERS_LAYER_CAPTURE
#define vPlayerPos gPlayerPos
#define vWorldNormal gWorldNormal
#define vWorldTangent gWorldTangent
#define vVertexEmission gVertexEmission
#define vColor gColor
#define vTexCoord gTexCoord
#define vBlockID gBlockID
#include "/programs/capture.fsh"
