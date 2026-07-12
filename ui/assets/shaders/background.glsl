#pragma language glsl3

// Adapted from a shader by hahnzhu (2020-10-20).
// Original: https://www.shadertoy.com/view/wdyczG
//
// Shadertoy API differences from LÖVE:
//   mainImage(out vec4, in vec2 fragCoord)  →  vec4 effect(vec4, Image, vec2 uv, vec2 px)
//   iResolution.xy                          →  px (pixel coords); resolution via px range
//   iTime                                   →  u_time

uniform float u_time;
uniform vec2  u_resolution;

#define S(a,b,t) smoothstep(a,b,t)

mat2 Rot(float a) {
    float s = sin(a);
    float c = cos(a);
    return mat2(c, -s, s, c);
}

// Gradient noise – inigo quilez / iq 2014
// License: Creative Commons Attribution-NonCommercial-ShareAlike 3.0 Unported
vec2 hash(vec2 p) {
    p = vec2(dot(p, vec2(2127.1, 81.17)), dot(p, vec2(1269.5, 283.37)));
    return fract(sin(p) * 43758.5453);
}

float noise(in vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    vec2 u = f * f * (3.0 - 2.0 * f);
    return 0.5 + 0.5 * mix(
        mix(dot(-1.0 + 2.0 * hash(i + vec2(0.0, 0.0)), f - vec2(0.0, 0.0)),
            dot(-1.0 + 2.0 * hash(i + vec2(1.0, 0.0)), f - vec2(1.0, 0.0)), u.x),
        mix(dot(-1.0 + 2.0 * hash(i + vec2(0.0, 1.0)), f - vec2(0.0, 1.0)),
            dot(-1.0 + 2.0 * hash(i + vec2(1.0, 1.0)), f - vec2(1.0, 1.0)), u.x),
        u.y);
}

vec4 effect(vec4 color, Image tex, vec2 texture_coords, vec2 px) {
    // Reconstruct normalised UV from pixel coords (LÖVE origin is top-left).
    vec2 uv = px / u_resolution;
    float ratio = u_resolution.x / u_resolution.y;

    vec2 tuv = uv;
    tuv -= 0.5;

    // Rotate with noise
    float degree = noise(vec2(u_time * 0.1, tuv.x * tuv.y));
    tuv.y *= 1.0 / ratio;
    tuv *= Rot(radians((degree - 0.5) * 720.0 + 180.0));
    tuv.y *= ratio;

    // Wave warp with sin
    float frequency = 5.0;
    float amplitude = 30.0;
    float speed = u_time * 2.0;
    tuv.x += sin(tuv.y * frequency + speed) / amplitude;
    tuv.y += sin(tuv.x * frequency * 1.5 + speed) / (amplitude * 0.5);

    // Colour layers
    vec3 colorYellow   = vec3(0.957, 0.804, 0.623);
    vec3 colorDeepBlue = vec3(0.192, 0.384, 0.933);
    vec3 layer1 = mix(colorYellow, colorDeepBlue, S(-0.3, 0.2, (tuv * Rot(radians(-5.0))).x));

    vec3 colorRed  = vec3(0.910, 0.510, 0.8);
    vec3 colorBlue = vec3(0.350, 0.710, 0.953);
    vec3 layer2 = mix(colorRed, colorBlue, S(-0.3, 0.2, (tuv * Rot(radians(-5.0))).x));

    vec3 col = mix(layer1, layer2, S(0.5, -0.3, tuv.y));

    return vec4(col, 1.0);
}
