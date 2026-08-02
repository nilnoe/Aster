//! Metal 文本管线资源（T-012，ADR-016；T-013 拆出，Rule 3 单文件 ≤300 行）。
//!
//! 决策依据：shader 源码内嵌编译，保持 SPM 纯 Swift 构建（ADR-016，Rule 9）；
//! 顶点布局与混合状态是 ADR-016 决定的 GPU 缓冲格式的机械实现，集中一处便于审计。

import Metal

enum MetalPipeline {
  static let shaderSource = """
    #include <metal_stdlib>
    using namespace metal;

    struct VertexIn {
        float2 position [[attribute(0)]];
        float2 uv [[attribute(1)]];
        float4 color [[attribute(2)]];
    };

    struct VertexOut {
        float4 position [[position]];
        float2 uv;
        float4 color;
    };

    vertex VertexOut vertex_main(VertexIn in [[stage_in]]) {
        VertexOut out;
        out.position = float4(in.position, 0.0, 1.0);
        out.uv = in.uv;
        out.color = in.color;
        return out;
    }

    fragment float4 fragment_main(VertexIn in [[stage_in]],
                                  texture2d<float> atlas [[texture(0)]],
                                  sampler atlas_sampler [[sampler(0)]]) {
        float4 tex = atlas.sample(atlas_sampler, in.uv);
        // 图集为预乘 alpha：顶点色 × 纹理色即得正确的预乘输出（ADR-016 备注）。
        return float4(in.color.rgb * tex.rgb, in.color.a * tex.a);
    }
    """

  /// 渲染管线：32B/顶点（位置 float2 + UV float2 + 颜色 float4）+ 预乘 alpha 混合。
  static func makePipeline(device: MTLDevice, library: MTLLibrary) -> MTLRenderPipelineState? {
    let descriptor = MTLRenderPipelineDescriptor()
    descriptor.vertexFunction = library.makeFunction(name: "vertex_main")
    descriptor.fragmentFunction = library.makeFunction(name: "fragment_main")

    let layout = descriptor.vertexDescriptor!.layouts[0]!
    layout.stride = 32
    layout.stepFunction = .perVertex
    let attrs = descriptor.vertexDescriptor!.attributes
    attrs[0].format = .float2
    attrs[0].offset = 0
    attrs[0].bufferIndex = 0
    attrs[1].format = .float2
    attrs[1].offset = 8
    attrs[1].bufferIndex = 0
    attrs[2].format = .float4
    attrs[2].offset = 16
    attrs[2].bufferIndex = 0

    let attachment = descriptor.colorAttachments[0]!
    attachment.pixelFormat = .bgra8Unorm
    attachment.isBlendingEnabled = true
    attachment.rgbBlendOperation = .add
    attachment.alphaBlendOperation = .add
    attachment.sourceRGBBlendFactor = .one
    attachment.sourceAlphaBlendFactor = .one
    attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
    attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha

    return try? device.makeRenderPipelineState(descriptor: descriptor)
  }

  /// 采样器：字形位图与 quad 像素 1:1，nearest 避免插值发糊（BUG-001）。
  static func makeSampler(device: MTLDevice) -> MTLSamplerState? {
    let descriptor = MTLSamplerDescriptor()
    descriptor.minFilter = .nearest
    descriptor.magFilter = .nearest
    descriptor.sAddressMode = .clampToEdge
    descriptor.tAddressMode = .clampToEdge
    return device.makeSamplerState(descriptor: descriptor)
  }
}
