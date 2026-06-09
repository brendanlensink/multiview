import MultipeerConnectivity
import SwiftUI

enum FeedID: Hashable {
    case director
    case peer(MCPeerID)
}

@Observable
final class FeedLayoutManager {
    struct Frame: Equatable {
        var center: CGPoint
        var size: CGSize

        var rect: CGRect {
            CGRect(
                x: center.x - size.width / 2,
                y: center.y - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    private(set) var frames: [FeedID: Frame] = [:]
    private(set) var activeFeedID: FeedID?
    private(set) var containerSize: CGSize = .zero

    private let minimumSide: CGFloat = 120

    func recalculateGrid(feeds: [FeedID], in size: CGSize) {
        containerSize = size
        guard !feeds.isEmpty, size.width > 0, size.height > 0 else {
            frames = [:]
            return
        }

        let count = feeds.count
        let columns: Int
        let rows: Int
        switch count {
        case 1:
            columns = 1; rows = 1
        case 2:
            if size.width > size.height { columns = 2; rows = 1 }
            else { columns = 1; rows = 2 }
        default:
            columns = 2; rows = (count + 1) / 2
        }

        let cellW = size.width / CGFloat(columns)
        let cellH = size.height / CGFloat(rows)
        var newFrames: [FeedID: Frame] = [:]
        for (i, id) in feeds.enumerated() {
            let col = i % columns
            let row = i / columns
            newFrames[id] = Frame(
                center: CGPoint(x: CGFloat(col) * cellW + cellW / 2, y: CGFloat(row) * cellH + cellH / 2),
                size: CGSize(width: cellW, height: cellH)
            )
        }
        frames = newFrames
    }

    func setFeedCenter(_ id: FeedID, _ center: CGPoint) {
        guard var frame = frames[id] else { return }
        activeFeedID = id
        frame.center = center
        frames[id] = clamped(frame)
        resolveOverlaps(around: id)
    }

    func setFeedSize(_ id: FeedID, _ size: CGSize) {
        guard var frame = frames[id] else { return }
        activeFeedID = id
        frame.size = CGSize(
            width: max(minimumSide, min(size.width, containerSize.width)),
            height: max(minimumSide, min(size.height, containerSize.height))
        )
        frames[id] = clamped(frame)
        resolveOverlaps(around: id)
    }

    func endGesture() {
        activeFeedID = nil
    }

    // MARK: - Private

    private func clamped(_ frame: Frame) -> Frame {
        var f = frame
        let halfW = f.size.width / 2
        let halfH = f.size.height / 2
        f.center.x = max(halfW, min(containerSize.width - halfW, f.center.x))
        f.center.y = max(halfH, min(containerSize.height - halfH, f.center.y))
        return f
    }

    private func resolveOverlaps(around activeID: FeedID) {
        for _ in 0..<10 {
            var moved = false

            guard let activeRect = frames[activeID]?.rect else { return }
            for id in frames.keys where id != activeID {
                guard var frame = frames[id] else { continue }
                if let push = pushVector(from: activeRect, to: frame.rect) {
                    frame.center.x += push.x
                    frame.center.y += push.y
                    frames[id] = clamped(frame)
                    moved = true
                }
            }

            let others = Array(frames.keys.filter { $0 != activeID })
            for i in 0..<others.count {
                for j in (i + 1)..<others.count {
                    guard var a = frames[others[i]], var b = frames[others[j]] else { continue }
                    if let push = pushVector(from: a.rect, to: b.rect) {
                        a.center.x -= push.x / 2
                        a.center.y -= push.y / 2
                        b.center.x += push.x / 2
                        b.center.y += push.y / 2
                        frames[others[i]] = clamped(a)
                        frames[others[j]] = clamped(b)
                        moved = true
                    }
                }
            }

            if !moved { break }
        }
    }

    private func pushVector(from a: CGRect, to b: CGRect) -> CGPoint? {
        let intersection = a.intersection(b)
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else { return nil }
        if intersection.width <= intersection.height {
            return CGPoint(x: intersection.width * (b.midX >= a.midX ? 1 : -1), y: 0)
        } else {
            return CGPoint(x: 0, y: intersection.height * (b.midY >= a.midY ? 1 : -1))
        }
    }
}
