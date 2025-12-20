#!/usr/bin/env swift

import AppKit
import Foundation
import CoreImage

// Get input and output paths
let inputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets/Icons/app-icon.png"
let outputPath = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "Assets/Icons/MenuBarIcon.png"

guard let inputImage = NSImage(contentsOfFile: inputPath) else {
    print("Error: Could not load image from \(inputPath)")
    exit(1)
}

// Target size: 36x36 pixels (18x18 points @2x for Retina)
let targetSize = NSSize(width: 36, height: 36)

// Create a new image representation
let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                          pixelsWide: Int(targetSize.width),
                          pixelsHigh: Int(targetSize.height),
                          bitsPerSample: 8,
                          samplesPerPixel: 4,
                          hasAlpha: true,
                          isPlanar: false,
                          colorSpaceName: .deviceRGB,
                          bytesPerRow: 0,
                          bitsPerPixel: 0)!

// Create graphics context
NSGraphicsContext.saveGraphicsState()
let context = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = context

// Draw and resize the input image
inputImage.draw(in: NSRect(x: 0, y: 0, width: targetSize.width, height: targetSize.height),
                from: NSRect.zero,
                operation: .sourceOver,
                fraction: 1.0)

NSGraphicsContext.restoreGraphicsState()

// Convert to grayscale and create monochrome template
let width = Int(targetSize.width)
let height = Int(targetSize.height)
let bytesPerPixel = 4
let bytesPerRow = rep.bytesPerRow
let data = rep.bitmapData!

for y in 0..<height {
    for x in 0..<width {
        let pixelIndex = (y * bytesPerRow) + (x * bytesPerPixel)
        let r = Int(data[pixelIndex])
        let g = Int(data[pixelIndex + 1])
        let b = Int(data[pixelIndex + 2])
        let a = Int(data[pixelIndex + 3])
        
        // Skip transparent pixels
        if a == 0 {
            continue
        }
        
        // Calculate luminance
        let luminance = (r * 299 + g * 587 + b * 114) / 1000
        
        // Apply threshold to create black shapes on transparent background
        // For template images: dark areas -> black, light areas -> transparent
        let threshold: Int = 180  // Higher threshold to keep more detail
        
        if luminance > threshold {
            // Light areas: make transparent
            data[pixelIndex + 3] = 0  // Set alpha to 0
        } else {
            // Dark areas: make black
            data[pixelIndex] = 0       // R
            data[pixelIndex + 1] = 0   // G
            data[pixelIndex + 2] = 0   // B
            // Keep alpha as is (should be opaque for dark areas)
            if a < 255 {
                data[pixelIndex + 3] = 255  // Make sure dark areas are opaque
            }
        }
    }
}

// Create NSImage from the bitmap representation
let finalImage = NSImage(size: targetSize)
finalImage.addRepresentation(rep)
finalImage.isTemplate = true

// Save as PNG
guard let pngData = rep.representation(using: .png, properties: [:]) else {
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
