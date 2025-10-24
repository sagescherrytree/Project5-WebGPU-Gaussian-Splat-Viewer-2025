struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    //TODO: information passed from vertex shader to fragment shader
    @location(0) v_color: vec3<f32>,
};

struct Splat {
    //TODO: information defined in preprocess compute shader
    // Same as one in preprocess.
    pos_ndc: vec3<f32>, // Splat position in ndc (covariance?).
    size: f32,
    color: vec3<f32>,
    opacity: f32, // Might need to decide if this gets pack w/ pos later...
    depth: f32, // For sorting by depth later.
};

// Read in splats from storage buffer that was set up in preprocess.
@group(0) @binding(0)var<storage, read> splats: array<Splat>;

// Quad offsets.
const QUAD_OFFSETS = array<vec2<f32>, 6>(
    vec2<f32>(-1.0, -1.0),
    vec2<f32>( 1.0, -1.0),
    vec2<f32>(-1.0,  1.0),
    vec2<f32>(-1.0,  1.0),
    vec2<f32>( 1.0, -1.0),
    vec2<f32>( 1.0,  1.0),
);


@vertex
fn vs_main(
    @builtin(instance_index) instance_index: u32,
    @builtin(vertex_index) vertex_index: u32
) -> VertexOutput {
    //TODO: reconstruct 2D quad based on information from splat, pass 

    // Read in current splat from splats[instance_index].
    let currSplat = splats[instance_index];
    let offset = QUAD_OFFSETS[vertex_index] * currSplat.size * 0.01;

    var pos = vec4<f32>(currSplat.pos_ndc.x + offset.x, currSplat.pos_ndc.y + offset.y, currSplat.pos_ndc.z, 1.0);
    var col = currSplat.color;

    var out: VertexOutput;
    out.position = pos;
    out.v_color = col;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(in.v_color, 1.0);
}