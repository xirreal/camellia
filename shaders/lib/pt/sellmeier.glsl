// 7-bin spectral dispersion for glass refraction.
// Wavelengths (nm):  425  465  490  535  575  605  645
const int GLASS_BIN_COUNT = 7;
const float GLASS_WL_BIN[7] = float[7](
      425.0, // V
      465.0, // B
      490.0, // C
      535.0, // G
      575.0, // Y
      605.0, // O
      645.0 // R
   );
// normalized to be sum to 1,1,1
const vec3 GLASS_MASK_BIN[7] = vec3[7](
      vec3(0.0, 0.0, 1.0 / 3.0), // V → (0,0,1)
      vec3(0.0, 0.0, 1.0 / 3.0), // B → (0,0,1)
      vec3(0.0, 1.0 / 4.0, 1.0 / 3.0), // C → (0,1,1)
      vec3(0.0, 1.0 / 4.0, 0.0), // G → (0,1,0)
      vec3(1.0 / 3.0, 1.0 / 4.0, 0.0), // Y → (1,1,0)
      vec3(1.0 / 3.0, 1.0 / 4.0, 0.0), // O → (1,1,0)
      vec3(1.0 / 3.0, 0.0, 0.0) // R → (1,0,0)
   );

float sellmeierIOR(float lambda_nm, vec3 B, vec3 C) {
   float L = lambda_nm * 1e-3;
   float L2 = L * L;
   vec3 terms = B * L2 / (vec3(L2) - C);
   return sqrt(1.0 + terms.x + terms.y + terms.z);
}

void glassCoeffs_N_BK7(out vec3 B, out vec3 C) {
   B = vec3(1.03961212, 0.231792344, 1.01046945);
   C = vec3(0.006000699, 0.0200179144, 103.560653);
}
