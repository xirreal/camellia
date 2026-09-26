// Copyright (c) 2021-2025 Benjamin Stott (SixthSurge). See licenses/Photon.txt.

#ifndef PHOTON_SKY_CLOUDS_CONSTANTS_INCLUDE_GUARD
#define PHOTON_SKY_CLOUDS_CONSTANTS_INCLUDE_GUARD

#include "/lib/photon/bridge.glsl"

const float clouds_cumulus_radius = planet_radius + CLOUDS_CUMULUS_ALTITUDE;
const float clouds_cumulus_thickness
    = CLOUDS_CUMULUS_ALTITUDE * CLOUDS_CUMULUS_THICKNESS;
const float clouds_cumulus_top_radius
    = clouds_cumulus_radius + clouds_cumulus_thickness;

const float clouds_altocumulus_radius
    = planet_radius + CLOUDS_ALTOCUMULUS_ALTITUDE;
const float clouds_altocumulus_thickness
    = CLOUDS_ALTOCUMULUS_ALTITUDE * CLOUDS_ALTOCUMULUS_THICKNESS;
const float clouds_altocumulus_top_radius
    = clouds_altocumulus_radius + clouds_altocumulus_thickness;

const float clouds_cirrus_radius = planet_radius + CLOUDS_CIRRUS_ALTITUDE;
const float clouds_cirrus_thickness
    = CLOUDS_CIRRUS_ALTITUDE * CLOUDS_ALTOCUMULUS_THICKNESS;
const float clouds_cirrus_top_radius
    = clouds_cirrus_radius + clouds_cirrus_thickness;
const float clouds_cirrus_extinction_coeff = 0.15;
const float clouds_cirrus_scattering_coeff = clouds_cirrus_extinction_coeff;

const float clouds_noctilucent_altitude = 80000.0;
const float clouds_noctilucent_radius
    = planet_radius + clouds_noctilucent_altitude;

#endif // PHOTON_SKY_CLOUDS_CONSTANTS_INCLUDE_GUARD
