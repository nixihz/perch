import Darwin
import Foundation

public enum ApplyLockError: Error, LocalizedError, Equatable, Sendable {
    case busy(String)
    case openFailed(String)
    case lockFailed(String)

    public var code: String {
        switch self {
        case .busy: "PLAN_BUSY"
        case .openFailed: "PLAN_LOCK_OPEN_FAILED"
        case .lockFailed: "PLAN_LOCK_FAILED"
        }
    }

    public var errorDescription: String? {
        switch self {
        case let .busy(path):
            return "已有另一个进程正在执行同一目标的计划：\(path)"
        case let .openFailed(path):
            return "无法创建计划锁文件：\(path)"
        case let .lockFailed(path):
            return "无法取得计划锁：\(path)"
        }
    }
}

/// 依赖文件描述符生命周期的跨进程互斥锁；进程退出时由系统自动释放。
public final class ApplyLockHandle {
    private let descriptor: Int32

    fileprivate init(descriptor: Int32) {
        self.descriptor = descriptor
    }

    deinit {
        _ = Darwin.close(descriptor)
    }
}

public enum ApplyLock {
    public static func acquire(rootURL: URL, scope: String) throws -> ApplyLockHandle {
        let directory = rootURL.appendingPathComponent("locks", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let digest = SkillAssetCopier.sha256(Data(scope.utf8))
        let url = directory.appendingPathComponent("apply-\(digest).lock")
        let descriptor = Darwin.open(
            url.path,
            O_CREAT | O_RDWR | O_EXLOCK | O_NONBLOCK,
            S_IRUSR | S_IWUSR
        )
        guard descriptor >= 0 else {
            if errno == EWOULDBLOCK || errno == EAGAIN {
                throw ApplyLockError.busy(scope)
            }
            throw ApplyLockError.openFailed(url.path)
        }
        return ApplyLockHandle(descriptor: descriptor)
    }
}
