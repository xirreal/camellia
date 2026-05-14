#ifndef SETTINGS_INCLUDE_GUARD
#define SETTINGS_INCLUDE_GUARD

// mode 0 = ReSTIR, mode 1 = Reference PT, mode 2 = BVH debug, mode 3 = nothing
#define MODE 0 //[0 1 2 3]

//#define ENABLE_DEBUG_OVERLAY
//#define ENABLE_SORT_VALIDATION
//#define ENABLE_QUAD_VALIDATION
//#define ENTITY_TEXTURES_DEBUG

// ReSTIR common numeric constants
const float RESTIR_PI = 3.14159265358979323846;
const float RESTIR_EPS = 1e-6;
const float RESTIR_WEIGHT_CLAMP = 50.0;

// ReSTIR initial sampling
const int RESTIR_MAX_BOUNCES = 3;
const float RESTIR_SURFACE_BIAS = 0.001;
const float RESTIR_SKY_SAMPLE_DISTANCE = 1024.0;

// ReSTIR temporal reuse
const float RESTIR_TEMPORAL_NORMAL_THRESHOLD = 0.9961947; // cos(5 degrees)
const float RESTIR_TEMPORAL_DEPTH_THRESHOLD = 0.2;
const float RESTIR_TEMPORAL_MIN_DEPTH_DELTA = 0.25;
const float RESTIR_TEMPORAL_M_CLAMP = 20.0;
const float RESTIR_TEMPORAL_MAX_AGE = 32.0;
const float RESTIR_M_PACK_MAX = 511.0;
// Keep temporal history until reprojection, scene reload, or validation rejects it.
// A fixed full-screen reset creates synchronized lighting pops.
const int RESTIR_TEMPORAL_RESET_INTERVAL = 0;
const int RESTIR_TEMPORAL_SEARCH_SAMPLES = 5;

// ReSTIR spatial reuse
const int RESTIR_SPATIAL_PAIRWISE_SAMPLES = 3;
const int RESTIR_SPATIAL_CANONICAL_SAMPLES = 1;
const int RESTIR_REUSE_TILE_SIZE = 8;
const int RESTIR_REUSE_CELL_BINS = 64;
const int RESTIR_REUSE_CELL_MAX_PIXELS = RESTIR_REUSE_TILE_SIZE * RESTIR_REUSE_TILE_SIZE;
const int RESTIR_REUSE_CELL_SEARCH_SAMPLES = 12;
const float RESTIR_SPATIAL_M_CLAMP = 500.0;
const float RESTIR_REUSE_CELL_SEARCH_RADIUS = 30.0;
const float RESTIR_REUSE_CELL_RADIUS_GROWTH = 1.25;
const float RESTIR_REUSE_CONFIDENCE_SCALE = 256.0;
const float RESTIR_NORMAL_THRESHOLD = 0.9961947; // cos(5 degrees)
const float RESTIR_DEPTH_THRESHOLD = 0.2;
const float RESTIR_MIN_DEPTH_DELTA = 0.25;
// This biased clamp trades a small reuse bias for lower variance from extreme Jacobians.
const float RESTIR_SPATIAL_JACOBIAN_CLAMP = 1000.0;

// ReSTIR visibility and lighting
const float RESTIR_TEMPORAL_VISIBILITY_BIAS = 0.001;
const float RESTIR_VISIBILITY_BIAS = 0.01;
const float RESTIR_SHADOW_MAX_DIST = 256.0;
const float RESTIR_SUN_HALF_ANGLE = 0.007;

const float VALIDATION_MAX_QUAD_EXTENT = 64.0; // max player-space span on any axis
const float VALIDATION_COPLANAR_THRESHOLD = 0.15; // max normal deviation (dot < 1-thresh)
const float VALIDATION_DEGEN_AREA_THRESHOLD = 1e-8; // minimum triangle area squared

#endif
