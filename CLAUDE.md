# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

MiniCap is a tiny macOS 15+ menu-bar screen recorder (Swift Package, single executable target, no dependencies, no tests). It runs as an `LSUIElement` agent app (no Dock icon) and saves HEVC `.mp4` files to `~/Movies/MiniCap/`.

## Commands

```bash
./build.sh                      # release build → build/MiniCap.app (stripped, ad-hoc signed)
swift build                     # debug compile check only
open build/MiniCap.app          # run
```

Run the `.app` bundle, not the raw `.build/` binary: screen-capture and microphone permission prompts depend on the bundle's `Info.plist` (`NSScreenCaptureUsageDescription`, `NSMicrophoneUsageDescription`). `Info.plist` lives at the repo root and is copied into the bundle by `build.sh`; edit it there.

## Architecture

- `main.swift`: `AppDelegate` (`@MainActor`) owns the `NSStatusItem`, rebuilds the whole menu on every `refresh()`, persists `Recorder.Options` to `UserDefaults` (keys `fps`, `mic`, `sys`, `cursor`), and shows an elapsed-time label driven by a 1 s timer with 0.5 s tolerance (keep wakeups low). When a recording finishes it reveals the file in Finder.
- `Recorder.swift`: wraps ScreenCaptureKit with `SCRecordingOutput`, so the system captures, encodes and writes the file; frames never pass through this process. It records the display under the mouse, excludes MiniCap's own windows and audio, and reports completion or failure through the `onFinish` callback. That callback arrives on an arbitrary thread, and `AppDelegate` hops to main. `isRecording` is just `stream != nil`.
- `HotKey.swift`: global ⌥⌘R toggle via Carbon `RegisterEventHotKey`, chosen so the app doesn't need Accessibility permission.

## Conventions

- Swift 6 tools with Swift 5 language mode (`swiftLanguageModes: [.v5]`); built with `-Osize`. The project favors minimal size and low CPU, so avoid adding dependencies or per-frame work in-process.
- UI strings, comments and output filenames are in Spanish; keep new ones in Spanish.
