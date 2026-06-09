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
| `RecordingManager.swift` | Orchestrates multi-stream recording — creates `StreamRecorder` per stream, writes session metadata |
| `StreamRecorder.swift` | Wraps `AVAssetWriter` for a single video/audio stream, writes `.mov` files |
| `RecordingSession.swift` | Codable metadata model for a completed recording (streams, timestamps, duration) |
| `RecordingStore.swift` | Manages recording temp directory — lists completed sessions, cleans up orphaned recordings |
| `PhotosExporter.swift` | Exports recording sessions to the Photos library via `PHPhotoLibrary`, cleans up temp files on success |
| `GridCompositor.swift` | Composites multiple angle recordings into a single split-screen video via `AVMutableComposition` + `AVVideoComposition` |
| `ExportOptionsSheet.swift` | Post-recording export UI — choose between separate files or grid composite export |

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

## Recording & File Management

Recording is director-only. `RecordingManager` creates one `StreamRecorder` (AVAssetWriter) per stream — the director's local camera + one per connected peer.

**File structure:**
```
tmp/recordings/<session-uuid>/
  .recording              ← in-progress marker, removed on completion
  session.json            ← RecordingSession metadata (written on stop)
  <director-name>.mov     ← local camera + audio
  <peer-name>.mov         ← one per connected peer (video only)
```

**Lifecycle:**
1. Start → create session dir, write `.recording` marker, start `StreamRecorder`s
2. Stop → finalize all writers, write `session.json`, remove `.recording` marker
3. App launch → `RecordingStore.cleanupIncompleteRecordings()` deletes dirs with a `.recording` marker or missing `session.json`
4. Export → user chooses export mode in `ExportOptionsSheet`:
   - **Separate files** → `PhotosExporter.exportSession()` saves each `.mov` to Photos
   - **Grid composite** → `GridCompositor.composite()` merges all angles into a single split-screen `.mov` via `AVMutableComposition` + `AVVideoComposition`, then `PhotosExporter.saveVideoToPhotos()` saves it

**Export integration:** `RecordingStore.completedSessions()` returns `[RecordingSession]` sorted newest-first. Each session has stream metadata and file references. Use `RecordingStore.fileURL(for:in:)` to resolve `.mov` paths. After recording stops, `DirectorView` presents `ExportOptionsSheet` for the user to choose an export mode.

**Grid composite layout:** `GridCompositor` arranges angles in a 1920x1080 output — 1 angle = full screen, 2 = side-by-side, 3–4 = 2×2 grid (black fill for empty cell). Audio comes from the director's stream only. Each angle is aspect-fit into its grid cell with the source `preferredTransform` applied.

## Key Integration Points

- `VideoDecoder.onSampleBuffer` — callback with decoded `CMSampleBuffer` per peer, used for display. Tap here to access decoded frames without affecting the render path.
- `CaptureManager.onRawSampleBuffer` — raw camera output on the director's own device.
- `ConnectivityManager` peer connect/disconnect callbacks — use for reacting to topology changes.
- `TimeSyncManager` — provides clock offset per peer so presentation timestamps can be aligned across streams.
- `Info.plist` declares Camera, Microphone, Local Network, Bonjour, and Photo Library Add permissions.
