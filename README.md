# Live Engine

[![macOS](https://img.shields.io/badge/macOS-13.0+-007AFF?style=flat&logo=apple&logoColor=white)](https://www.apple.com/macos)
[![Swift](https://img.shields.io/badge/Swift-5.9-FA7343?style=flat&logo=swift&logoColor=white)](https://swift.org)
[![License](https://img.shields.io/badge/License-MIT-green?style=flat)](LICENSE)

**Live Engine** is a macOS menu bar app that lets you set video files as your desktop wallpaper,  
playing in a seamless loop. Built with Swift, featuring a clean native macOS interface.

---

## Features

- Set any local video file as your desktop wallpaper
- Videos play in a seamless loop
- Sits behind desktop icons (true wallpaper replacement)
- Menu bar app – doesn't clutter your dock
- Mute/unmute audio controls
- Videos are stored locally for quick access
- Works on all spaces

---

## Installation

### Build from Source

```bash
git clone https://github.com/luka-loehr/live-engine.git
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

### Build as .app Bundle

Use the provided script:

```bash
./Scripts/package.sh
```

---

## Usage

1. Click the menu bar icon (▶️ rectangle)
2. Click "Add New" to select a video file
3. Click on a video to set it as wallpaper
4. Enjoy your live wallpaper!

### Controls

- **Mute/Unmute**: Toggle audio playback
- **Click video**: Toggle wallpaper on/off
- **Delete**: Hover over a video and click the X button to remove it

---

## Requirements

- macOS 13.0 (Ventura) or later

---

## Known Limitations

- Only works with the main display (multi-monitor support coming soon)
- High-resolution videos may use significant CPU/GPU resources

---

## License

[MIT License](LICENSE)

---

## Support

- [Report bugs](https://github.com/luka-loehr/live-engine/issues)  
- Questions: [contact@lukaloehr.de](mailto:contact@lukaloehr.de)

---

Developed by [Luka Löhr](https://github.com/luka-loehr)  
Inspired by [Plash](https://github.com/sindresorhus/Plash) for the desktop window technique.
