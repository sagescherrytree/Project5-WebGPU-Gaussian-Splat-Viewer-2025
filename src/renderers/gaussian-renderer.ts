import { PointCloud } from '../utils/load';
import preprocessWGSL from '../shaders/preprocess.wgsl';
import renderWGSL from '../shaders/gaussian.wgsl';
import { get_sorter, c_histogram_block_rows, C } from '../sort/sort';
import { Renderer } from './renderer';

export interface GaussianRenderer extends Renderer {
  render_settings_buffer: GPUBuffer
}

// Utility to create GPU buffers
const createBuffer = (
  device: GPUDevice,
  label: string,
  size: number,
  usage: GPUBufferUsageFlags,
  data?: ArrayBuffer | ArrayBufferView
) => {
  const buffer = device.createBuffer({ label, size, usage });
  if (data) device.queue.writeBuffer(buffer, 0, data);
  return buffer;
};

export default function get_renderer(
  pc: PointCloud,
  device: GPUDevice,
  presentation_format: GPUTextureFormat,
  camera_buffer: GPUBuffer,
): GaussianRenderer {

  const sorter = get_sorter(pc.num_points, device);

  // ===============================================
  //            Initialize GPU Buffers
  // ===============================================

  const nulling_data = new Uint32Array([0]);

  // Create null buffer.
  const null_buffer = createBuffer(
    device,
    'null_buffer',
    4,
    GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST, nulling_data
  );

  // Create indirect buffer.
  const indirect_buffer = createBuffer(
    device,
    'indirect_buffer',
    4 * 4,
    GPUBufferUsage.COPY_DST | GPUBufferUsage.INDIRECT,
    new Uint32Array([6, pc.num_points, 0, 0])
  );

  // Create splat buffer.
  const splatBufferSize = pc.num_points * 64;

  const splat_buffer = createBuffer(
    device,
    'splat_buffer',
    splatBufferSize,
    GPUBufferUsage.STORAGE | GPUBufferUsage.COPY_SRC | GPUBufferUsage.COPY_DST
  )

  // Render settings buffer?
  const renderSettings_size = new Float32Array([1.0, pc.sh_deg, 0.0, 0.0]);
  const render_settings_buffer = createBuffer(
    device,
    'render_settings',
    renderSettings_size.byteLength,
    GPUBufferUsage.UNIFORM | GPUBufferUsage.COPY_DST,
    renderSettings_size
  )

  // ===============================================
  //    Create Compute Pipeline and Bind Groups
  // ===============================================
  const preprocess_pipeline = device.createComputePipeline({
    label: 'preprocess',
    layout: 'auto',
    compute: {
      module: device.createShaderModule({ code: preprocessWGSL }),
      entryPoint: 'preprocess',
      constants: {
        workgroupSize: C.histogram_wg_size,
        sortKeyPerThread: c_histogram_block_rows,
      },
    },
  });

  // Holds buffers for splat, camera+gaussian, etc.
  const compute_bind_group = device.createBindGroup({
    label: 'Compute Bind Group',
    layout: preprocess_pipeline.getBindGroupLayout(0),
    entries: [
      { binding: 0, resource: { buffer: camera_buffer } },
      { binding: 1, resource: { buffer: pc.gaussian_3d_buffer } },
      { binding: 2, resource: { buffer: splat_buffer } },
      { binding: 3, resource: { buffer: render_settings_buffer } },
      { binding: 4, resource: { buffer: pc.sh_buffer } },
    ],
  });

  const sort_bind_group = device.createBindGroup({
    label: 'sort',
    layout: preprocess_pipeline.getBindGroupLayout(1),
    entries: [
      { binding: 0, resource: { buffer: sorter.sort_info_buffer } },
      { binding: 1, resource: { buffer: sorter.ping_pong[0].sort_depths_buffer } },
      { binding: 2, resource: { buffer: sorter.ping_pong[0].sort_indices_buffer } },
      { binding: 3, resource: { buffer: sorter.sort_dispatch_indirect_buffer } },
    ],
  });

  // ===============================================
  //    Create Render Pipeline and Bind Groups
  // ===============================================
  const render_pipeline = device.createRenderPipeline({
    label: "render pipeline",
    layout: "auto",
    vertex: {
      module: device.createShaderModule({
        label: "vert shader",
        code: renderWGSL
      }),
      entryPoint: "vs_main",
      buffers: []
    },
    fragment: {
      module: device.createShaderModule({
        label: "frag shader",
        code: renderWGSL
      }),
      targets: [{
        format: presentation_format,
        blend: {
          color: {
            srcFactor: "one",
            dstFactor: "one-minus-src-alpha",
            operation: "add"
          },
          alpha: {
            srcFactor: "one",
            dstFactor: "one-minus-src-alpha",
            operation: "add"
          }
        },
      }],
      entryPoint: "fs_main"
    }
  });

  // create the render pipeline bind group for all other resources
  const render_pipeline_bind_group = device.createBindGroup({
    label: 'render_pipeline_bind_group',
    layout: render_pipeline.getBindGroupLayout(0),
    entries: [

      // declare a new entry for the splat data buffer
      { binding: 0, resource: { buffer: splat_buffer, } },
      { binding: 1, resource: { buffer: sorter.ping_pong[0].sort_indices_buffer } },
      { binding: 2, resource: { buffer: camera_buffer } },
    ],
  });

  // ===============================================
  //    Command Encoder Functions
  // ===============================================
  // Compute pass first for preprocessing (?).
  const compute_pass = (encoder: GPUCommandEncoder) => {
    const preprocess_compute_pass = encoder.beginComputePass();

    // Bind preprocess.
    preprocess_compute_pass.setPipeline(preprocess_pipeline);

    // Set bind groups.
    preprocess_compute_pass.setBindGroup(0, compute_bind_group);
    preprocess_compute_pass.setBindGroup(1, sort_bind_group);

    // Dispatch work groups.
    preprocess_compute_pass.dispatchWorkgroups(Math.ceil(pc.num_points / C.histogram_wg_size));

    // End preprocess pass.
    preprocess_compute_pass.end();
  };

  const render_pass = (encoder: GPUCommandEncoder, texture_view: GPUTextureView) => {
    const gaussian_render_pass = encoder.beginRenderPass({
      label: 'gaussian render pass',
      colorAttachments: [
        {
          view: texture_view,
          loadOp: "clear",
          storeOp: "store",
          clearValue: [
            0.0, 0.0, 0.0, 1.0
          ]
        }]
    });
    // Somewhere here set pipeline and draw indirect buffer.
    gaussian_render_pass.setPipeline(render_pipeline);
    gaussian_render_pass.setBindGroup(0, render_pipeline_bind_group);
    gaussian_render_pass.drawIndirect(indirect_buffer, 0);
    gaussian_render_pass.end();
  };

  // Render pass next.

  // ===============================================
  //    Return Render Object
  // ===============================================
  return {
    frame: (encoder: GPUCommandEncoder, texture_view: GPUTextureView) => {
      encoder.copyBufferToBuffer(
        null_buffer, 0,
        sorter.sort_info_buffer, 0,
        4
      );
      encoder.copyBufferToBuffer(
        null_buffer, 0,
        sorter.sort_dispatch_indirect_buffer, 0,
        4
      );

      // Preprocess first.
      compute_pass(encoder);

      sorter.sort(encoder);

      encoder.copyBufferToBuffer(
        sorter.sort_info_buffer,
        0,
        indirect_buffer,
        4,
        4
      );

      // New render pass.
      // We return the render pass.
      render_pass(encoder, texture_view);
    },
    camera_buffer,
    render_settings_buffer
  };
}
