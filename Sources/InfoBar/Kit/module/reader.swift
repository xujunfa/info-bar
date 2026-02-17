import Foundation

public protocol ReaderProtocol: AnyObject {
    func start()
    func stop()
    func read()
    func pause()
    func lock()
    func unlock()
}

open class Reader<Value>: ReaderProtocol {
    public typealias Callback = (Value?) -> Void

    public var callback: Callback
    public var interval: Int
    public var popup: Bool

    private var repeater: Repeater?
    private var isLocked = true

    public init(interval: Int = 60, popup: Bool = false, callback: @escaping Callback = { _ in }) {
        self.interval = interval
        self.popup = popup
        self.callback = callback
    }

    open func start() {
        if popup && isLocked {
            read()
            return
        }
        if repeater == nil {
            repeater = Repeater(seconds: interval) { [weak self] in
                self?.read()
            }
        }
        repeater?.start()
        read()
    }

    open func stop() {
        repeater?.pause()
        repeater = nil
    }

    open func read() {}

    open func pause() {
        repeater?.pause()
    }

    open func lock() {
        isLocked = true
    }

    open func unlock() {
        isLocked = false
    }
}
