# Mac Live Wallpaper

A macOS menu bar app that lets you set YouTube videos as your desktop wallpaper, playing in a loop.

![macOS](https://img.shields.io/badge/macOS-13.0+-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/License-MIT-green)

## Features

- Set any YouTube video as your desktop wallpaper
- Videos play in a seamless loop
- Sits behind desktop icons (true wallpaper replacement)
- Menu bar app - doesn't clutter your dock
- Mute/unmute audio
- Downloaded videos are cached for quick access
- Works on all spaces

## Requirements

- macOS 13.0 (Ventura) or later
- [yt-dlp](https://github.com/yt-dlp/yt-dlp) for downloading YouTube videos

## Installation

### Install yt-dlp

```bash
brew install yt-dlp
```

Or see other installation methods at [yt-dlp GitHub](https://github.com/yt-dlp/yt-dlp#installation).

### Build from Source

```bash
git clone https://github.com/yourusername/mac-live-wallpaper.git
cd mac-live-wallpaper
swift build -c release
```

The built app will be at `.build/release/MacLiveWallpaper`.

### Run

```bash
swift run
```

Or after building:

```bash
.build/release/MacLiveWallpaper
```

## Usage

1. Click the menu bar icon (▶️ rectangle)
2. Paste a YouTube URL
3. Click "Set"
4. Wait for the video to download
5. Enjoy your live wallpaper!

### Controls

- **Mute/Unmute**: Toggle audio playback
- **Stop**: Remove the video wallpaper and restore normal desktop

## How It Works

The app creates a borderless window at the desktop window level, which sits behind your icons but in front of your normal wallpaper. Videos are downloaded using `yt-dlp` and played using AVPlayer with seamless looping.

Downloaded videos are cached in `~/Library/Application Support/MacLiveWallpaper/Videos/` so the same video won't need to be downloaded again.

## Building as a .app Bundle

To create a proper macOS app bundle, you can use Xcode:

1. Open Xcode and create a new macOS App project
2. Copy the source files from `Sources/` into your project
3. Build and archive for distribution

## Known Limitations

- Only works with the main display (multi-monitor support coming soon)
- High-resolution videos may use significant CPU/GPU resources
- Some YouTube videos may be geo-restricted or age-restricted

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) file for details.

## Credits

- [yt-dlp](https://github.com/yt-dlp/yt-dlp) for video downloading
- Inspired by [Plash](https://github.com/sindresorhus/Plash) for the desktop window technique
