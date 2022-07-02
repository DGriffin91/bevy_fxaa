// Basic FXAA implementation based on the code on geeks3d.com with the
// modification that the texture2DLod stuff was removed since it's
// unsupported by WebGL.
// --
// From:
// https://github.com/mitsuhiko/webgl-meincraft
// Copyright (c) 2011 by Armin Ronacher.
// Some rights reserved.
// Redistribution and use in source and binary forms, with or without
// modification, are permitted provided that the following conditions are
// met:
//     * Redistributions of source code must retain the above copyright
//       notice, this list of conditions and the following disclaimer.
//     * Redistributions in binary form must reproduce the above
//       copyright notice, this list of conditions and the following
//       disclaimer in the documentation and/or other materials provided
//       with the distribution.
//     * The names of the contributors may not be used to endorse or
//       promote products derived from this software without specific
//       prior written permission.
// THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
// "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
// LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
// A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT
// OWNER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL,
// SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT
// LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE,
// DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY
// THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
// (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
// OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.


let FXAA_REDUCE_MIN: f32 = 0.0078125; //1.0 / 128.0
let FXAA_REDUCE_MUL: f32 = 0.125; //1.0 / 8.0
let FXAA_SPAN_MAX: f32 = 8.0;

//optimized version for mobile, where dependent 
//texture reads can be a bottleneck
fn fxaa(tex: texture_2d<f32>, samp: sampler, fragCoord: vec2<f32>, resolution: vec2<f32>, 
        v_rgbNW: vec2<f32>,
        v_rgbNE: vec2<f32>,
        v_rgbSW: vec2<f32>,
        v_rgbSE: vec2<f32>,
        v_rgbM: vec2<f32>) -> vec4<f32> {
    var color = vec4<f32>(0.0);
    let inverseVP = 1.0 / resolution.xy;
    let rgbNW = textureSample(tex, samp, v_rgbNW).xyz;
    let rgbNE = textureSample(tex, samp, v_rgbNE).xyz;
    let rgbSW = textureSample(tex, samp, v_rgbSW).xyz;
    let rgbSE = textureSample(tex, samp, v_rgbSE).xyz;
    let texColor = textureSample(tex, samp, v_rgbM);
    let rgbM  = texColor.xyz;
    let luma = vec3<f32>(0.299, 0.587, 0.114);
    let lumaNW = dot(rgbNW, luma);
    let lumaNE = dot(rgbNE, luma);
    let lumaSW = dot(rgbSW, luma);
    let lumaSE = dot(rgbSE, luma);
    let lumaM  = dot(rgbM,  luma);
    let lumaMin = min(lumaM, min(min(lumaNW, lumaNE), min(lumaSW, lumaSE)));
    let lumaMax = max(lumaM, max(max(lumaNW, lumaNE), max(lumaSW, lumaSE)));
    
    var dir = vec2<f32>(0.0);
    dir.x = -((lumaNW + lumaNE) - (lumaSW + lumaSE));
    dir.y =  ((lumaNW + lumaSW) - (lumaNE + lumaSE));
    
    let dirReduce = max((lumaNW + lumaNE + lumaSW + lumaSE) *
                          (0.25 * FXAA_REDUCE_MUL), FXAA_REDUCE_MIN);
    
    let rcpDirMin = 1.0 / (min(abs(dir.x), abs(dir.y)) + dirReduce);
    dir = min(vec2<f32>(FXAA_SPAN_MAX, FXAA_SPAN_MAX),
              max(vec2<f32>(-FXAA_SPAN_MAX, -FXAA_SPAN_MAX),
              dir * rcpDirMin)) * inverseVP;
    
    let rgbA = 0.5 * (
        textureSample(tex, samp, fragCoord * inverseVP + dir * (1.0 / 3.0 - 0.5)).xyz +
        textureSample(tex, samp, fragCoord * inverseVP + dir * (2.0 / 3.0 - 0.5)).xyz);
    let rgbB = rgbA * 0.5 + 0.25 * (
        textureSample(tex, samp, fragCoord * inverseVP + dir * -0.5).xyz +
        textureSample(tex, samp, fragCoord * inverseVP + dir * 0.5).xyz);

    let lumaB = dot(rgbB, luma);
    if ((lumaB < lumaMin) || (lumaB > lumaMax)) {
        color = vec4<f32>(rgbA, texColor.a);
    } else {
        color = vec4<f32>(rgbB, texColor.a);
    }
    return color;
}


#import bevy_pbr::mesh_types
#import bevy_pbr::mesh_view_bindings

struct VertexOutput {
    [[builtin(position)]] frag_coord: vec4<f32>;
    [[location(0)]] coord: vec2<f32>;
    [[location(1)]] v_rgbNW: vec2<f32>;
    [[location(2)]] v_rgbNE: vec2<f32>;
    [[location(3)]] v_rgbSW: vec2<f32>;
    [[location(4)]] v_rgbSE: vec2<f32>;
    [[location(5)]] v_rgbM: vec2<f32>;
};

[[stage(vertex)]]
fn vertex(
    [[location(0)]] vertex_position: vec3<f32>,
    [[location(1)]] vertex_uv: vec2<f32>
) -> VertexOutput {
    var out: VertexOutput;
    let resolution = vec2<f32>(view.width, view.height);
    out.frag_coord = view.view_proj * vec4<f32>(vertex_position, 1.0);
    out.coord = vertex_position.xy + resolution / 2.0;
	let inverseVP = 1.0 / resolution;
    out.v_rgbNW = (out.coord + vec2<f32>(-1.0, -1.0)) * inverseVP;
    out.v_rgbNE = (out.coord + vec2<f32>(1.0, -1.0)) * inverseVP;
    out.v_rgbSW = (out.coord + vec2<f32>(-1.0, 1.0)) * inverseVP;
    out.v_rgbSE = (out.coord + vec2<f32>(1.0, 1.0)) * inverseVP;
	out.v_rgbM = vec2<f32>(out.coord * inverseVP);
    return out;
}

[[group(1), binding(0)]]
var texture: texture_2d<f32>;
[[group(1), binding(1)]]
var our_sampler: sampler;

[[stage(fragment)]]
fn fragment(in: VertexOutput) -> [[location(0)]] vec4<f32> {
    let resolution = vec2<f32>(view.width, view.height);

    var output_color = fxaa(texture, our_sampler, in.coord, resolution, 
                            in.v_rgbNW, in.v_rgbNE, in.v_rgbSW, in.v_rgbSE, in.v_rgbM);

    return output_color;
}

