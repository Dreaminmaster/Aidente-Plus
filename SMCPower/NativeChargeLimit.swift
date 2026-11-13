import Foundation
import ObjectiveC
import Darwin

/// Independent runtime bridge to Apple's system charge-limit client. Private
/// API availability is checked at runtime; this does not grant SMC access.
public final class NativeChargeLimit {
    public struct State: Codable, Equatable {
        public let limit: Int
        public let enabled: Bool
    }
    private let object: AnyObject
    private let type: AnyClass
    private typealias ErrorPointer = AutoreleasingUnsafeMutablePointer<NSError?>?
    private typealias Flag = @convention(c) (AnyObject, Selector) -> Bool
    private typealias ByteRead = @convention(c) (AnyObject, Selector, ErrorPointer) -> UInt8
    private typealias FlagRead = @convention(c) (AnyObject, Selector, ErrorPointer) -> UInt64
    private typealias LimitsRead = @convention(c) (AnyObject, Selector, ErrorPointer) -> Unmanaged<AnyObject>?
    private typealias Write = @convention(c) (AnyObject, Selector, UInt8, ErrorPointer) -> Bool
    private typealias Disable = @convention(c) (AnyObject, Selector, ErrorPointer) -> Bool

    public init() throws {
        guard dlopen("/System/Library/PrivateFrameworks/PowerUI.framework/Versions/A/PowerUI", RTLD_NOW) != nil,
              let cls = NSClassFromString("PowerUISmartChargeClient") else { throw Self.failure("系统原生限充接口不可用") }
        // Check return/argument ABI before casting an IMP. Unknown future API
        // signatures fail closed instead of making an unsafe runtime call.
        let signatures: [(String, String, [String])] = [
            ("initWithClientName:", "@", ["@"]), ("isMCLSupported", "B", []),
            ("getMCLLimitWithError:", "C", ["^@"]),
            ("isMCLCurrentlyEnabled:", "Q", ["^@"]),
            ("availableChargeLimitsWithError:", "@", ["^@"]),
            ("setMCLLimit:error:", "B", ["C", "^@"]), ("disableMCL:", "B", ["^@"])
        ]
        for (name, result, arguments) in signatures {
            guard let method = class_getInstanceMethod(cls, NSSelectorFromString(name)),
                  method_getNumberOfArguments(method) == arguments.count + 2 else { throw Self.failure("系统限充接口签名未知") }
            let returnType = method_copyReturnType(method)
            defer { free(returnType) }
            guard String(cString: returnType) == result else { throw Self.failure("系统限充接口返回类型已变化") }
            for (index, expected) in arguments.enumerated() {
                guard let argument = method_copyArgumentType(method, UInt32(index + 2)) else { throw Self.failure("系统限充接口参数未知") }
                defer { free(argument) }
                guard String(cString: argument) == expected else { throw Self.failure("系统限充接口参数已变化") }
            }
        }
        guard let raw = class_createInstance(cls, 0) else { throw Self.failure("无法创建系统限充客户端") }
        typealias Initialize = @convention(c) (AnyObject, Selector, NSString) -> AnyObject
        let selector = NSSelectorFromString("initWithClientName:")
        object = unsafeBitCast(class_getMethodImplementation(cls, selector)!, to: Initialize.self)(raw as AnyObject, selector, "Aidente")
        type = cls
        let supported = NSSelectorFromString("isMCLSupported")
        guard unsafeBitCast(class_getMethodImplementation(cls, supported)!, to: Flag.self)(object, supported) else {
            throw Self.failure("本机不支持系统原生限充")
        }
    }
    public func availableLimits() throws -> [Int] {
        let selector = NSSelectorFromString("availableChargeLimitsWithError:")
        var error: NSError?
        let value = unsafeBitCast(class_getMethodImplementation(type, selector)!, to: LimitsRead.self)(object, selector, &error)?.takeUnretainedValue()
        if let error { throw error }
        guard let values = value as? [NSNumber] else { throw Self.failure("无法读取系统限充档位") }
        let limits = Array(Set(values.map(\.intValue).filter { (80...100).contains($0) })).sorted()
        guard !limits.isEmpty else { throw Self.failure("系统没有返回可用限充档位") }
        return limits
    }
    public func read() throws -> State {
        var error: NSError?
        let limitSelector = NSSelectorFromString("getMCLLimitWithError:")
        let limit = unsafeBitCast(class_getMethodImplementation(type, limitSelector)!, to: ByteRead.self)(object, limitSelector, &error)
        if let error { throw error }
        let flagSelector = NSSelectorFromString("isMCLCurrentlyEnabled:")
        let enabled = unsafeBitCast(class_getMethodImplementation(type, flagSelector)!, to: FlagRead.self)(object, flagSelector, &error)
        if let error { throw error }
        guard (0...100).contains(Int(limit)), enabled <= 1 else { throw Self.failure("系统限充状态未知") }
        return State(limit: Int(limit), enabled: enabled == 1)
    }
    public func set(_ limit: Int) throws {
        guard (80...100).contains(limit) else { throw Self.failure("用户态原生接口只接受 80–100%；更低目标需要已授权的后台服务") }
        if try read() == State(limit: limit, enabled: limit < 100) { return }
        var error: NSError?
        let selector = NSSelectorFromString("setMCLLimit:error:")
        let success = unsafeBitCast(class_getMethodImplementation(type, selector)!, to: Write.self)(object, selector, UInt8(limit), &error)
        if let error { throw error }
        guard success, try read() == State(limit: limit, enabled: limit < 100) else { throw Self.failure("系统限充写入未通过读回验证") }
    }
    public func restore(_ state: State) throws {
        if state.enabled { try set(state.limit); return }
        // The UI reports disabled for sub-80 limits even while powerd still
        // enforces them. Always ask the agent to unregister its active policy.
        var error: NSError?
        let selector = NSSelectorFromString("disableMCL:")
        let success = unsafeBitCast(class_getMethodImplementation(type, selector)!, to: Disable.self)(object, selector, &error)
        if let error { throw error }
        guard success, try !read().enabled else { throw Self.failure("系统限充原设置恢复失败") }
    }
    public func disable() throws { try restore(State(limit: 100, enabled: false)) }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "AidenteNativeChargeLimit", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
