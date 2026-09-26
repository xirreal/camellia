// Copyright (c) 2021-2025 Benjamin Stott (SixthSurge). See licenses/Photon.txt.

#ifndef PHOTON_UTILITY_GEOMETRY_INCLUDE_GUARD
#define PHOTON_UTILITY_GEOMETRY_INCLUDE_GUARD

#include "/lib/photon/utility/fast_math.glsl"

// Sphere/AABB intersection methods from https://www.scratchapixel.com

// Returns +-1
vec3 sign_non_zero(vec3 v) {
    return vec3(
        v.x >= 0.0 ? 1.0 : -1.0,
        v.y >= 0.0 ? 1.0 : -1.0,
        v.z >= 0.0 ? 1.0 : -1.0
    );
}

// from https://ebruneton.github.io/precomputed_atmospheric_scattering/
vec2 intersect_sphere(float mu, float r, float sphere_radius) {
    float discriminant = r * r * (mu * mu - 1.0) + sqr(sphere_radius);

    if (discriminant < 0.0) {
        return vec2(-1.0);
    }

    discriminant = sqrt(discriminant);
    return -r * mu + vec2(-discriminant, discriminant);
}

vec2 intersect_sphere(vec3 ray_origin, vec3 ray_dir, float sphere_radius) {
    float b = dot(ray_origin, ray_dir);
    float discriminant
        = sqr(b) - dot(ray_origin, ray_origin) + sqr(sphere_radius);

    if (discriminant < 0.0) {
        return vec2(-1.0);
    }

    discriminant = sqrt(discriminant);
    return -b + vec2(-discriminant, discriminant);
}

vec2 intersect_spherical_shell(
    float mu,
    float r,
    float inner_sphere_radius,
    float outer_sphere_radius
) {
    vec2 inner_sphere_dists = intersect_sphere(mu, r, inner_sphere_radius);
    vec2 outer_sphere_dists = intersect_sphere(mu, r, outer_sphere_radius);

    bool inner_sphere_intersected = inner_sphere_dists.y >= 0.0;
    bool outer_sphere_intersected = outer_sphere_dists.y >= 0.0;

    if (!outer_sphere_intersected) {
        return vec2(-1.0);
    }

    vec2 dists;
    dists.x = inner_sphere_intersected && inner_sphere_dists.x < 0.0
        ? inner_sphere_dists.y
        : max0(outer_sphere_dists.x);
    dists.y = inner_sphere_intersected && inner_sphere_dists.x > 0.0
        ? inner_sphere_dists.x
        : outer_sphere_dists.y;

    return dists;
}

vec2 intersect_spherical_shell(
    vec3 ray_origin,
    vec3 ray_dir,
    float inner_sphere_radius,
    float outer_sphere_radius
) {
    vec2 inner_sphere_dists
        = intersect_sphere(ray_origin, ray_dir, inner_sphere_radius);
    vec2 outer_sphere_dists
        = intersect_sphere(ray_origin, ray_dir, outer_sphere_radius);

    bool inner_sphere_intersected = inner_sphere_dists.y >= 0.0;
    bool outer_sphere_intersected = outer_sphere_dists.y >= 0.0;

    if (!outer_sphere_intersected) {
        return vec2(-1.0);
    }

    vec2 dists;
    dists.x = inner_sphere_intersected && inner_sphere_dists.x < 0.0
        ? inner_sphere_dists.y
        : max0(outer_sphere_dists.x);
    dists.y = inner_sphere_intersected && inner_sphere_dists.x > 0.0
        ? inner_sphere_dists.x
        : outer_sphere_dists.y;

    return dists;
}

vec2 intersect_cylindrical_shell(
    vec3 ray_origin,
    vec3 ray_dir,
    float inner_cylinder_radius,
    float outer_cylinder_radius
) {
    // Camellia's reflected/refracted paths can start away from the cylinder axis.
    // Photon only needs the centered primary-camera case here.
    float a = dot(ray_dir.xz, ray_dir.xz);
    float b = dot(ray_origin.xz, ray_dir.xz);
    float radius_sq = dot(ray_origin.xz, ray_origin.xz);
    if (a < 1e-12) {
        return radius_sq >= sqr(inner_cylinder_radius) && radius_sq <= sqr(outer_cylinder_radius)
            ? vec2(0.0, 1e6) : vec2(-1.0);
    }
    float outer_d = sqr(b) - a * (radius_sq - sqr(outer_cylinder_radius));
    if (outer_d < 0.0) return vec2(-1.0);
    vec2 outer = (-b + vec2(-1.0, 1.0) * sqrt(outer_d)) / a;
    float inner_d = sqr(b) - a * (radius_sq - sqr(inner_cylinder_radius));
    vec2 inner = inner_d >= 0.0 ? (-b + vec2(-1.0, 1.0) * sqrt(inner_d)) / a : vec2(-1.0);
    if (outer.y < 0.0) return vec2(-1.0);
    return vec2(inner.y >= 0.0 && inner.x < 0.0 ? inner.y : max0(outer.x),
                inner.x > 0.0 ? inner.x : outer.y);
}

#endif // PHOTON_UTILITY_GEOMETRY_INCLUDE_GUARD
