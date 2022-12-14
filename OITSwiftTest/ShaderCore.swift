//
//  ShaderCore.swift
//  OITSwiftTest
//
//  Created by Yuki Kuwashima on 2022/12/14.
//

import Metal

public final class ShaderCore {
    public static let device: MTLDevice = MTLCreateSystemDefaultDevice()!
    public static var library: MTLLibrary = {
        return try! ShaderCore.device.makeDefaultLibrary(bundle: Bundle.main)
    }()
    public static var commandQueue: MTLCommandQueue = {
        return ShaderCore.device.makeCommandQueue()!
    }()
}
