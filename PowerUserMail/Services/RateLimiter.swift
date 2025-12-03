import Foundation

/// Manages API rate limiting with exponential backoff, Retry-After support, and request queuing
actor RateLimiter {
    static let shared = RateLimiter()

    /// Per-account rate limit state
    private struct RateLimitState {
        var consecutiveFailures: Int = 0
        var retryAfter: Date? = nil
        var lastRequestTime: Date? = nil
        var isBackingOff: Bool = false
        var activeRequests: Int = 0
        var totalRequestsThisMinute: Int = 0
        var minuteStartTime: Date = Date()
    }

    private var states: [String: RateLimitState] = [:]  // keyed by email

    // Configuration - Gmail limits: 250 quota units/second, but threads.get costs 1 unit each
    // To be safe, limit to ~10 requests/second with burst allowance
    private let baseBackoffSeconds: Double = 30
    private let maxBackoffSeconds: Double = 300  // 5 minutes max
    private let minRequestInterval: Double = 0.1  // 100ms between individual requests
    private let maxConcurrentRequests: Int = 5  // Max parallel requests per account
    private let maxRequestsPerMinute: Int = 60  // Stay well under Gmail's limits
    private let requestStaggerDelay: Double = 0.2  // 200ms delay between queued requests

    private init() {}

    // MARK: - Public API

    /// Check if we should proceed with a request for this account
    /// Returns the number of seconds to wait, or 0 if ready
    func shouldWait(for email: String) async -> TimeInterval {
        var state = states[email] ?? RateLimitState()

        // Reset per-minute counter if a minute has passed
        if Date().timeIntervalSince(state.minuteStartTime) >= 60 {
            state.totalRequestsThisMinute = 0
            state.minuteStartTime = Date()
            states[email] = state
        }

        // Check Retry-After first (from 429 response)
        if let retryAfter = state.retryAfter, retryAfter > Date() {
            let waitTime = retryAfter.timeIntervalSinceNow
            return waitTime
        }

        // Check backoff from consecutive failures
        if state.isBackingOff && state.consecutiveFailures > 0 {
            let backoffTime = calculateBackoff(failures: state.consecutiveFailures)
            if let lastRequest = state.lastRequestTime {
                let elapsed = Date().timeIntervalSince(lastRequest)
                if elapsed < backoffTime {
                    return backoffTime - elapsed
                }
            }
        }

        // Check concurrent request limit
        if state.activeRequests >= maxConcurrentRequests {
            return requestStaggerDelay
        }

        // Check per-minute limit
        if state.totalRequestsThisMinute >= maxRequestsPerMinute {
            let timeUntilReset = 60 - Date().timeIntervalSince(state.minuteStartTime)
            if timeUntilReset > 0 {
                print(
                    "⏳ Rate limit: \(email) hit \(maxRequestsPerMinute)/min limit, waiting \(Int(timeUntilReset))s"
                )
                return timeUntilReset
            }
        }

        // Check minimum interval
        if let lastRequest = state.lastRequestTime {
            let elapsed = Date().timeIntervalSince(lastRequest)
            if elapsed < minRequestInterval {
                return minRequestInterval - elapsed
            }
        }

        return 0
    }

    /// Acquire a request slot - call before making a request
    /// Returns true if request can proceed, false if should wait
    func acquireSlot(for email: String) async -> Bool {
        var state = states[email] ?? RateLimitState()

        // Reset per-minute counter if needed
        if Date().timeIntervalSince(state.minuteStartTime) >= 60 {
            state.totalRequestsThisMinute = 0
            state.minuteStartTime = Date()
        }

        // Check if we can proceed
        if state.activeRequests >= maxConcurrentRequests {
            return false
        }

        if state.totalRequestsThisMinute >= maxRequestsPerMinute {
            return false
        }

        if let retryAfter = state.retryAfter, retryAfter > Date() {
            return false
        }

        // Acquire the slot
        state.activeRequests += 1
        state.totalRequestsThisMinute += 1
        state.lastRequestTime = Date()
        states[email] = state

        return true
    }

    /// Release a request slot - call when request completes (success or failure)
    func releaseSlot(for email: String) async {
        var state = states[email] ?? RateLimitState()
        state.activeRequests = max(0, state.activeRequests - 1)
        states[email] = state
    }

    /// Call this before making a request
    func willMakeRequest(for email: String) async {
        var state = states[email] ?? RateLimitState()
        state.lastRequestTime = Date()
        state.totalRequestsThisMinute += 1
        states[email] = state
    }

    /// Call this when a request succeeds
    func requestSucceeded(for email: String) async {
        var state = states[email] ?? RateLimitState()
        state.consecutiveFailures = 0
        state.isBackingOff = false
        state.retryAfter = nil
        states[email] = state
    }

    /// Call this when a request fails with rate limit (429)
    func requestRateLimited(for email: String, retryAfterSeconds: Double? = nil) async {
        var state = states[email] ?? RateLimitState()
        state.consecutiveFailures += 1
        state.isBackingOff = true

        if let retrySeconds = retryAfterSeconds {
            state.retryAfter = Date().addingTimeInterval(retrySeconds)
            print("🚫 Rate limit: \(email) got 429, retry after \(Int(retrySeconds))s")
        } else {
            // Use exponential backoff
            let backoff = calculateBackoff(failures: state.consecutiveFailures)
            state.retryAfter = Date().addingTimeInterval(backoff)
            print(
                "🚫 Rate limit: \(email) got 429, backing off \(Int(backoff))s (failure #\(state.consecutiveFailures))"
            )
        }

        states[email] = state
    }

    /// Call this when a request fails for other reasons
    func requestFailed(for email: String) async {
        var state = states[email] ?? RateLimitState()
        state.consecutiveFailures += 1
        state.isBackingOff = true
        states[email] = state
    }

    /// Reset rate limit state for an account (e.g., on re-authentication)
    func reset(for email: String) async {
        states[email] = RateLimitState()
        print("🔄 Rate limit: Reset state for \(email)")
    }

    /// Get current backoff time for display
    func currentBackoffTime(for email: String) async -> TimeInterval? {
        guard let state = states[email], let retryAfter = state.retryAfter else {
            return nil
        }
        let remaining = retryAfter.timeIntervalSinceNow
        return remaining > 0 ? remaining : nil
    }

    /// Get current stats for debugging
    func getStats(for email: String) async -> (active: Int, perMinute: Int, failures: Int) {
        let state = states[email] ?? RateLimitState()
        return (state.activeRequests, state.totalRequestsThisMinute, state.consecutiveFailures)
    }

    // MARK: - Private Helpers

    private func calculateBackoff(failures: Int) -> Double {
        // Exponential backoff: base * 2^(failures-1), capped at max
        let backoff = baseBackoffSeconds * pow(2.0, Double(failures - 1))
        return min(backoff, maxBackoffSeconds)
    }
}
