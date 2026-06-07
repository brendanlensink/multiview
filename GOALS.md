# MultiView — Project Goals

## Vision

An iOS app that lets users connect multiple iPhones to capture video from several angles simultaneously, controlled from a single "director" device.

## Core Goals

- **Multi-device connectivity:** Connect multiple iPhones over a local network using Multipeer Connectivity, with no server infrastructure required.
- **Real-time video streaming:** Stream live camera feeds from each connected device to the director with low latency.
- **Multi-angle display:** Show all connected camera feeds on the director device in a responsive grid layout.
- **Synchronized recording:** Record all streams simultaneously with synchronized timestamps so footage can be edited together in post.

## Roles

- **Director:** The device that discovers and connects to cameras, displays all feeds, and controls recording.
- **Camera:** A device that captures video and streams it to the director. Shows a live preview so the user can frame their shot.

## UX Principles

- **Simplicity first:** The app should be dead simple — minimal screens, minimal configuration. A user should go from launch to recording in seconds, not minutes.
- **Immediate role selection:** On launch, the user picks "Director" or "Camera." That's it — no accounts, no setup wizards.
- **Automatic connection:** Camera devices should appear on the director automatically. One tap to connect, no manual IP entry or pairing codes.
- **Always-visible grid:** The director displays all connected camera feeds in a live grid at all times. No switching between views or navigating tabs.

## Capture & Export

- All recording is initiated and stored on the director device.
- The director can start/stop recording for all connected cameras simultaneously with a single action.
- Audio is captured from the director device's microphone only.
- On export, the user chooses between:
  - **Grid composite:** A single video with all angles arranged in a split-screen layout.
  - **Separate files:** Individual video files per angle with synchronized timestamps, ready for multi-angle editing.
- Recordings are saved to the camera roll.

## Constraints

- iOS only, built with SwiftUI (leveraging Apple frameworks: Multipeer Connectivity, AVFoundation, VideoToolbox)
- Practical limit of ~3–4 simultaneous camera streams due to bandwidth
- Hardware H.264/HEVC encoding to keep streams manageable
- No internet connection required — fully local/peer-to-peer
