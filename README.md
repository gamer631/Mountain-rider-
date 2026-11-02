# Mountain Rider

An original, offline, 2D cartoon mountain-driving game built with **Godot 4**. It is inspired by the hill-driving genre, but uses original code and procedural artwork rather than copied game assets.

## Features

- Side-scrolling rolling hills with layered parallax scenery
- Acceleration, reverse/brake, gravity, airborne rotation and slope-following suspension feel
- Four vehicles with different power, grip, speed and prices
- Collectible coins and fuel cans
- Persistent wallet, unlocked vehicles, selected vehicle and best distance
- Touch controls for Android; keyboard controls for desktop
- No network calls or online dependency

## Run on desktop

1. Install Godot 4.3 or later.
2. Import `project.godot` in Godot.
3. Press **F6** or **F5** to run.

Controls: Right/D to accelerate, Left/A to brake/reverse. On mobile, use the on-screen pedals.

## Build an Android APK

The Android export preset and GitHub Actions workflow are included. Pushes to `main` attempt to build a debug APK. Check the Actions tab for the build result and download the `Mountain-Rider-Android-APK` artifact if the workflow succeeds. The APK is a debug build, not a Play Store release.

## Project structure

```text
Mountain_Rider/
├── project.godot
├── main.tscn
├── scripts/game.gd
├── export_presets.cfg
└── .github/workflows/android-apk.yml
```

## License

MIT. See `LICENSE`.
