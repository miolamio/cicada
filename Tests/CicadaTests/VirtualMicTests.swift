import CryptoKit
import Foundation
import Testing
@testable import Cicada

/// Serves a package that is not BlackHole.
final class FakePackage: URLProtocol, @unchecked Sendable {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("not the driver".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
}

@MainActor @Suite struct VirtualMicTests {
    @Test func pinnedPackageIsHTTPSAndAFullHash() {
        #expect(VirtualMicInstaller.packageURL.scheme == "https")
        #expect(VirtualMicInstaller.packageSHA256.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil)
    }

    @Test func aPackageWithTheWrongHashIsNotInstalled() async throws {
        let pkg = FileManager.default.temporaryDirectory.appendingPathComponent("LiveSubsMic/BlackHole2ch.pkg")
        try? FileManager.default.removeItem(at: pkg)
        let installer = VirtualMicInstaller()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [FakePackage.self]
        installer.session = URLSession(configuration: config)
        installer.install(verifyOnly: true)
        for _ in 0..<100 {
            if case .failed = installer.state { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        #expect(installer.state == .failed(L("安装包校验未通过，已中止安装")))
        #expect(!FileManager.default.fileExists(atPath: pkg.path))
    }

    /// The check that guards the install runs in the root shell, on root's own copy: a package
    /// swapped in after the download was verified never reaches the installer, the real one does.
    @Test func onlyThePinnedPackageReachesTheInstaller() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("cicada-pkg-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pkg = dir.appendingPathComponent("it's a.pkg"), ran = dir.appendingPathComponent("ran")
        try Data("the driver".utf8).write(to: pkg)
        let real = SHA256.hash(data: Data("the driver".utf8)).map { String(format: "%02x", $0) }.joined()
        let install = "/usr/sbin/installer -pkg \"$d/p.pkg\" -target /"
        #expect(VirtualMicInstaller.installCommand(package: pkg.path).contains(VirtualMicInstaller.packageSHA256))
        #expect(VirtualMicInstaller.installCommand(package: pkg.path).contains("'/private/var/root/cicada-pkg.XXXXXX'"))

        // The same command without root: the installer and the Core Audio restart swapped for markers.
        func exit(sha256: String) throws -> Int32 {
            let command = VirtualMicInstaller.installCommand(package: pkg.path, sha256: sha256, scratch: dir.path)
            #expect(command.contains(install))
            let sh = Process()
            sh.executableURL = URL(fileURLWithPath: "/bin/sh")
            sh.arguments = ["-c", command.replacingOccurrences(of: install, with: "/usr/bin/touch '\(ran.path)'")
                .replacingOccurrences(of: "/bin/launchctl kickstart -k system/com.apple.audio.coreaudiod", with: "/usr/bin/true")]
            sh.standardError = FileHandle.nullDevice
            try sh.run()
            sh.waitUntilExit()
            return sh.terminationStatus
        }
        #expect(try exit(sha256: String(repeating: "0", count: 64)) != 0)
        #expect(!FileManager.default.fileExists(atPath: ran.path))
        #expect(try exit(sha256: real) == 0)
        #expect(FileManager.default.fileExists(atPath: ran.path))
        // Root's copy is gone either way.
        #expect(try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted() == ["it's a.pkg", "ran"])
    }
}
