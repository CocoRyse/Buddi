enum BuddyTask: String, CaseIterable {
    case idle
    case working
    case reading
    case sleeping
    case compacting
    case waiting
    case error
    case success
    case panic
    case nervous
    case celebrate

    var faceSuffix: String {
        switch self {
        case .idle: ""
        case .working: "..."
        case .reading: "..."
        case .sleeping: " zzz"
        case .compacting: "~"
        case .waiting: "?"
        case .error: "!"
        case .success: "✓"
        case .panic: "!!"
        case .nervous: "…"
        case .celebrate: " ✓"
        }
    }
}
