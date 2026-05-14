#ifndef RESTIR_REUSE_CELLS_INCLUDE_GUARD
#define RESTIR_REUSE_CELLS_INCLUDE_GUARD

#include "/lib/core/settings.glsl"

// Per-pixel records live first, followed by fixed per-tile cell records.
// A tile has four 4x4 spatial subcells times 16 normal bins. This keeps
// flat Minecraft surfaces from degenerating into a full 64-pixel walk.
// Pixel record: z = cell index, w = floatBitsToUint(source pHat).
// Cell record:  x/y = 64-bit tile-local occupancy mask,
//               z = low16 pixel count + high16 reservoir count, w = fixed-point confidence sum.
layout(binding = 12, std430) restrict buffer ReuseCellBuffer {
   uvec4 reuseCellRecords[];
};

uint reuseCellPixelCount(ivec2 extent) {
   return uint(extent.x) * uint(extent.y);
}

uint reuseCellCoordIndex(ivec2 coord, ivec2 extent) {
   return uint(coord.x) + uint(coord.y) * uint(extent.x);
}

ivec2 reuseCellIndexToCoord(uint pixelIndex, ivec2 extent) {
   uint width = uint(extent.x);
   return ivec2(int(pixelIndex % width), int(pixelIndex / width));
}

uvec2 reuseCellTileCount(ivec2 extent) {
   return (uvec2(extent) + uint(RESTIR_REUSE_TILE_SIZE - 1)) / uint(RESTIR_REUSE_TILE_SIZE);
}

uint reuseCellNormalBin(vec3 normal) {
   vec3 n = normalize(normal);
   float l1 = abs(n.x) + abs(n.y) + abs(n.z);
   if (l1 <= RESTIR_EPS) return 0u;

   vec2 p = n.xy / l1;
   if (n.z < 0.0) {
      vec2 s = vec2(p.x >= 0.0 ? 1.0 : -1.0, p.y >= 0.0 ? 1.0 : -1.0);
      p = (1.0 - abs(p.yx)) * s;
   }

   uvec2 q = min(uvec2(floor(clamp(p * 0.5 + 0.5, vec2(0.0), vec2(0.999999)) * 4.0)), uvec2(3u));
   return q.x | (q.y << 2u);
}

uint reuseCellIndex(ivec2 coord, ivec2 extent, vec3 normal) {
   uvec2 tileCount = reuseCellTileCount(extent);
   uvec2 tile = uvec2(coord) / uint(RESTIR_REUSE_TILE_SIZE);
   uint tileIndex = tile.x + tile.y * tileCount.x;
   uvec2 tileLocal = uvec2(coord) & uvec2(uint(RESTIR_REUSE_TILE_SIZE - 1));
   uint quadrant = (tileLocal.x >> 2u) | ((tileLocal.y >> 2u) << 1u);
   return tileIndex * uint(RESTIR_REUSE_CELL_BINS) + quadrant * 16u + reuseCellNormalBin(normal);
}

ivec2 reuseCellTileOrigin(uint cellIndex, ivec2 extent) {
   uvec2 tileCount = reuseCellTileCount(extent);
   uint tileIndex = cellIndex / uint(RESTIR_REUSE_CELL_BINS);
   uvec2 tile = uvec2(tileIndex % tileCount.x, tileIndex / tileCount.x);
   return ivec2(tile * uint(RESTIR_REUSE_TILE_SIZE));
}

uint reuseCellRecordIndex(uint cellIndex, ivec2 extent) {
   return reuseCellPixelCount(extent) + cellIndex;
}

uvec4 loadReusePixelRecord(uint pixelIndex) {
   return reuseCellRecords[pixelIndex];
}

uvec4 loadReuseCellRecord(uint cellIndex, ivec2 extent) {
   return reuseCellRecords[reuseCellRecordIndex(cellIndex, extent)];
}

float reuseCellConfidenceSum(uvec4 cellRecord) {
   return float(cellRecord.w) / RESTIR_REUSE_CONFIDENCE_SCALE;
}

void clearReuseCellForPixel(ivec2 coord, ivec2 extent, vec3 normal) {
   uint pixelIndex = reuseCellCoordIndex(coord, extent);
   reuseCellRecords[pixelIndex] = uvec4(INVALID_ID, INVALID_ID, INVALID_ID, 0u);

   if (dot(normal, normal) <= 0.25) return;

   uint cellIndex = reuseCellIndex(coord, extent, normal);
   reuseCellRecords[reuseCellRecordIndex(cellIndex, extent)] = uvec4(0u, 0u, 0u, 0u);
}

void insertReuseCellPixel(
      ivec2 coord,
      ivec2 extent,
      vec3 normal,
      float confidence,
      float sourceTarget,
      bool hasContributingReservoir) {
   uint pixelIndex = reuseCellCoordIndex(coord, extent);
   uint cellIndex = reuseCellIndex(coord, extent, normal);
   uint cellRecordIndex = reuseCellRecordIndex(cellIndex, extent);

   reuseCellRecords[pixelIndex] = uvec4(0u, 0u, cellIndex, floatBitsToUint(max(sourceTarget, 0.0)));

   uvec2 tileLocal = uvec2(coord) & uvec2(uint(RESTIR_REUSE_TILE_SIZE - 1));
   uint localIndex = tileLocal.x + tileLocal.y * uint(RESTIR_REUSE_TILE_SIZE);
   if (localIndex < 32u) {
      atomicOr(reuseCellRecords[cellRecordIndex].x, 1u << localIndex);
   } else {
      atomicOr(reuseCellRecords[cellRecordIndex].y, 1u << (localIndex - 32u));
   }

   atomicAdd(reuseCellRecords[cellRecordIndex].z, 1u);

   uint confidenceFixed = uint(round(clamp(confidence, 0.0, RESTIR_SPATIAL_M_CLAMP) * RESTIR_REUSE_CONFIDENCE_SCALE));
   atomicAdd(reuseCellRecords[cellRecordIndex].w, confidenceFixed);

   if (hasContributingReservoir) {
      atomicAdd(reuseCellRecords[cellRecordIndex].z, 1u << 16u);
   }
}

#endif // RESTIR_REUSE_CELLS_INCLUDE_GUARD
