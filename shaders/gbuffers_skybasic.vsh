#version 150

#ifdef MC_GL_VENDOR_NVIDIA
#extension GL_NV_gpu_shader5 : require

out gl_PerVertex {
   flat float16_t gl_Position;
};
#endif

void main() {
   #ifdef MC_GL_VENDOR_NVIDIA
   gl_Position = float16_t(0.0 / 0.0);
   #else
   gl_Position = vec4(0.0 / 0.0);
   #endif
}
