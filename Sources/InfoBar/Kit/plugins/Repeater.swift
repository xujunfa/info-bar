import Foundation

public final class Repeater {
    private let timer: DispatchSourceTimer
    private var isRunning = false

    public init(seconds: Int, block: @escaping () -> Void) {
        timer = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "io.infobar.repeater"))
        timer.schedule(deadline: .now() + .seconds(seconds), repeating: .seconds(seconds))
        timer.setEventHandler(handler: block)
    }

    deinit {
        timer.setEventHandler {}
        timer.cancel()
    }

    public func start() {
        guard !isRunning else { return }
        isRunning = true
        timer.resume()
    }

    public func pause() {
        guard isRunning else { return }
        isRunning = false
        timer.suspend()
    }
}
