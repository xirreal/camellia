#ifndef CLOUDS_INCLUDE_GUARD
#define CLOUDS_INCLUDE_GUARD

#include "/lib/photon/bridge.glsl"
#include "/lib/photon/sky/clouds/parameters.glsl"
CloudsParameters clouds_params;
#include "/lib/photon/weather/clouds.glsl"
#include "/lib/photon/lighting/colors/weather_color.glsl"
#include "/lib/photon/sky/clouds.glsl"

struct CloudResult {
    vec3 scattering;
    float transmittance;
    vec3 aerialTransmittance;
    float albedo;
    bool collision;
    vec3 position;
};

void initClouds(vec3 sunDirection) {
    bool frozen = control.sceneFrozen == 1u;
    vec4 weather = frozen ? control.frozenCloudWeather
        : vec4(photonWorldAge, wetness, photonBiomeTemperature, photonBiomeHumidity);
    vec4 skyState = frozen ? control.frozenCloudSky
        : vec4(float(worldDay), photonLightning, photonBiomeSnow, photonBiomeSandstorm);
    photonCameraPosition = frozen ? control.frozenCameraPos.xyz : cameraPosition;
    photonRainStrength = frozen ? control.frozenLightPos.w : rainStrength;
    world_age = weather.x;
    photonWetness = weather.y;
    biome_temperature = weather.z;
    biome_humidity = weather.w;
    photonWorldDay = int(skyState.x);
    cloudLightning = skyState.y;
    biome_may_snow = skyState.z;
    biome_may_sandstorm = skyState.w;
    sun_dir = sunDirection;
    moon_dir = -sunDirection;

    float meFade = sun_dir.y < 0.18 ? 0.37 + 1.2 * max(0.0, -sun_dir.y) : 1.7;
    float meWeight = sqr(clamp01(1.0 - meFade * abs(sun_dir.y - 0.18)));
    time_sunrise = (sun_dir.x > 0.0 ? 1.0 : 0.0) * meWeight;
    time_sunset = (sun_dir.x < 0.0 ? 1.0 : 0.0) * meWeight;
    time_noon = (sun_dir.y > 0.0 ? 1.0 : 0.0) * (1.0 - meWeight);
    time_midnight = (sun_dir.y < 0.0 ? 1.0 : 0.0) * (1.0 - meWeight);
    day_factor = cubic_smooth(clamp01(abs(sun_dir.y) / 0.3));
    clouds_params = get_clouds_parameters(get_weather());

    sky_color = (tau * 1.13) * sampleSky(normalize(vec3(0.0, 1.0, -0.8)), sun_dir);
    sky_color = mix(sky_color, tau * get_weather_color(), photonRainStrength);
}

vec3 cloudAirPosition(vec3 scenePosition) {
    return vec3(scenePosition.x * CLOUDS_SCALE,
        planet_radius + (scenePosition.y + photonCameraPosition.y - 63.0) * CLOUDS_SCALE,
        scenePosition.z * CLOUDS_SCALE);
}

bool cloudLayerEnabled(int layer) {
#ifdef CLOUDS_CUMULUS
    if (layer == 0) return clouds_params.l0_coverage.y > eps;
#endif
#ifdef CLOUDS_ALTOCUMULUS
    if (layer == 1) return clouds_params.l1_coverage.y > eps;
#endif
#ifdef CLOUDS_CIRRUS
    if (layer == 2) return clouds_params.cirrus_amount + clouds_params.cirrocumulus_amount > eps;
#endif
#ifdef CLOUDS_CUMULUS_CONGESTUS
    if (layer == 3) return clouds_params.cumulus_congestus_blend > eps;
#endif
    return false;
}

vec2 cloudLayerBounds(int layer) {
    if (layer == 0) return vec2(clouds_cumulus_radius, clouds_cumulus_top_radius);
    if (layer == 1) return vec2(clouds_altocumulus_radius, clouds_altocumulus_top_radius);
    if (layer == 2) return clouds_cirrus_radius + vec2(-0.5, 0.5) * CLOUDS_CIRRUS_THICKNESS;
    return vec2(clouds_cumulus_congestus_radius, clouds_cumulus_congestus_top_radius);
}

vec2 cloudSegment(vec3 origin, vec3 direction, int layer, float maxDistance) {
    vec2 bounds = cloudLayerBounds(layer);
    vec2 segment = intersect_spherical_shell(origin, direction, bounds.x, bounds.y);
    if (segment.y < 0.0) return vec2(-1.0);
    vec2 ground = intersect_sphere(origin, direction, min(length(origin) - 10.0, planet_radius));
    if (ground.x > 0.0) segment.y = min(segment.y, ground.x);
    if (layer == 3) {
        vec2 cylinder = intersect_cylindrical_shell(origin, direction,
            clouds_cumulus_congestus_distance, clouds_cumulus_congestus_end_distance);
        segment = vec2(max(segment.x, cylinder.x), min(segment.y, cylinder.y));
    }
    segment.y = min(segment.y, maxDistance);
    return segment;
}

float cloudDensity(vec3 position, int layer) {
    if (layer == 0) return clouds_cumulus_density(position);
    if (layer == 1) return clouds_altocumulus_density(position);
    if (layer == 3) return clouds_cumulus_congestus_density(position);
    float radius = length(position);
    float altitude = (radius - clouds_cirrus_radius) / CLOUDS_CIRRUS_THICKNESS + 0.5;
    if (altitude < 0.0 || altitude > 1.0) return 0.0;
    return clouds_cirrus_density(position.xz * (clouds_cirrus_radius / radius), altitude);
}

float cloudExtinction(int layer) {
    if (layer == 0) return clouds_params.l0_extinction_coeff;
    if (layer == 1) return mix(0.08, 0.16, day_factor) * CLOUDS_ALTOCUMULUS_DENSITY
        * (2.0 - clouds_params.l1_cumulus_stratus_blend);
    if (layer == 2) return clouds_cirrus_extinction_coeff;
    return clouds_cumulus_congestus_extinction_coeff;
}

float cloudDensityMajorant(int layer) {
    return layer == 2 ? CLOUDS_CIRRUS_DENSITY + 0.25 * CLOUDS_CIRROCUMULUS_DENSITY : 1.0;
}

float cloudAlbedo(int layer) {
    if (layer == 0) return clouds_params.l0_scattering_coeff / clouds_params.l0_extinction_coeff;
    if (layer == 1) return mix(1.0, 0.75, photonRainStrength);
    if (layer == 3) return mix(1.0, 0.8, photonRainStrength);
    return 1.0;
}

float cloudFreeFlight(float majorant) {
    return -log(clamp(rand(), 1e-7, 1.0 - 1e-7)) / majorant;
}

int cloudPathSteps(int layer, vec3 direction) {
    if (layer == 0) return int(mix(float(CLOUDS_CUMULUS_PRIMARY_STEPS_H), float(CLOUDS_CUMULUS_PRIMARY_STEPS_Z), abs(direction.y)));
    if (layer == 1) return int(mix(float(CLOUDS_ALTOCUMULUS_PRIMARY_STEPS_H), float(CLOUDS_ALTOCUMULUS_PRIMARY_STEPS_Z), abs(direction.y)));
    if (layer == 2) return 12;
    return CLOUDS_CUMULUS_CONGESTUS_PRIMARY_STEPS;
}

float cloudLightTransmittance(vec3 origin, vec3 direction) {
    float opticalDepth = 0.0;
    for (int layer = 0; layer < 4; ++layer) {
        if (!cloudLayerEnabled(layer)) continue;
        vec2 segment = cloudSegment(origin, direction, layer, 1e6);
        if (segment.y <= segment.x) continue;
        int steps = cloudPathSteps(layer, direction);
        float stepLength = (segment.y - segment.x) / float(steps);
        float jitter = rand();
        for (int i = 0; i < steps; ++i) {
            vec3 position = origin + direction * (segment.x + (float(i) + jitter) * stepLength);
            opticalDepth += cloudDensity(position, layer) * cloudExtinction(layer) * stepLength;
        }
    }
    return exp(-opticalDepth);
}

float cloudSunTransmittance(vec3 sceneOrigin, vec3 direction) {
    return cloudLightTransmittance(cloudAirPosition(sceneOrigin), direction);
}

float cloudPhase(float cosine) {
    return 0.8 * henyey_greenstein_phase(cosine, 0.8)
        + 0.2 * henyey_greenstein_phase(cosine, -0.2);
}

vec3 sampleCloudPhase(vec3 incoming) {
    float g = rand() < 0.8 ? 0.8 : -0.2;
    float u = rand();
    float v = rand();
    float s = (1.0 - g * g) / (1.0 - g + 2.0 * g * u);
    float cosine = clamp((1.0 + g * g - s * s) / (2.0 * g), -1.0, 1.0);
    float sine = sqrt(max(1.0 - cosine * cosine, 0.0));
    vec3 up = abs(incoming.y) < 0.999 ? vec3(0.0, 1.0, 0.0) : vec3(1.0, 0.0, 0.0);
    vec3 tangent = normalize(cross(up, incoming));
    return normalize(incoming * cosine + sine * (tangent * cos(tau * v) + cross(incoming, tangent) * sin(tau * v)));
}

vec3 cloudAerialTransmittance(vec3 origin, vec3 end, vec3 direction) {
#if CLOUD_MODE == 1 && CLOUDS_AERIAL_PERSPECTIVE_BOOST != 0
    end = mix(origin, end, float(1 << CLOUDS_AERIAL_PERSPECTIVE_BOOST));
#endif
    vec3 air;
    if (length_squared(origin) < length_squared(end)) {
        air = clamp01(atmosphere_transmittance(origin, direction)
            / max(atmosphere_transmittance(end, direction), vec3(1e-8)));
    } else {
        air = clamp01(atmosphere_transmittance(end, -direction)
            / max(atmosphere_transmittance(origin, -direction), vec3(1e-8)));
    }
#if CLOUD_MODE == 1
    return mix(air, vec3(air.x), 0.8 * photonRainStrength);
#else
    return air;
#endif
}

CloudResult traceClouds(vec3 sceneOrigin, vec3 direction, float sceneDistance) {
    CloudResult result = CloudResult(vec3(0.0), 1.0, vec3(1.0), 1.0, false, vec3(0.0));
    vec3 origin = cloudAirPosition(sceneOrigin);
    float distanceToTerrain = sceneDistance < 0.0 ? -1.0 : sceneDistance * CLOUDS_SCALE;
#if CLOUD_MODE == 1
    CloudsResult photon = draw_clouds(origin, direction, sampleSky(direction, sun_dir), distanceToTerrain, rand());
    result.scattering = photon.scattering.rgb + cloudLightning * 4.0 * photon.scattering.w;
    result.transmittance = photon.transmittance;
#else
    float nearest = distanceToTerrain < 0.0 ? 1e6 : distanceToTerrain;
    for (int layer = 0; layer < 4; ++layer) {
        if (layer == 2) continue;
        if (!cloudLayerEnabled(layer)) continue;
        vec2 segment = cloudSegment(origin, direction, layer, nearest);
        if (segment.y <= segment.x) continue;
        float bound = cloudDensityMajorant(layer);
        float majorant = cloudExtinction(layer) * bound;
        float distance = segment.x;
        while (distance < segment.y) {
            distance += cloudFreeFlight(majorant);
            if (distance >= segment.y) break;
            float density = cloudDensity(origin + direction * distance, layer);
            if (rand() * bound < density) {
                nearest = distance;
                result.albedo = cloudAlbedo(layer);
                result.collision = true;
                break;
            }
        }
    }
    if (result.collision) {
        vec3 position = origin + direction * nearest;
        result.position = sceneOrigin + direction * (nearest / CLOUDS_SCALE);
        result.aerialTransmittance = cloudAerialTransmittance(origin, position, direction);
        bool moonlit = sun_dir.y < -0.04;
        vec3 lightDirection = moonlit ? moon_dir : sun_dir;
        vec3 direct = (moonlit ? MOON_ILLUMINANCE : SUN_ILLUMINANCE)
            * atmosphere_transmittance(position, lightDirection);
        if (!traceBVH(result.position, lightDirection).hit) {
            result.scattering = result.albedo * direct * cloudPhase(dot(direction, lightDirection))
                * cloudLightTransmittance(position, lightDirection);
        }
        vec3 clearSky = sampleSky(direction, sun_dir);
        result.scattering = (1.0 - result.aerialTransmittance) * clearSky
            + result.aerialTransmittance * result.scattering;
    }
#ifdef CLOUDS_CIRRUS
    CloudsResult cirrus = draw_cirrus_clouds(origin, direction, sampleSky(direction, sun_dir),
        result.collision ? nearest : distanceToTerrain, rand());
    if (!result.collision || cirrus.apparent_distance < nearest) {
        result.scattering = cirrus.scattering.rgb + cirrus.transmittance * result.scattering;
        result.transmittance *= cirrus.transmittance;
    }
#endif
    if (!result.collision) {
#ifdef CLOUDS_NOCTILUCENT
        vec4 noctilucent = draw_noctilucent_clouds(origin, direction, sampleSky(direction, sun_dir), distanceToTerrain);
        result.scattering += result.transmittance * noctilucent.rgb;
        result.transmittance *= noctilucent.a;
#endif
    }
#endif
    return result;
}

#endif
