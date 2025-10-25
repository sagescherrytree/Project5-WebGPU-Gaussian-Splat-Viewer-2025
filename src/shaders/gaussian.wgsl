struct VertexOutput {
    @builtin(position) position: vec4<f32>,
    //TODO: information passed from vertex shader to fragment shader
    @location(0) v_color: vec3<f32>,
    @location(1) v_conic_opacity: vec4<f32>,
    @location(2) v_center: vec2<f32>
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
    conic_opacity0: u32,
    conic_opacity1: u32
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

    // Obtain sorted index.
    let sortedIndex = sort_indices[instance_index];
    // Read in current splat from sortedIndex.
    let currSplat = splats[sortedIndex];
    
    let posXY = unpack2x16float(currSplat.pos_ndc);
    let size = unpack2x16float(currSplat.size);

    let conicXY = unpack2x16float(currSplat.conic_opacity0);
    let conicZOpacity = unpack2x16float(currSplat.conic_opacity1);

    let depth_variance = conicZOpacity.x;
    let opacity = conicZOpacity.y;

    var pos = vec4<f32>(posXY, 0.0, 1.0);
    var col = currSplat.color;

    let offset = QUAD_OFFSETS[vertex_index] * size;

    let finalPos = vec4<f32>(pos.xy + offset, pos.z, pos.w);

    // Pass out VertexOutput params for frag shader.
    let conicOpacity = vec4<f32>(conicXY.xy, conicZOpacity.xy);

    var out: VertexOutput;
    out.position = finalPos;
    out.v_color = col;
    out.v_conic_opacity = conicOpacity;
    out.v_center = vec2<f32>(posXY);
    return out;
}

@fragment
fn fs_main(in: VertexOutput) -> @location(0) vec4<f32> {
    // Calculate ndc position again.
    var posNdc = (in.position.xy / camera.viewport) * 2.0 - 1.0;
    posNdc.y = -posNdc.y;

    // Offset in ndc.
    let offset = posNdc.xy - in.v_center.xy;
    let A = in.v_conic_opacity.x;
    let B = in.v_conic_opacity.y;
    let C = in.v_conic_opacity.z;

    let power = -0.5 * (A * offset.x * offset.x + 2.0 * B * offset.x * offset.y + C * offset.y * offset.y);

    if (power > 0.0) {
        return vec4<f32>(0.0);
    }

    let alpha = clamp(in.v_conic_opacity.w * exp(power), 0.0, 1.0);

    return vec4<f32>(in.v_color * alpha, alpha);
}