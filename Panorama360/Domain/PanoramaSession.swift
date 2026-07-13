import Foundation

/// A full panorama capture session: the target layout, captured photos, and
/// (eventually) the produced equirectangular image.
public struct PanoramaSession: Identifiable, Codable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public var distribution: SphereDistribution
    public var points: [CapturePoint]
    public var samples: [CaptureSample]
    public var equirectangularURL: URL?
    public var directoryURL: URL

    public init(id: UUID = UUID(),
                createdAt: Date = Date(),
                distribution: SphereDistribution,
                points: [CapturePoint] = [],
                samples: [CaptureSample] = [],
                equirectangularURL: URL? = nil,
                directoryURL: URL) {
        self.id = id
        self.createdAt = createdAt
        self.distribution = distribution
        self.points = points
        self.samples = samples
        self.equirectangularURL = equirectangularURL
        self.directoryURL = directoryURL
    }

    // MARK: - Progress

    public var capturedCount: Int { points.capturedCount }
    public var totalPoints: Int { points.count }
    public var fractionComplete: Double { points.fractionComplete }

    public var isCaptureComplete: Bool {
        !points.isEmpty && points.allSatisfy(\.isCaptured)
    }

    public var isStitched: Bool { equirectangularURL != nil }

    /// Records a captured photo against its target point.
    public mutating func record(sample: CaptureSample, forPointID pointID: UUID) {
        if let idx = points.firstIndex(where: { $0.id == pointID }) {
            points[idx].state = .captured
            points[idx].confidence = 1
            points[idx].revision += 1
        }
        samples.append(sample)
    }
}
