# Project5-WebGPU-Gaussian-Splat-Viewer

**University of Pennsylvania, CIS 565: GPU Programming and Architecture, Project 5**

* Jacqueline (Jackie) Li
  * [LinkedIn](https://www.linkedin.com/in/jackie-lii/), [personal website](https://sites.google.com/seas.upenn.edu/jacquelineli/home), [Instagram](https://www.instagram.com/sagescherrytree/), etc.
* Tested on: : Chrome/141.0.7390.67, : Windows NT 10.0.19045.6332, 11th Gen Intel(R) Core(TM) i7-11800H @ 2.30GHz, NVIDIA GeForce RTX 3060 Laptop GPU (6 GB)

### Live Demo

[Demo Link](https://sagescherrytree.github.io/Project5-WebGPU-Gaussian-Splat-Viewer-2025/)
[![](img/HUGEHUGEHUGEBIKE.png)](https://sagescherrytree.github.io/Project5-WebGPU-Gaussian-Splat-Viewer-2025/)

### Demo Video/GIF

| ![](img/demo_bicycle.gif) | ![](img/demo_bonsai.gif) |
|:--:|:--:|
| Bicycle | Bonsai |

## Gaussian Splats Overview

Gaussian Splats is a concept first introduced in the paper [3D Gaussian Splatting for Real Time Rendering](https://repo-sam.inria.fr/fungraph/3d-gaussian-splatting/) by Kerbl et al at SIGGRAPH 2023. It is a concept which significantly optimised the neural radiance fields methodology, by representing the scene in 3D Gaussians that each carry properties of position, colour, size, and depth to recreate the scene while reducing unnecessary computations and thus optimising the runtime.

## Performance Anaylsis

### Number of Points v. Runtime Pointclouds and Runtime Gaussian

|    Scene    |  # of Points   | Pointclouds | Gaussian Splat |
|-------------|----------------|-------------|----------------|
| bicycle.ply |     1063091    |     144     |       60       |
| bonsai.ply  |     272956     |     140     |       144      |

| ![](img/pointClouds_v_splats.png) |
|:--:|

### Gaussian Multiplier v. Runtime per Scene

| Multiplier | bicycle.ply | bonsai.ply |
|------------|-------------|------------|
|    0.0     |     54      |    144     |
|    1.0     |     60      |    144     |
|    1.5     |     17      |    84      |

| ![](img/gaussianMult_v_FPS.png) |
|:--:|

### Credits

- [Vite](https://vitejs.dev/)
- [tweakpane](https://tweakpane.github.io/docs//v3/monitor-bindings/)
- [stats.js](https://github.com/mrdoob/stats.js)
- [wgpu-matrix](https://github.com/greggman/wgpu-matrix)
- Special Thanks to: Shrek Shao (Google WebGPU team) & [Differential Guassian Renderer](https://github.com/graphdeco-inria/diff-gaussian-rasterization)
