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
- **Camera:** A device that captures video and streams it to the director.

## UX Principles

- **Simplicity first:** The app should be dead simple — minimal screens, minimal configuration. A user should go from launch to recording in seconds, not minutes.
- **Immediate role selection:** On launch, the user picks "Director" or "Camera." That's it — no accounts, no setup wizards.
- **Automatic connection:** Camera devices should appear on the director automatically. One tap to connect, no manual IP entry or pairing codes.
- **Always-visible grid:** The director displays all connected camera feeds in a live grid at all times. No switching between views or navigating tabs.

## Capture

- All recording is initiated and stored on the director device.
- The director can start/stop recording for all connected cameras simultaneously with a single action.
- Each camera stream is saved as a separate file with synchronized timestamps, ready for multi-angle editing.
- Camera devices stream only — they don't need to manage recordings or storage.

## Constraints

- iOS only (leveraging Apple frameworks: Multipeer Connectivity, AVFoundation, VideoToolbox)
- Practical limit of ~3–4 simultaneous camera streams due to bandwidth
- Hardware H.264/HEVC encoding to keep streams manageable
- No internet connection required — fully local/peer-to-peer
