struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    //TODO: information passed from vertex shader to fragment shader
    @location(0) v_color: vec3<f32>,
};

// Camera uniform struct defines.
struct CameraUniforms {
    view: mat4x4<f32>,
    view_inv: mat4x4<f32>,
    proj: mat4x4<f32>,
    proj_inv: mat4x4<f32>,
    viewport: vec2<f32>,
    focal: vec2<f32>
};

struct Splat {
    //TODO: information defined in preprocess compute shader
    // Same as one in preprocess.
    pos_ndc: u32,
    size: u32,
    color: vec3<f32>,
    depth_opacity: u32
};

// Read in splats from storage buffer that was set up in preprocess.
@group(0) @binding(0)
var<storage, read> splats: array<Splat>;
@group(0) @binding(1)
var<storage, read> sort_indices: array<u32>;
@group(0) @binding(2)
var<uniform> camera: CameraUniforms;

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
    let sortedIndex = sort_indices[instance_index];
    let currSplat = splats[sortedIndex];

    let dummy = camera.view[0][0];

    let posXY = unpack2x16float(currSplat.pos_ndc);
    let size = unpack2x16float(currSplat.size);
    let depth_opacity = unpack2x16float(currSplat.depth_opacity);

    var pos = vec4<f32>(posXY.x, posXY.y, depth_opacity.y, 1.0);
    var col = currSplat.color;
    let opacity = depth_opacity.x;  
    let depth = depth_opacity.y;

    let offset = QUAD_OFFSETS[vertex_index] * f32(size.x);

    var out: VertexOutput;
    out.position = pos;
    out.v_color = col;
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    return vec4<f32>(in.v_color, 1.0);
}