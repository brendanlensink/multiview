# Agents

Notes for AI agents working on this project.

## Platform & Build

- **iOS only** (iPhone/iPad), SwiftUI frontend, no macOS target
- No external dependencies — pure Apple frameworks
- Uses `PBXFileSystemSynchronizedRootGroup`, so Xcode auto-discovers files in `MultiView/`. No `pbxproj` changes needed when adding or removing source files.

## Source Layout

All source lives under `MultiView/MultiView/`:

| File | Role |
|------|------|
| `ContentView.swift` | Root view, role selection (Director vs Camera) |
| `DirectorView.swift` | Director UI — displays grid of all camera feeds |
| `CameraView.swift` | Camera participant UI — streams video to director |
| `CameraPreviewView.swift` | Local camera preview |
| `SampleBufferVideoView.swift` | Wraps `AVSampleBufferDisplayLayer` for rendering decoded frames |
| `ConnectivityManager.swift` | MultipeerConnectivity session, advertising, browsing, send/receive |
| `CaptureManager.swift` | `AVCaptureSession` setup, raw `CMSampleBuffer` output |
| `VideoEncoder.swift` | H.264 hardware encoding via `VTCompressionSession` |
| `VideoDecoder.swift` | Decodes H.264 NALUs back to `CMSampleBuffer` |
| `FrameSender.swift` | Queues and rate-limits encoded frames, drops non-keyframes on congestion |
| `FramePacket.swift` | Data model for encoded frame packets |
| `PeerVideoManager.swift` | Owns one `VideoDecoder` per connected peer, manages decoded output |
| `TimeSyncManager.swift` | NTP-like ping/pong time sync across peers (30s refresh, 5-sample average) |
| `PermissionManager.swift` | Camera/mic permission requests |

## Video Pipeline

**Camera device (sender):**
```
AVCaptureSession (720p)
  → AVCaptureVideoDataOutput
    → CaptureManager.onRawSampleBuffer
      → VideoEncoder (VTCompressionSession, H.264 Main, 2 Mbps)
        → FrameSender (rate-limited, drops non-keyframes on congestion)
          → ConnectivityManager.sendFrame()
            → MCSession.send()
```

**Director device (receiver):**
```
MCSession.didReceive()
  → ConnectivityManager.onFrameReceived
    → TimeSyncManager (adjusts PTS via RTT-based offset)
      → PeerVideoManager.handleFrame()
        → VideoDecoder → CMSampleBuffer
          → AVSampleBufferDisplayLayer.enqueue()
```

## Roles

- **Director**: advertises via `MCNearbyServiceAdvertiser`, accepts connections, runs local capture, displays all feeds in a grid (own camera at position 0, peers at 1..N). Sets `isDirector = true`.
- **Camera**: browses via `MCNearbyServiceBrowser`, invites director, streams encoded video, shows local preview only.

## Key Integration Points

- `VideoDecoder.onSampleBuffer` — callback with decoded `CMSampleBuffer` per peer, used for display. Tap here to access decoded frames without affecting the render path.
- `CaptureManager.onRawSampleBuffer` — raw camera output on the director's own device.
- `ConnectivityManager` peer connect/disconnect callbacks — use for reacting to topology changes.
- `TimeSyncManager` — provides clock offset per peer so presentation timestamps can be aligned across streams.
- `Info.plist` already declares Camera, Microphone, Local Network, and Bonjour permissions.
