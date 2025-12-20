# Menu Bar Icon Guide

## Requirements

For macOS menu bar icons, you need a **template image** that is:
- **Monochrome** (black shapes on transparent background)
- **Template format** (macOS will automatically tint it for light/dark mode)
- **Size**: 18x18 or 22x22 points (@2x = 36x36 or 44x44 pixels for Retina)

## Supported Formats

1. **PDF** (recommended - vector, scales perfectly)
   - File name: `MenuBarIcon.pdf`
   - Black shapes on transparent background
   - Size: 18x18 points

2. **PNG** (raster, needs @2x for Retina)
   - File name: `MenuBarIcon.png` or `menu-bar-icon.png`
   - Size: 36x36 pixels (18x18@2x) or 44x44 pixels (22x22@2x)
   - Black shapes on transparent background

## How to Create

### Option 1: Using Design Tools
1. Create a new document: 18x18 points (or 36x36 pixels for PNG)
2. Design your icon in **black only** (no colors)
3. Use transparent background
4. Export as:
   - **PDF** (vector) - best quality
   - **PNG** at 2x resolution (36x36 or 44x44 pixels)

### Option 2: Convert from SVG
If you have an SVG:
```bash
# Convert SVG to PDF (using Inkscape or online converter)
# Or use macOS Preview: Open SVG → Export as PDF
```

### Option 3: Use SF Symbols
The app currently falls back to SF Symbol `play.rectangle.fill` if no custom icon is found.

## Testing

Place your icon file in `Assets/Icons/` as:
- `MenuBarIcon.pdf` (preferred)
- `MenuBarIcon.png` (alternative)
- `menu-bar-icon.png` (alternative)

The app will automatically detect and use it.

## Design Tips

- Keep it simple - menu bar icons are small
- Use bold, clear shapes
- Avoid fine details
- Test in both light and dark mode
- The icon will be automatically tinted by macOS
