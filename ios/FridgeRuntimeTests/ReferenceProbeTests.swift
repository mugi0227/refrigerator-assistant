import XCTest
@testable import Fridge

final class ReferenceProbeTests: XCTestCase {
    func testReferenceImagesAndExportedLogs() async throws {
        let configURL = try XCTUnwrap(Bundle(for: Self.self).url(forResource: "config", withExtension: "json"))
        let config = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: configURL)) as? [String: String])
        let model = URL(fileURLWithPath: try XCTUnwrap(config["modelPath"]))
        // Keep the direct native log even if XCTest has to kill a stuck process.
        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("GemmaProbe-CI").appendingPathComponent(UUID().uuidString)
        let runner = ReferenceProbe()
        do {
            _ = try await runner.run(model: model, output: directory) { print("REFERENCE_PROGRESS: " + $0) }
        } catch {
            attachLogs(directory)
            throw error
        }
        attachLogs(directory)
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("result.json"))) as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "passed")
        XCTAssertEqual(result["modelActualSHA256"] as? String, ReferenceProbe.modelSHA256)
        XCTAssertEqual(result["initializationAndPrewarmSucceeded"] as? Bool, true)
        XCTAssertEqual(result["appleRecognized"] as? Bool, true)
        XCTAssertEqual(result["redRecognized"] as? Bool, true)
        print("REFERENCE_RESULT: \(result)")
    }

    func testRejectsDifferentModelWithoutDeletingItAndPreservesFailureReport() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("probe-invalid-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let model = directory.appendingPathComponent("invalid.litertlm")
        try Data("abc".utf8).write(to: model)
        XCTAssertEqual(try ReferenceProbe.sha256(model), "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        let output = directory.appendingPathComponent("report")
        do {
            _ = try await ReferenceProbe().run(model: model, output: output) { _ in }
            XCTFail("An incorrect model hash must be rejected before native initialization")
        } catch { XCTAssertTrue(error.localizedDescription.contains("SHA256")) }
        XCTAssertEqual(try Data(contentsOf: model), Data("abc".utf8))
        let result = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: output.appendingPathComponent("result.json"))) as? [String: Any])
        XCTAssertEqual(result["status"] as? String, "failed")
        XCTAssertEqual(result["failedPhase"] as? String, "checking-model")
        XCTAssertNil(result["initializationAndPrewarmSucceeded"])
    }

    private func attachLogs(_ directory: URL) {
        for name in ["result.json", "phases.txt", "native-stderr.txt", "apple-partial.txt", "red-partial.txt"] {
            if let data = try? Data(contentsOf: directory.appendingPathComponent(name)) {
                let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.plain-text")
                attachment.name = name; attachment.lifetime = .keepAlways; add(attachment)
            }
        }
    }
}
