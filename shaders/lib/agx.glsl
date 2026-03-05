#ifndef AGX_INCLUDE_GUARD
#define AGX_INCLUDE_GUARD

#define AGX_LUT_BLOCK_SIZE 32
#define AGX_LUT_DIMENSIONS ivec2(AGX_LUT_BLOCK_SIZE * AGX_LUT_BLOCK_SIZE, AGX_LUT_BLOCK_SIZE)
#define AGX_LUT_PIXEL_SIZE (1.0 / vec2(AGX_LUT_DIMENSIONS))

// --------------------------------------------------------------------------
// Math utilities (from lib_math.hlsl)
// --------------------------------------------------------------------------

vec3 agx_powsafe(vec3 color, float power) {
   return pow(abs(color), vec3(power)) * sign(color);
}

vec3 agx_apply_matrix(vec3 color, mat3 m) {
   return vec3(
      dot(color, m[0]),
      dot(color, m[1]),
      dot(color, m[2])
   );
}

// --------------------------------------------------------------------------
// AgX Inset / Outset matrices (from lib_agx.hlsl)
// --------------------------------------------------------------------------

const mat3 AGX_INSET_MATRIX = mat3(
      vec3(0.84247906, 0.0784336, 0.07922375),
      vec3(0.04232824, 0.87846864, 0.07916613),
      vec3(0.04237565, 0.0784336, 0.87914297)
   );

const mat3 AGX_OUTSET_MATRIX = mat3(
      vec3(1.1968790, -0.09802088, -0.09902975),
      vec3(-0.05289685, 1.15190313, -0.09896118),
      vec3(-0.05297163, -0.09804345, 1.15107368)
   );

// --------------------------------------------------------------------------
// AgX Log encoding (from lib_agx.hlsl: _applyAgXLog)
//
// Prepare the data for display encoding. Converted to log domain.
// --------------------------------------------------------------------------

vec3 agxLog(vec3 color) {
   // Clamp negatives
   color = max(vec3(0.0), color);

   // Apply inset matrix (compresses chroma for the log encoding range)
   color = agx_apply_matrix(color, AGX_INSET_MATRIX);

   // Log2 normalized from open domain
   // Ported from cctf_log2_normalized_from_open_domain(color, -10.0, 6.5)
   float minEV = -10.0;
   float maxEV = 6.5;
   float midGrey = 0.18;

   // Remove negative before log transform
   color = max(vec3(0.0), color);
   // Avoid infinite issue with log
   color = mix(color, vec3(1.525878e-5) + color, lessThan(color, vec3(3.051757e-5)));
   color = clamp(log2(color / midGrey), vec3(minEV), vec3(maxEV));
   color = (color - minEV) / (maxEV - minEV);

   color = clamp(color, 0.0, 1.0);
   return color;
}

// --------------------------------------------------------------------------
// AgX LUT sampling (from lib_agx.hlsl: _applyAgXLUT)
//
// Apply the AgX 1D curve on log encoded data using the 3D LUT.
// The 3D LUT is stored as a 2D texture strip: 32 blocks of 32x32.
// The LUT output is encoded with a power 2.2 transfer function,
// so we decode it back to linear.
// --------------------------------------------------------------------------

vec3 agxLutSample(vec3 color, sampler2D lut) {
   vec3 lut3D = color * float(AGX_LUT_BLOCK_SIZE - 1);

   // Front slice
   vec2 lut2D_front;
   lut2D_front.x = floor(lut3D.z) * float(AGX_LUT_BLOCK_SIZE) + lut3D.x;
   lut2D_front.y = lut3D.y;

   // Back slice
   vec2 lut2D_back;
   lut2D_back.x = ceil(lut3D.z) * float(AGX_LUT_BLOCK_SIZE) + lut3D.x;
   lut2D_back.y = lut3D.y;

   // Convert from texel coordinates to normalized texture coordinates
   lut2D_front = (lut2D_front + 0.5) * AGX_LUT_PIXEL_SIZE;
   lut2D_back = (lut2D_back + 0.5) * AGX_LUT_PIXEL_SIZE;

   // Bilinear interpolation on front and back slices, then lerp along Z
   vec3 result = mix(
         texture(lut, lut2D_front).rgb,
         texture(lut, lut2D_back).rgb,
         fract(lut3D.z)
      );

   // The LUT is stored with a power 2.2 transfer function; decode to linear
   result = agx_powsafe(result, 2.2);

   return result;
}

// --------------------------------------------------------------------------
// AgX Outset (from lib_agx.hlsl: _applyOutset)
//
// Inverse of the inset applied during agxLog; restores chroma.
// --------------------------------------------------------------------------

vec3 agxOutset(vec3 color) {
   return agx_apply_matrix(color, AGX_OUTSET_MATRIX);
}

// --------------------------------------------------------------------------
// sRGB OETF (IEC 61966-2-1)
// --------------------------------------------------------------------------

vec3 agx_srgbOETF(vec3 color) {
   return mix(
      12.92 * color,
      1.055 * pow(color, vec3(1.0 / 2.4)) - 0.055,
      step(vec3(0.0031308), color)
   );
}

// Apply AgX DRT: sRGB linear input -> sRGB linear output (closed domain 0-1)
vec3 agxTonemap(vec3 color, sampler2D lut) {
   color = agxLog(color);
   color = agxLutSample(color, lut);
   return color;
}

// Apply AgX DRT with outset: sRGB linear input -> sRGB linear output
vec3 agxTonemapOutset(vec3 color, sampler2D lut) {
   color = agxTonemap(color, lut);
   color = agxOutset(color);
   return color;
}

vec3 agxComplete(vec3 srgbLinear, sampler2D lut) {
   vec3 color = agxTonemapOutset(srgbLinear, lut);
   color = max(vec3(0.0), color);
   color = agx_srgbOETF(color);

   return color;
}

vec3 agxCompleteNoOutset(vec3 srgbLinear, sampler2D lut) {
   vec3 color = agxTonemap(srgbLinear, lut);

   color = max(vec3(0.0), color);
   color = agx_srgbOETF(color);

   return color;
}

#endif
