# Live Engine

A macOS menu bar app that lets you set video files as your desktop wallpaper, playing in a loop.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- Set any local video file as your desktop wallpaper
- Videos play in a seamless loop
- Sits behind desktop icons (true wallpaper replacement)
- Menu bar app - doesn't clutter your dock
- Mute/unmute audio
- Videos are stored locally for quick access
- Works on all spaces

## Requirements

- macOS 13.0 (Ventura) or later

## Installation

### Build from Source

```bash
git clone https://github.com/yourusername/live-engine.git
cd live-engine
swift build -c release
```

The built app will be at `.build/release/LiveEngine`.

### Run

```bash
swift run
```

Or after building:

```bash
.build/release/LiveEngine
```

## Usage

1. Click the menu bar icon (▶️ rectangle)
2. Click "Add New" to select a video file
3. Click on a video to set it as wallpaper
4. Enjoy your live wallpaper!

### Controls

- **Mute/Unmute**: Toggle audio playback
- **Click video**: Toggle wallpaper on/off
- **Delete**: Hover over a video and click the X button to remove it

## How It Works

The app creates a borderless window at the desktop window level, which sits behind your icons but in front of your normal wallpaper. Videos are played using AVPlayer with seamless looping.

Videos are stored in `~/Library/Application Support/LiveEngine/Videos/` so they persist between app launches.

## Building as a .app Bundle

To create a proper macOS app bundle, you can use Xcode:

1. Open Xcode and create a new macOS App project
2. Copy the source files from `Sources/` into your project
3. Build and archive for distribution

Or use the provided script:

```bash
./Scripts/package.sh
```

## Known Limitations

- Only works with the main display (multi-monitor support coming soon)
- High-resolution videos may use significant CPU/GPU resources

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

- Inspired by [Plash](https://github.com/sindresorhus/Plash) for the desktop window technique
