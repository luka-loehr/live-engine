#!/usr/bin/env swift

import AppKit
import Foundation

// Get input and output paths
let inputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets/Icons/app-icon.png"
let outputPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Assets/Icons/MenuBarIcon.png"

guard let inputImage = NSImage(contentsOfFile: inputPath) else {
    print("Error: Could not load image from \(inputPath)")
    exit(1)
}

// Get the actual image representation
guard let cgImage = inputImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    print("Error: Could not get CGImage representation")
    exit(1)
}

// Target size: 36x36 pixels (18x18 points @2x for Retina)
let targetSize = NSSize(width: 36, height: 36)

// Create a new image context
let colorSpace = CGColorSpaceCreateDeviceRGB()
let bitmapInfo = CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue)
guard let context = CGContext(
    data: nil,
    width: Int(targetSize.width),
    height: Int(targetSize.height),
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: bitmapInfo.rawValue
) else {
    print("Error: Could not create graphics context")
    exit(1)
}

// Draw and resize the image
context.interpolationQuality = .high
context.draw(cgImage, in: CGRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height))

guard let resizedCGImage = context.makeImage() else {
    print("Error: Could not create resized image")
    exit(1)
}

// Convert to grayscale and apply threshold for monochrome template
let width = Int(targetSize.width)
let height = Int(targetSize.height)
let bytesPerPixel = 4
let bytesPerRow = width * bytesPerPixel
let data = context.data!.assumingMemoryBound(to: UInt8.self)

// Convert to grayscale and create monochrome template
for y in 0..<height {
    for x in 0..<width {
        let pixelIndex = (y * bytesPerRow) + (x * bytesPerPixel)
        let r = Int(data[pixelIndex])
        let g = Int(data[pixelIndex + 1])
        let b = Int(data[pixelIndex + 2])
        let _ = Int(data[pixelIndex + 3]) // Alpha channel (not used in threshold calculation)
        
        // Calculate luminance
        let luminance = (r * 299 + g * 587 + b * 114) / 1000
        
        // Apply threshold (128) to create black/white
        // For template images, we want black shapes on transparent background
        let threshold: Int = 128
        let value: UInt8 = luminance > threshold ? 255 : 0
        
        // Set RGB to the same value (grayscale) and keep alpha
        data[pixelIndex] = value     // R
        data[pixelIndex + 1] = value // G
        data[pixelIndex + 2] = value // B
        // Alpha stays the same
    }
}

// Create final image from modified data
guard let finalCGImage = context.makeImage() else {
    print("Error: Could not create final image")
    exit(1)
}

let finalImage = NSImage(cgImage: finalCGImage, size: targetSize)
finalImage.isTemplate = true

// Save as PNG
guard let tiffData = finalImage.tiffRepresentation,
      let bitmapImage = NSBitmapImageRep(data: tiffData),
      let pngData = bitmapImage.representation(using: .png, properties: [:]) else {
    print("Error: Could not convert to PNG")
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Successfully created menu bar icon: \(outputPath)")
    print("Size: \(Int(targetSize.width))x\(Int(targetSize.height)) pixels (18x18 points @2x)")
} catch {
    print("Error: Could not save image: \(error)")
    exit(1)
}
