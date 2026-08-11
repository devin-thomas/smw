# iPhone and iPad

SMW includes a native iOS and iPadOS shell for self-built installs on iOS 16 or later. The app runs the reverse-engineered C game core locally through SDL's Metal-backed renderer. It does not contain or download a ROM.

## Features

- Landscape layouts for iPhone and iPad, including safe-area handling.
- Sliding and diagonal D-pad input, equal circular A/B/X/Y buttons, L/R, Start, and Select.
- Physical-controller support with optional automatic hiding of gameplay touch controls.
- A game menu with quick save, quick load, reset, quit, opacity, and control-size settings.
- Native audio-session handling that mixes with other audio and resumes cleanly after backgrounding.
- Crisp nearest-neighbor output on an integer physical-pixel grid.

## Requirements

- A Mac with Xcode and the iOS SDK.
- CMake 3.25 or later and Git.
- An iPhone or iPad running iOS 16 or later, or an Apple Silicon iOS Simulator.
- A legally owned US Super Mario World ROM named `smw.sfc`.
- An Apple development team for installation on a physical device.

The repository ignores `smw.sfc`, `smw_assets.dat`, generated Xcode projects, and build products. Do not add those local files to a commit.

## Prepare the assets

From the repository root, place `smw.sfc` beside `README.md`, then run:

```sh
python3 assets/restool.py
```

This creates `smw_assets.dat`. The iOS build copies that generated file and `smw.ini` into the app bundle. On first launch, the app copies both files into its Documents directory, where save data also persists. Rebuilding or updating the app does not overwrite those existing Documents copies; deleting the app removes its local data.

## Build for the Simulator

```sh
cmake -S . -B build-ios-sim -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0
open build-ios-sim/SMWIOS.xcodeproj
```

Select the `SuperMarioWorld` scheme, choose a landscape iPhone or iPad Simulator, and run.

## Build for a device

```sh
cmake -S . -B build-ios-device -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0
open build-ios-device/SMWIOS.xcodeproj
```

In Xcode:

1. Select the `SuperMarioWorld` target.
2. Choose your Apple development team under Signing and Capabilities.
3. Replace `com.local.smw.ios` with a bundle identifier unique to your account.
4. Connect and trust the device, enable Developer Mode if prompted, then run the app.

Development-signed apps remain subject to the provisioning profile's expiration date. Rebuild and reinstall when the profile expires.

## Touch controls

- Slide across the D-pad to change direction without lifting your thumb. Its diagonal zones press two directions together.
- The face buttons use a compact SNES-style diamond. Their active regions are circular, preventing overlapping corner taps.
- L and R sit at the top corners; Select and Start sit directly below them.
- Every press uses light haptic feedback on supported devices.
- Opening the menu, backgrounding the app, or connecting a controller releases all held touch inputs.

Touch-control preferences are stored on the device and do not modify `smw.ini`.

## Game menu

Tap the `...` button at the top center to open the menu:

- **Save** writes quick-save slot 0 immediately.
- **Load** restores quick-save slot 0 after an inline confirmation.
- **Reset** restarts the game after confirmation.
- **Quit** closes the running game after confirmation.
- **Opacity** ranges from 0% to 100% and updates the controls live.
- **Control size** ranges from 80% to 125%.
- **Always** keeps gameplay controls visible when a physical controller is connected.
- **Auto-hide** hides gameplay controls while a physical controller is connected. The `...` menu remains available.

Load presents the restored frame immediately. It does not require an orientation change, unpausing, or another game frame before the screen updates.

## Video and audio behavior

iOS always uses the original 256x224 game viewport. The renderer opts into the screen's native backing scale, applies nearest-neighbor sampling, and chooses the largest integer scale that fits. Black side margins are intentional: stretching the image to fill the display would create uneven physical pixel sizes and visible shimmer in motion.

The SNES DSP produces 534 stereo samples for each 60 Hz game frame, or 32,040 samples per second. The app negotiates the device rate and carries fractional output-frame remainders so playback maintains the intended pitch and speed. Its ambient audio session can mix with other apps and is deactivated while SMW is in the background.

## Troubleshooting

- **The app reports missing assets:** regenerate `smw_assets.dat`, reconfigure CMake, and rebuild so the file is copied into the bundle.
- **The device build will not sign:** select a development team and use a bundle identifier owned by that team.
- **The app stopped opening after several days:** rebuild and reinstall with a current development provisioning profile.
- **Touch controls disappear:** open the `...` menu and change Touch controls from Auto-hide to Always, or disconnect the physical controller.
- **A save seems old after replacing assets:** save data and the first copied assets live in the app's Documents directory. Delete the app only if you intentionally want to clear all local data.

Implementation details and regression procedures live in [IOS_DEVELOPMENT.md](IOS_DEVELOPMENT.md).
