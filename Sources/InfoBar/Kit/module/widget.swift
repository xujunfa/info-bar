import Foundation

public protocol WidgetProtocol: AnyObject {
    var isActive: Bool { get set }
    func setValue(_ value: Any?)
}

open class Widget: WidgetProtocol {
    public var isActive: Bool = true

    public init() {}
    open func setValue(_ value: Any?) {}
}
