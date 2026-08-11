# iOS and iPadOS development notes

This document records the architectural constraints and regression procedures for the native Apple-mobile port. Read it before modifying rendering, UIKit integration, audio, lifecycle handling, save states, or touch geometry.

## Source map

- `CMakeLists.txt` defines the iOS application bundle, fetches static SDL 2.32.10, embeds resources, and links UIKit and AVFAudio.
- `ios/Info.plist.in` declares landscape-only, full-screen iPhone and iPad support with a minimum deployment target supplied by CMake.
- `ios/LaunchScreen.storyboard` provides the launch screen.
- `src/platform/ios/ios_impl.h` is the narrow C interface used by the portable game loop.
- `src/platform/ios/ios_impl.mm` owns UIKit controls, preferences, audio-session setup, controller visibility, and runtime-directory preparation.
- `src/main.c` remains the owner of emulator state, SDL events, rendering, audio production, and save/load execution.
- `scripts/verify_ios_render.py` measures the rendered viewport in a screenshot.
- `scripts/verify_ios_load_redraw.py` proves that quick-load restores state and presents the restored frame without a lifecycle event.

Keep platform behavior behind `__IOS__` or inside `src/platform/ios`. Desktop and Switch behavior must remain unchanged unless a cross-platform change is intentional and tested.

## UIKit and game-loop ownership

UIKit objects must be created and mutated on the main queue. The SDL/game loop consumes only atomic state exposed by the iOS bridge:

- `gTouchInput` is a level-triggered SNES input mask.
- `gPendingActions` is an edge-triggered bitset for save, load, reset, and quit.
- UIKit publishes actions with `fetch_or`; the game loop consumes them with `exchange(0)`.

Do not call emulator save/load/reset functions directly from a UIKit callback. Keeping those operations on the game thread prevents races with RAM, PPU, renderer, and audio state.

Whenever ownership changes, release all held touch bits. The current release points are menu opening, app backgrounding, touch cancellation, and physical-controller takeover. A stuck direction or face button after any of those transitions is a release-path regression.

## Pixel-perfect rendering invariant

The source framebuffer is 256x224. Every source pixel must map to an equal, integer-sized square in the display's physical pixel space.

The required SDL configuration is:

1. Add `SDL_WINDOW_ALLOW_HIGHDPI` before creating the window so the Metal drawable uses the screen's native backing scale.
2. Set the logical renderer size to 256x224.
3. Enable `SDL_RenderSetIntegerScale(renderer, SDL_TRUE)` on iOS.
4. Set both `SDL_HINT_RENDER_SCALE_QUALITY` and the streaming texture's scale mode to nearest-neighbor.
5. Accept letterboxing or pillarboxing when the display is not an integer multiple of the framebuffer.

Logical-point fitting alone is insufficient. On a 2622x1206 landscape capture, fitting the game to the full height produced a roughly 1379x1206 viewport, or 5.3867x5.3839 physical pixels per source pixel. That alternated source pixels across five and six display pixels, making the entire scene shimmer even though static screenshots looked approximately correct. The corrected viewport is 1280x1120, exactly 5x in both axes.

iOS forces the normal viewport, aspect preservation, and nearest filtering after parsing `smw.ini`. Do not allow desktop stretch, filtering, or experimental widescreen settings to bypass the mobile invariant without adding a separate integer-grid design and regression coverage.

## Save/load presentation invariant

Restoring emulator memory does not itself replace the pixels already stored in the SDL texture. If quick-load occurs while the game is paused or the next frame is delayed, the old texture remains visible. Rotation appeared to fix the issue only because the lifecycle/layout transition caused another presentation.

After `RtlSaveLoad(kSaveLoad_Load, 0)`, call `DrawPpuFrameWithPerf()` in the same game-loop action path. Never depend on orientation, unpausing, an SDL expose event, or the next emulated frame to reveal loaded state.

Load, reset, and quit confirmations stay inside the existing control panel. Avoid presenting a separate `UIAlertController`: a modal view-controller transition adds lifecycle and focus changes to an operation that only needs confirmation, and it can make controller-hiding behavior difficult to understand.

## Touch-control behavior

- Phone and iPad layouts are calculated separately and respect safe areas.
- A/B/X/Y have equal diameters and form a compact diamond. Their `pointInside` implementation is circular even when square UIButton frames touch or overlap at their corners.
- The D-pad calculates one continuous direction mask from the touch location, including diagonal zones. Moving a held touch updates the mask without requiring a lift.
- The overlay's `hitTest` passes touches outside actual controls through to SDL.
- The menu button is independent of gameplay-control visibility and must remain reachable in both Always and Auto-hide modes.
- Opacity has a true 0% minimum. Slider movement updates the overlay live, while `NSUserDefaults` writes occur only when the drag ends to avoid UI stalls.
- Opening the menu hides gameplay controls and releases inputs. Closing it restores visibility according to controller state.

When changing geometry, test at the minimum and maximum control-size settings on at least one notched iPhone and one iPad. Check simultaneous direction and face-button presses, sliding diagonals, safe-area clearance, and both landscape orientations.

## Audio cadence and lifecycle

The game produces 534 stereo samples per 60 Hz frame, which is 32,040 Hz. Do not calculate output using `534 * deviceRate / 32000`; that treats the source as 32 kHz and audibly slows playback.

For each output block, add the negotiated device sample rate to a remainder accumulator, divide by 60 for the next frame count, and retain the modulo-60 remainder. Allocate for `ceil(deviceRate / 60)` frames. This distributes non-integral block sizes without long-term pitch or timing drift.

The iOS audio session uses the ambient category with mixing enabled, requests 48 kHz and a short I/O buffer, and accepts the actual rate returned by SDL. Deactivate and pause audio on background entry; reactivate it on foreground entry unless the game is paused.

## Runtime files and persistence

`smw.ini` and `smw_assets.dat` are bundle resources. `IosImpl_PrepareRuntime` copies each into the app's Documents directory only when absent, then changes the working directory there. This gives the portable core writable paths for saves and preferences while preserving data across ordinary app updates.

Consequences:

- A newly bundled `smw.ini` or `smw_assets.dat` does not replace an existing Documents copy.
- Deleting the app deletes save data and copied runtime files.
- Tests that require a fresh runtime must uninstall the app or explicitly remove only the intended simulator container.
- ROMs, generated assets, save data, provisioning profiles, and build directories must never be committed.

## Configure and build

Simulator:

```sh
cmake -S . -B build-ios-sim -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphonesimulator \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0
xcodebuild -project build-ios-sim/SMWIOS.xcodeproj \
  -scheme SuperMarioWorld -configuration Debug \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build
```

Device:

```sh
cmake -S . -B build-ios-device -G Xcode \
  -DCMAKE_SYSTEM_NAME=iOS \
  -DCMAKE_OSX_SYSROOT=iphoneos \
  -DCMAKE_OSX_ARCHITECTURES=arm64 \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=16.0
xcodebuild -project build-ios-device/SMWIOS.xcodeproj \
  -scheme SuperMarioWorld -configuration Debug \
  -destination 'id=<core-device-id>' \
  DEVELOPMENT_TEAM=<team-id> CODE_SIGN_STYLE=Automatic \
  PRODUCT_BUNDLE_IDENTIFIER=<unique-bundle-id> build
```

Use `xcrun devicectl list devices` to obtain the CoreDevice identifier. Development signing is temporary; inspect the embedded provisioning profile's expiration when handing off a long-running test build.

## Regression checks

The image scripts require Pillow. A local install or an ephemeral `uv` environment is sufficient:

```sh
uv run --with pillow python scripts/verify_ios_render.py \
  --image /absolute/path/to/device-or-simulator-screenshot.png
```

A passing device result for the 256x224 framebuffer reports equal integer scales, for example:

```text
viewport=1280x1120@(671,43) scale=5.0000x5.0000 distortion=0.00%
PASS: framebuffer uses a consistent 5x physical-pixel grid
```

The quick-load test needs a running debug Simulator build and LLDB attach permission:

```sh
uv run --with pillow python scripts/verify_ios_load_redraw.py \
  --simulator <simulator-udid> \
  --bundle-id com.local.smw.ios
```

It pauses the game, saves a sentinel value, corrupts both RAM and the visible SDL texture, invokes the real menu load path, and compares the resulting screenshot with the saved frame. A pass requires restored RAM, zero stale-magenta coverage, and a near-zero frame difference without rotating the simulator.

Capture a physical-device screenshot with:

```sh
xcrun devicectl device capture screenshot \
  --device <core-device-id> \
  --destination /tmp/smw-device.png
```

## Pre-handoff checklist

1. Run the desktop build to catch cross-platform compilation regressions.
2. Build and launch the Debug simulator target.
3. Run both rendering and quick-load regressions.
4. Build, sign, install, and launch on a physical iPhone or iPad.
5. Run the pixel-grid check against a physical-device screenshot.
6. Test audio speed, interruptions, background/foreground transitions, and silent-mode behavior.
7. Test touch size and opacity extremes, simultaneous inputs, menu confirmations, controller connect/disconnect, and both landscape orientations.
8. Save and load repeatedly at different gameplay moments without rotating the device.
9. Verify the provisioning-profile expiration and record any remaining device-specific risks.
