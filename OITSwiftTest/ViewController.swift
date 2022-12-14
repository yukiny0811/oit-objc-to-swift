//
//  ViewController.swift
//  OITSwiftTest
//
//  Created by Yuki Kuwashima on 2022/12/14.
//

import UIKit
import MetalKit

struct AAPLFrameUniforms {
    var projectionMatrix: simd_float4x4
    var viewMatrix: simd_float4x4
    static var memorySize: Int {
        return MemoryLayout<AAPLFrameUniforms>.stride
    }
}

class ViewController: UIViewController {
    
    let renderer: Renderer = Renderer()

    override func viewDidLoad() {
        super.viewDidLoad()
        
        let metalView = MTKView(frame: self.view.bounds, device: ShaderCore.device)
        metalView.colorPixelFormat = .bgra8Unorm_srgb
        metalView.depthStencilPixelFormat = .depth32Float_stencil8
        metalView.sampleCount = 1
        metalView.delegate = renderer
        self.view.addSubview(metalView)
    }
}

class Renderer: NSObject, MTKViewDelegate {
    
    var frameUniformBuffer: MTLBuffer
    var pipelineState: MTLRenderPipelineState
    var depthState: MTLDepthStencilState
    var clearTileState: MTLRenderPipelineState
    var resolveState: MTLRenderPipelineState
    var vertexDescriptor: MTLVertexDescriptor
    
    let optimalTileSize = MTLSize(width: 32, height: 16, depth: 1)
    
    override init() {
        
        // MARK: - functions
        let constantValue = MTLFunctionConstantValues()
        let transparencyMethodFragmentFunction = try! ShaderCore.library.makeFunction(name: "OITFragmentFunction_4Layer", constantValues: constantValue)
        let vertexFunction = ShaderCore.library.makeFunction(name: "vertexTransform")
        let resolveFunction = try! ShaderCore.library.makeFunction(name: "OITResolve_4Layer", constantValues: constantValue)
        let clearFunction = try! ShaderCore.library.makeFunction(name: "OITClear_4Layer", constantValues: constantValue)
        
        // MARK: - vertexDescriptor
        vertexDescriptor = MTLVertexDescriptor()
        
        vertexDescriptor.attributes[0].format = .float3
        vertexDescriptor.attributes[0].offset = 0
        vertexDescriptor.attributes[0].bufferIndex = 0
        
        vertexDescriptor.attributes[1].format = .float4
        vertexDescriptor.attributes[1].offset = 0
        vertexDescriptor.attributes[1].bufferIndex = 1
        
        vertexDescriptor.attributes[2].format = .float3
        vertexDescriptor.attributes[2].offset = 0
        vertexDescriptor.attributes[2].bufferIndex = 2
        
        vertexDescriptor.attributes[3].format = .float3
        vertexDescriptor.attributes[3].offset = 0
        vertexDescriptor.attributes[3].bufferIndex = 3
        
        vertexDescriptor.attributes[4].format = .float3
        vertexDescriptor.attributes[4].offset = 0
        vertexDescriptor.attributes[4].bufferIndex = 4
        
        vertexDescriptor.layouts[0].stride = 12
        vertexDescriptor.layouts[0].stepRate = 1
        vertexDescriptor.layouts[0].stepFunction = .perVertex
        
        vertexDescriptor.layouts[1].stride = 16
        vertexDescriptor.layouts[1].stepRate = 1
        vertexDescriptor.layouts[1].stepFunction = .perVertex
        
        vertexDescriptor.layouts[2].stride = 12
        vertexDescriptor.layouts[2].stepRate = 1
        vertexDescriptor.layouts[2].stepFunction = .perVertex
        
        vertexDescriptor.layouts[3].stride = 12
        vertexDescriptor.layouts[3].stepRate = 1
        vertexDescriptor.layouts[3].stepFunction = .perVertex
        
        vertexDescriptor.layouts[4].stride = 12
        vertexDescriptor.layouts[4].stepRate = 1
        vertexDescriptor.layouts[4].stepFunction = .perVertex
        
        // MARK: - render pipeline descriptor
        let pipelineStateDescriptor = MTLRenderPipelineDescriptor()
        pipelineStateDescriptor.vertexDescriptor = vertexDescriptor
        pipelineStateDescriptor.vertexFunction = vertexFunction
        pipelineStateDescriptor.sampleCount = 1
        pipelineStateDescriptor.depthAttachmentPixelFormat = .depth32Float_stencil8
        pipelineStateDescriptor.stencilAttachmentPixelFormat = .depth32Float_stencil8
        pipelineStateDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        pipelineStateDescriptor.colorAttachments[0].isBlendingEnabled = false
//        pipelineStateDescriptor.colorAttachments[0].writeMask = .none //これはなんだ
        pipelineStateDescriptor.fragmentFunction = transparencyMethodFragmentFunction
        pipelineState = try! ShaderCore.device.makeRenderPipelineState(descriptor: pipelineStateDescriptor)
        
        // MARK: - Tile descriptor
        let tileDesc = MTLTileRenderPipelineDescriptor()
        tileDesc.tileFunction = resolveFunction
        tileDesc.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        tileDesc.threadgroupSizeMatchesTileSize = true
        resolveState = try! ShaderCore.device.makeRenderPipelineState(tileDescriptor: tileDesc, options: .argumentInfo, reflection: nil) // FIXME: argumentinfo?
        
        tileDesc.tileFunction = clearFunction
        clearTileState = try! ShaderCore.device.makeRenderPipelineState(tileDescriptor: tileDesc, options: .argumentInfo, reflection: nil) // FIXME: argumentinfo?
        
        // MARK: - Depth Descriptor
        let depthStateDesc = MTLDepthStencilDescriptor()
        depthStateDesc.depthCompareFunction = .less
        depthStateDesc.isDepthWriteEnabled = false
        depthState = ShaderCore.device.makeDepthStencilState(descriptor: depthStateDesc)!
        
        let frameUniforms: [AAPLFrameUniforms] = [
            AAPLFrameUniforms(
                projectionMatrix: MathUtil.makePrespective(
                    rad: 65.0 * (Float.pi / 180.0),
                    aspect: 2.1, //FIXME: あとでなおす
                    near: 1,
                    far: 5000
                ),
                viewMatrix: MathUtil.makeTranslationMatrix(x: 0, y: 0, z: 1000)
            )
        ]
        
        // MARK: frame uniform buffer
        frameUniformBuffer = ShaderCore.device.makeBuffer(bytes: frameUniforms, length: AAPLFrameUniforms.memorySize, options: .storageModeShared)!
        
        super.init()
    }
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        
    }
    func draw(in view: MTKView) {
        let commandBuffer = ShaderCore.commandQueue.makeCommandBuffer()!
        
        // MARK: - render pass descriptor
        let renderPassDescriptor = view.currentRenderPassDescriptor!
        renderPassDescriptor.tileWidth = optimalTileSize.width
        renderPassDescriptor.tileHeight = optimalTileSize.height
        renderPassDescriptor.imageblockSampleLength = resolveState.imageblockSampleLength
        
        
        // MARK: - render encoder
        let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor)!
        
        renderEncoder.setRenderPipelineState(clearTileState)
        renderEncoder.dispatchThreadsPerTile(optimalTileSize)
        renderEncoder.setCullMode(.none)
        renderEncoder.setDepthStencilState(depthState)
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // MARK: - set buffer
        renderEncoder.setVertexBuffer(frameUniformBuffer, offset: 0, index: 5)
        renderEncoder.setFragmentBuffer(frameUniformBuffer, offset: 0, index: 5)
        
        // MARK: - draw primitive
        
        let pos: [simd_float3] = [
            simd_float3(-1, -1,  0),
            simd_float3(1, -1,  0),
            simd_float3(0, 1,  0)
        ]
        let col: [simd_float4] = [
            simd_float4(1, 0, 1, 0.5),
            simd_float4(1, 0, 1, 0.5),
            simd_float4(1, 0, 1, 0.5)
        ]
        let mPos: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(0, 0, 0),
            simd_float3(0, 0, 0)
        ]
        let mRot: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(0, 0, 0),
            simd_float3(0, 0, 0)
        ]
        let mScale: [simd_float3] = [
            simd_float3(100, 100, 100),
            simd_float3(100, 100, 100),
            simd_float3(100, 100, 100)
        ]
        let posBuf = ShaderCore.device.makeBuffer(bytes: pos, length: MemoryLayout<simd_float3>.stride * pos.count, options: .storageModeShared)
        let colBuf = ShaderCore.device.makeBuffer(bytes: col, length: MemoryLayout<simd_float4>.stride * col.count, options: .storageModeShared)
        let mPosBuf = ShaderCore.device.makeBuffer(bytes: mPos, length: MemoryLayout<simd_float3>.stride * mPos.count, options: .storageModeShared)
        let mRotBuf = ShaderCore.device.makeBuffer(bytes: mRot, length: MemoryLayout<simd_float3>.stride * mRot.count, options: .storageModeShared)
        let mScaleBuf = ShaderCore.device.makeBuffer(bytes: mScale, length: MemoryLayout<simd_float3>.stride * mScale.count, options: .storageModeShared)
        renderEncoder.setVertexBuffer(posBuf, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(colBuf, offset: 0, index: 1)
        renderEncoder.setVertexBuffer(mPosBuf, offset: 0, index: 2)
        renderEncoder.setVertexBuffer(mRotBuf, offset: 0, index: 3)
        renderEncoder.setVertexBuffer(mScaleBuf, offset: 0, index: 4)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        
//         TODO: pos2
        let pos2: [simd_float3] = [
            simd_float3(-1, -1,  0),
            simd_float3(1, -1,  0),
            simd_float3(0, 1,  0)
        ]
        let col2: [simd_float4] = [
            simd_float4(1, 0, 1, 0.5),
            simd_float4(1, 1, 1, 0.5),
            simd_float4(1, 1, 1, 0.5)
        ]
        let mPos2: [simd_float3] = [
            simd_float3(0, 0, 0),
            simd_float3(0, 0, 0),
            simd_float3(0, 0, 0)
        ]
        let mRot2: [simd_float3] = [
            simd_float3(1, 0, 0),
            simd_float3(0, 1, 0),
            simd_float3(0, 0, 1)
        ]
        let mScale2: [simd_float3] = [
            simd_float3(100, 100, 100),
            simd_float3(100, 100, 100),
            simd_float3(100, 100, 100)
        ]
        let posBuf2 = ShaderCore.device.makeBuffer(bytes: pos2, length: MemoryLayout<simd_float3>.stride * pos2.count, options: .storageModeShared)
        let colBuf2 = ShaderCore.device.makeBuffer(bytes: col2, length: MemoryLayout<simd_float4>.stride * col2.count, options: .storageModeShared)
        let mPosBuf2 = ShaderCore.device.makeBuffer(bytes: mPos2, length: MemoryLayout<simd_float3>.stride * mPos2.count, options: .storageModeShared)
        let mRotBuf2 = ShaderCore.device.makeBuffer(bytes: mRot2, length: MemoryLayout<simd_float3>.stride * mRot2.count, options: .storageModeShared)
        let mScaleBuf2 = ShaderCore.device.makeBuffer(bytes: mScale2, length: MemoryLayout<simd_float3>.stride * mScale2.count, options: .storageModeShared)
        renderEncoder.setVertexBuffer(posBuf2, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(colBuf2, offset: 0, index: 1)
        renderEncoder.setVertexBuffer(mPosBuf2, offset: 0, index: 2)
        renderEncoder.setVertexBuffer(mRotBuf2, offset: 0, index: 3)
        renderEncoder.setVertexBuffer(mScaleBuf2, offset: 0, index: 4)
        renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 3)
        
        // MARK: - end encoding
        renderEncoder.setRenderPipelineState(resolveState)
        renderEncoder.dispatchThreadsPerTile(optimalTileSize)
        renderEncoder.endEncoding()
        
        // MARK: - commit buffer
        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
}
