#version 460 compatibility

#include "/lib/scene/textures-copy.glsl"

uniform sampler2D gtexture;
uniform sampler2D normals;
uniform sampler2D specular;
flat in uvec4 vTextureCopy;

void main() {
   copyEntityTexture(vTextureCopy, ivec2(shadowMapResolution), gtexture, normals, specular);
   discard;
}
