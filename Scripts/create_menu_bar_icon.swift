#!/usr/bin/env swift

import AppKit
import Foundation

// Target size: 36x36 pixels (18x18 points @2x for Retina)
let size: CGFloat = 36
let outputPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "Assets/Icons/MenuBarIcon.png"

// Create bitmap representation
let rep = NSBitmapImageRep(bitmapDataPlanes: nil,
                          pixelsWide: Int(size),
                          pixelsHigh: Int(size),
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

// Clear with transparent background
NSColor.clear.set()
NSRect(x: 0, y: 0, width: size, height: size).fill()

// Draw a simple, clean icon: Play button inside a rounded rectangle frame
// This represents video/wallpaper

let padding: CGFloat = 6
let frameRect = NSRect(x: padding, y: padding, width: size - padding * 2, height: size - padding * 2)
let cornerRadius: CGFloat = 4

// Draw rounded rectangle frame (thin border)
let framePath = NSBezierPath(roundedRect: frameRect, xRadius: cornerRadius, yRadius: cornerRadius)
NSColor.black.set()
framePath.lineWidth = 1.5
framePath.stroke()

// Draw play triangle inside
let playSize: CGFloat = 10
let playX = size / 2 - playSize / 2 + 1 // Slight offset to center visually
let playY = size / 2 - playSize / 2

let playPath = NSBezierPath()
playPath.move(to: NSPoint(x: playX, y: playY))
playPath.line(to: NSPoint(x: playX + playSize, y: playY + playSize / 2))
playPath.line(to: NSPoint(x: playX, y: playY + playSize))
playPath.close()
NSColor.black.set()
playPath.fill()

NSGraphicsContext.restoreGraphicsState()

// Create NSImage
let image = NSImage(size: NSSize(width: 18, height: 18))
image.addRepresentation(rep)
image.isTemplate = true

// Save as PNG
guard let pngData = rep.representation(using: .png, properties: [:]) else {
    print("Error: Could not convert to PNG")
    exit(1)
}

do {
    try pngData.write(to: URL(fileURLWithPath: outputPath))
    print("Successfully created menu bar icon: \(outputPath)")
    print("Size: \(Int(size))x\(Int(size)) pixels (18x18 points @2x)")
} catch {
    print("Error: Could not save image: \(error)")
    exit(1)
}
