// SPDX-License-Identifier: LGPL-2.1-or-later
// Copyright (C) 2026 Roger Sodre and vlc-syphon-ndi contributors
//
// Rotates the hue of every image in an .iconset, e.g. turning the orange
// VLCSyphon icon NDI-blue. Used by apps/scripts/make-icons.sh.
//
// Usage: swift tint-icon.swift <in.iconset> <out.iconset> <hue-degrees>

import CoreImage
import Foundation
import ImageIO
import UniformTypeIdentifiers

let args = CommandLine.arguments
guard args.count == 4, let degrees = Double(args[3]) else {
    FileHandle.standardError.write("usage: tint-icon <in.iconset> <out.iconset> <hue-degrees>\n".data(using: .utf8)!)
    exit(2)
}
let input = URL(fileURLWithPath: args[1])
let output = URL(fileURLWithPath: args[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

let context = CIContext(options: [.workingColorSpace: CGColorSpace(name: CGColorSpace.sRGB)!])
for name in try FileManager.default.contentsOfDirectory(atPath: input.path) where name.hasSuffix(".png") {
    guard let image = CIImage(contentsOf: input.appendingPathComponent(name)) else { continue }
    let filter = CIFilter(name: "CIHueAdjust")!
    filter.setValue(image, forKey: kCIInputImageKey)
    filter.setValue(degrees * .pi / 180, forKey: kCIInputAngleKey)
    guard let tinted = filter.outputImage,
          let cg = context.createCGImage(tinted, from: image.extent),
          let dest = CGImageDestinationCreateWithURL(output.appendingPathComponent(name) as CFURL,
                                                     UTType.png.identifier as CFString, 1, nil)
    else { exit(1) }
    CGImageDestinationAddImage(dest, cg, nil)
    CGImageDestinationFinalize(dest)
}
