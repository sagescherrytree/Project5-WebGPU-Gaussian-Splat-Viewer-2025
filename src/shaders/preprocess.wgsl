const SH_C0: f32 = 0.28209479177387814;
const SH_C1 = 0.4886025119029199;
const SH_C2 = array<f32,5>(
    1.0925484305920792,
    -1.0925484305920792,
    0.31539156525252005,
    -1.0925484305920792,
    0.5462742152960396
);
const SH_C3 = array<f32,7>(
    -0.5900435899266435,
    2.890611442640554,
    -0.4570457994644658,
    0.3731763325901154,
    -0.4570457994644658,
    1.445305721320277,
    -0.5900435899266435
);

override workgroupSize: u32;
override sortKeyPerThread: u32;

struct DispatchIndirect {
    dispatch_x: atomic<u32>,
    dispatch_y: u32,
    dispatch_z: u32,
}

struct SortInfos {
    keys_size: atomic<u32>,  // instance_count in DrawIndirect
    //data below is for info inside radix sort 
    padded_size: u32, 
    passes: u32,
    even_pass: u32,
    odd_pass: u32,
}

struct CameraUniforms {
    view: mat4x4<f32>,
    view_inv: mat4x4<f32>,
    proj: mat4x4<f32>,
    proj_inv: mat4x4<f32>,
    viewport: vec2<f32>,
    focal: vec2<f32>
};

struct RenderSettings {
    gaussian_scaling: f32,
    sh_deg: f32,
}

struct Gaussian {
    pos_opacity: array<u32,2>,
    rot: array<u32,2>,
    scale: array<u32,2>
};

struct Splat {
    //TODO: store information for 2D splat rendering
    pos_ndc: u32,
    size: u32,
    color: vec3<f32>,
    conic_opacity0: u32,
    conic_opacity1: u32
};

//TODO: bind your data here

@group(0) @binding(0)
var<uniform> camera: CameraUniforms;
// Storage buffer for gaussians.
@group(0) @binding(1)
var<storage, read> gaussians: array<Gaussian>;
@group(0) @binding(2)
var<storage, read_write> splatBuffer: array<Splat>;
@group(0) @binding(3) 
var<uniform> settings: RenderSettings;
@group(0) @binding(4) 
var<storage, read> sh_coeffs: array<u32>;

@group(1) @binding(0)
var<storage, read_write> sort_infos: SortInfos;
@group(1) @binding(1)
var<storage, read_write> sort_depths : array<u32>;
@group(1) @binding(2)
var<storage, read_write> sort_indices : array<u32>;
@group(1) @binding(3)
var<storage, read_write> sort_dispatch: DispatchIndirect;

/// reads the ith sh coef from the storage buffer 
fn sh_coef(splat_idx: u32, c_idx: u32) -> vec3<f32> {
    //TODO: access your binded sh_coeff, see load.ts for how it is stored
    let base_index = splat_idx * 24u + (c_idx / 2u) * 3u + (c_idx % 2u);
    let color01 = unpack2x16float(sh_coeffs[base_index + 0u]);
    let color23 = unpack2x16float(sh_coeffs[base_index + 1u]);
    if ((c_idx & 1u) == 0u) {
        return vec3<f32>(color01.x, color01.y, color23.x);
    } else {
        return vec3<f32>(color01.y, color23.x, color23.y);
    }
}

// spherical harmonics evaluation with Condon–Shortley phase
fn computeColorFromSH(dir: vec3<f32>, v_idx: u32, sh_deg: u32) -> vec3<f32> {
    var result = SH_C0 * sh_coef(v_idx, 0u);

    if sh_deg > 0u {

        let x = dir.x;
        let y = dir.y;
        let z = dir.z;

        result += - SH_C1 * y * sh_coef(v_idx, 1u) + SH_C1 * z * sh_coef(v_idx, 2u) - SH_C1 * x * sh_coef(v_idx, 3u);

        if sh_deg > 1u {

            let xx = dir.x * dir.x;
            let yy = dir.y * dir.y;
            let zz = dir.z * dir.z;
            let xy = dir.x * dir.y;
            let yz = dir.y * dir.z;
            let xz = dir.x * dir.z;

            result += SH_C2[0] * xy * sh_coef(v_idx, 4u) + SH_C2[1] * yz * sh_coef(v_idx, 5u) + SH_C2[2] * (2.0 * zz - xx - yy) * sh_coef(v_idx, 6u) + SH_C2[3] * xz * sh_coef(v_idx, 7u) + SH_C2[4] * (xx - yy) * sh_coef(v_idx, 8u);

            if sh_deg > 2u {
                result += SH_C3[0] * y * (3.0 * xx - yy) * sh_coef(v_idx, 9u) + SH_C3[1] * xy * z * sh_coef(v_idx, 10u) + SH_C3[2] * y * (4.0 * zz - xx - yy) * sh_coef(v_idx, 11u) + SH_C3[3] * z * (2.0 * zz - 3.0 * xx - 3.0 * yy) * sh_coef(v_idx, 12u) + SH_C3[4] * x * (4.0 * zz - xx - yy) * sh_coef(v_idx, 13u) + SH_C3[5] * z * (xx - yy) * sh_coef(v_idx, 14u) + SH_C3[6] * x * (xx - 3.0 * yy) * sh_coef(v_idx, 15u);
            }
        }
    }
    result += 0.5;

    return  max(vec3<f32>(0.), result);
}

@compute @workgroup_size(workgroupSize,1,1)
fn preprocess(@builtin(global_invocation_id) gid: vec3<u32>, @builtin(num_workgroups) wgs: vec3<u32>) {
    let idx = gid.x;
    //TODO: set up pipeline as described in instruction
    // Length check for gaussians buffer.
    if(idx >= arrayLength(&gaussians)){
        return;
    }

    // Unpack Gaussian data.
    let currGaussian = gaussians[idx];

    let xy = unpack2x16float(currGaussian.pos_opacity[0]);
    let z_opacity = unpack2x16float(currGaussian.pos_opacity[1]);
    let position = vec3<f32>(xy, z_opacity.x); 
    let alpha = f32(z_opacity.y);

    // Project position to NDC.
    let viewPos = (camera.view * vec4<f32>(position, 1.0f)).xyz;
    let clipPos = camera.proj * camera.view * vec4<f32>(position, 1.0);
    let posNdc = clipPos.xyz/clipPos.w;

    // Check if outside bounds, if yes, then cull.
    if (any(posNdc.xy < vec2<f32>(-1.2)) || any(posNdc.xy > vec2<f32>(1.2)) || posNdc.z < 0.0 || posNdc.z > 1.0) {
        return;
    }

    // Compute 3D covariance.

    // Unpack rotation.
    let rotationXY = unpack2x16float(currGaussian.rot[0]);
    let rotationZW = unpack2x16float(currGaussian.rot[1]);

    let rotation = vec4f(
        rotationXY.x,
        rotationXY.y,
        rotationZW.x,
        rotationZW.y
    );

    // Unpack scale.
    let scaleXY = unpack2x16float(currGaussian.scale[0]);
    let scaleZW = unpack2x16float(currGaussian.scale[1]);

    let scale = exp(vec3<f32>(
        scaleXY.x,
        scaleXY.y,
        scaleZW.x
    ));

    // Compute R matrix.
    let nq = normalize(rotation);

    let R = mat3x3<f32>(
        vec3<f32>(
            1.0 - 2.0*(nq.y*nq.y + nq.z*nq.z),
            2.0*(nq.x*nq.y + nq.z*nq.w),
            2.0*(nq.x*nq.z - nq.y*nq.w)
        ),
        vec3<f32>(
            2.0*(nq.x*nq.y - nq.z*nq.w),
            1.0 - 2.0*(nq.x*nq.x + nq.z*nq.z),
            2.0*(nq.y*nq.z + nq.x*nq.w)
        ),
        vec3<f32>(
            2.0*(nq.x*nq.z + nq.y*nq.w),
            2.0*(nq.y*nq.z - nq.x*nq.w),
            1.0 - 2.0*(nq.x*nq.x + nq.y*nq.y)
        )
    );

    // Construct S matrix.
    let S = mat3x3<f32>(
        vec3<f32>(scale.x, 0.0, 0.0),
        vec3<f32>(0.0, scale.y, 0.0),
        vec3<f32>(0.0, 0.0, scale.z)
    );

    // Compute M matrix.
    let M = S * R;

    // Compute 3D covariance matrix.
    let covar_3D_M = transpose(M) * M;

    let covar_3D = array<f32,6>(
        covar_3D_M[0][0],
        covar_3D_M[0][1],
        covar_3D_M[0][2],
        covar_3D_M[1][1],
        covar_3D_M[1][2],
        covar_3D_M[2][2]
    );

    // Compute t vector.
    var t = (camera.view * vec4<f32>(position, 1.0)).xyz;
    let limx = 0.65 * camera.viewport.x / camera.focal.x;
    let limy = 0.65 * camera.viewport.y / camera.focal.y;
    let txtz = t.x / t.z;
    let tytz = t.y / t.z;
    t.x = min(limx, max(-limx, txtz)) * t.z;
    t.y = min(limy, max(-limy, tytz)) * t.z;

    // Compute Jacobian.
    let J = mat3x3<f32>(
        camera.focal.x / t.z, 0.0f, -(camera.focal.x * t.x) / (t.z * t.z),
        0.0f, camera.focal.y / t.z, -(camera.focal.y * t.y) / (t.z * t.z),
        0.0f, 0.0f, 0.0f
    );

    // Compute W matrix.
    let W = transpose(mat3x3<f32>(
        camera.view[0].xyz, 
        camera.view[1].xyz, 
        camera.view[2].xyz
    ));

    // Comute T matrix.
    let T = W * J;

    // Get V matrix.
    let V = mat3x3<f32>(
        vec3<f32>(covar_3D[0], covar_3D[1], covar_3D[2]),
        vec3<f32>(covar_3D[1], covar_3D[3], covar_3D[4]),
        vec3<f32>(covar_3D[2], covar_3D[4], covar_3D[5])
    );

    // Calculate 2D covariance matrix.
    var covar_2D_M = transpose(T) * transpose(V) * T;
    covar_2D_M[0][0] += 0.3f;
    covar_2D_M[1][1] += 0.3f;

    // Compute 2D covariance.
    let covar_2D = vec3<f32>(
        covar_2D_M[0][0],
        covar_2D_M[0][1],
        covar_2D_M[1][1]
    );

    // Calculate determinant.
    var determinant = covar_2D.x * covar_2D.z - (covar_2D.y * covar_2D.y);
    if (determinant == 0.0) {
        return;
    }

    // Calculate radius.
    let mid = (covar_2D.x + covar_2D.z) * 0.5f;
    let lambda1 = mid + sqrt(max(0.1f, mid * mid - determinant));
    let lambda2 = mid - sqrt(max(0.1f, mid * mid - determinant));
    let radius = ceil(3.0f * sqrt(max(lambda1, lambda2)));

    // Calculate size (please work...).
    let size = vec2<f32>(radius, radius) / camera.viewport;

    let scaleSettings = settings.gaussian_scaling;
    let testingSH = sh_coeffs[0];
    let sortIdx = atomicAdd(&sort_infos.keys_size, 1u);

    let sortDepth = sort_depths[0];
    let sortIndices = sort_indices[0]; 
    let sortDispatch = atomicAdd(&sort_dispatch.dispatch_x, 0u); 

    // Pack stuff into new splat struct, to render in gaussian.wgsl.
    let packedPosNdc = pack2x16float(posNdc.xy);
    let packedSize = pack2x16float(size);

    // Compute conic.
    let conic = vec3<f32>(
        covar_2D.z / determinant,
        -covar_2D.y / determinant,
        covar_2D.x / determinant,
    );

    let opacity_f = 1.0 / (1.0 + exp(-alpha));

    let splatCol = computeColorFromSH(normalize(position), idx, u32(settings.sh_deg));

    splatBuffer[sortIdx].pos_ndc = packedPosNdc;
    splatBuffer[sortIdx].size = packedSize;
    splatBuffer[sortIdx].color = splatCol;
    
    let packedConicXY: u32 = pack2x16float(conic.xy);
    let packedConicZOpacity: u32 = pack2x16float(vec2<f32>(conic.z, opacity_f));

    splatBuffer[sortIdx].conic_opacity0 = packedConicXY;
    splatBuffer[sortIdx].conic_opacity1 = packedConicZOpacity;

    sort_indices[sortIdx] = sortIdx;
    sort_depths[sortIdx]= bitcast<u32>(100.0 - viewPos.z);

    let keys_per_dispatch = workgroupSize * sortKeyPerThread; 
    // increment DispatchIndirect.dispatchx each time you reach limit for one dispatch of keys
    if (sortIdx % keys_per_dispatch == 0){
        atomicAdd(&sort_dispatch.dispatch_x, 1);
    }
}