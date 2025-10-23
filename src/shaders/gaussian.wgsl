struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    //TODO: information passed from vertex shader to fragment shader
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

@vertex
fn vs_main(
    @builtin(instance_index) instance_index: u32,
) -> VertexOutput {
    //TODO: reconstruct 2D quad based on information from splat, pass 

    // Read in current splat from splats[instance_index].
    let currSplat = splats[instance_index];

    var out: VertexOutput;
    out.position = vec4<f32>(1. ,1. , 0., 1.);
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(1.);
}