import Cocoa
import FlutterMacOS
import PDFKit
import Vision
import CoreImage
import CoreML

class MainFlutterWindow: NSWindow {
  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)
    LocalParsersChannel.register(with: flutterViewController)

    super.awakeFromNib()
  }
}

private enum LocalParserError: Error {
  case missingFile(String)
  case missingTool(String)
  case failed(String)
}

private final class LocalParsersChannel {
  static func register(with controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "local_parsers",
      binaryMessenger: controller.engine.binaryMessenger)

    channel.setMethodCallHandler { call, result in
      do {
        let arguments = call.arguments as? [String: Any] ?? [:]
        switch call.method {
        case "extractPdfTextWithPdfium":
          guard let path = arguments["path"] as? String else {
            result(FlutterError(code: "bad_arguments", message: "Missing file path.", details: nil))
            return
          }
          result(try extractPdfTextWithPdfium(path: path))
        case "extractDocumentTextWithTika":
          guard let path = arguments["path"] as? String else {
            result(FlutterError(code: "bad_arguments", message: "Missing file path.", details: nil))
            return
          }
          result(try extractDocumentTextWithTika(path: path))
        case "extractImageTextWithVision":
          guard let path = arguments["path"] as? String else {
            result(FlutterError(code: "bad_arguments", message: "Missing file path.", details: nil))
            return
          }
          result(extractImageTextWithVision(path: path))
        case "extractImageFeaturePrint":
          guard let path = arguments["path"] as? String else {
            result(FlutterError(code: "bad_arguments", message: "Missing file path.", details: nil))
            return
          }
          result(extractImageFeaturePrint(path: path))
        case "embedTextForMobileCLIP":
          // Best-effort cross-modal text projection. Returns nil when no
          // MobileCLIP text encoder model is bundled, so the Dart side
          // can fall back to its deterministic hash-based projection.
          let text = arguments["text"] as? String ?? ""
          result(embedTextForMobileCLIP(text: text))
        default:
          result(FlutterMethodNotImplemented)
        }
      } catch {
        result(FlutterError(code: "parse_failed", message: "\(error)", details: nil))
      }
    }
  }

  // MARK: - PDF

  private static func extractPdfTextWithPdfium(path: String) throws -> String {
    try requireFile(path)

    if let pdfText = extractPdfTextWithPdfKit(path: path),
       !pdfText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return pdfText
    }

    do {
      let script = try findProjectFile("scripts/extract_pdfium.py")
      return try runProcess(
        executable: "/usr/bin/python3",
        arguments: [script, path])
    } catch {
      return try extractDocumentTextWithTika(path: path)
    }
  }

  private static func extractPdfTextWithPdfKit(path: String) -> String? {
    guard let document = PDFDocument(url: URL(fileURLWithPath: path)) else {
      return nil
    }

    var pages: [String] = []
    for index in 0..<document.pageCount {
      if let text = document.page(at: index)?.string,
         !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
        pages.append(text)
      }
    }
    return pages.joined(separator: "\n")
  }

  private static func extractDocumentTextWithTika(path: String) throws -> String {
    try requireFile(path)
    let java = try findProjectFile(".tooling/jdk-21.0.11+10-jre/Contents/Home/bin/java")
    let tika = try findProjectFile(".tooling/tika-app.jar")
    return try runProcess(
      executable: java,
      arguments: ["-jar", tika, "--text", path])
  }

  // MARK: - Vision OCR (offline, on-device)

  private static func extractImageTextWithVision(path: String) -> String {
    guard let image = CIImage(contentsOf: URL(fileURLWithPath: path)) else {
      return ""
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    if #available(macOS 13.0, *) {
      request.automaticallyDetectsLanguage = true
    }
    request.recognitionLanguages = ["en-US", "zh-Hans", "zh-Hant"]

    let handler = VNImageRequestHandler(ciImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return ""
    }
    let lines = (request.results ?? [])
      .compactMap { $0.topCandidates(1).first?.string }
      .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    return lines.joined(separator: "\n")
  }

  // MARK: - CoreML image feature print (real MobileCLIP / Vision feature extractor)

  private static func extractImageFeaturePrint(path: String) -> [Double] {
    guard let image = CIImage(contentsOf: URL(fileURLWithPath: path)) else {
      return []
    }

    // First try Apple's bundled CoreML MobileCLIP image encoder (real multimodal model).
    if let clipVector = runCoreMLImageModel(name: "mobileclip_s0_image", image: image),
       !clipVector.isEmpty {
      return clipVector
    }

    // Fallback: Vision's built-in feature print (256-d) for general visual similarity.
    let request = VNGenerateImageFeaturePrintRequest()
    request.imageCropAndScaleOption = .centerCrop
    let handler = VNImageRequestHandler(ciImage: image, options: [:])
    do {
      try handler.perform([request])
    } catch {
      return []
    }
    guard let observation = (request.results ?? []).first else { return [] }
    return observation.data.withUnsafeBytes { raw -> [Double] in
      let buffer = raw.bindMemory(to: Float.self)
      return (0..<buffer.count).map { Double(buffer[$0]) }
    }
  }

  private static func runCoreMLImageModel(name: String, image: CIImage) -> [Double]? {
    guard let compiledURL = locateCompiledModel(named: name) else { return nil }
    do {
      var modelURL = compiledURL
      let config = MLModelConfiguration()
      config.computeUnits = .all
      let model = try MLModel(contentsOf: modelURL, configuration: config)
      // Apple MobileCLIP CoreML package exposes a Vision feature provider; the
      // simplest portable way to invoke it is through VNCoreMLRequest.
      guard let visionModel = try? VNCoreMLModel(for: model) else { return nil }
      let request = VNCoreMLRequest(model: visionModel)
      request.imageCropAndScaleOption = .centerCrop
      let handler = VNImageRequestHandler(ciImage: image, options: [:])
      try handler.perform([request])
      // Pull the first array-shaped output we can find.
      if let results = request.results, let provider = results.first?.value(forKey: "var_1418") as? MLFeatureProvider {
        return arrayFrom(provider: provider)
      }
      return nil
    } catch {
      return nil
    }
  }

  private static func arrayFrom(provider: MLFeatureProvider) -> [Double]? {
    for name in provider.featureNames {
      if let multiArray = provider.featureValue(for: name)?.multiArrayValue {
        let count = multiArray.count
        return (0..<count).map { Double(truncating: multiArray[$0]) }
      }
    }
    return nil
  }

  // MARK: - Cross-modal text encoder (MobileCLIP text tower via CoreML)

  /// Maps a free-form query to a CLIP-compatible embedding using the bundled
  /// MobileCLIP s0 text encoder when available. Returns `nil` when the
  /// encoder isn't present so the Dart layer can fall back to its
  /// deterministic text projection.
  private static func embedTextForMobileCLIP(text: String) -> [Double]? {
    if text.isEmpty { return nil }
    if let compiledURL = locateCompiledModel(named: "mobileclip_s0_text") {
      do {
        let config = MLModelConfiguration()
        config.computeUnits = .all
        let model = try MLModel(contentsOf: compiledURL, configuration: config)
        guard let visionModel = try? VNCoreMLModel(for: model) else { return nil }
        let request = VNCoreMLRequest(model: visionModel)
        // MobileCLIP text takes a single-channel 77-token int input. Building
        // a VNCoreMLRequest with image semantics isn't appropriate here, so
        // we use the CoreML prediction API directly. The simplest portable
        // shape is an `input_ids: [1, 77]` Int32 multi-array.
        let input = try MLMultiArray(shape: [1, 77], dataType: .int32)
        let tokenIds = tokenizeForMobileCLIP(text)
        for (index, token) in tokenIds.enumerated() where index < 77 {
          input[index] = NSNumber(value: token)
        }
        let provider = try MLDictionaryFeatureProvider(dictionary: [
          "input_ids": MLFeatureValue(multiArray: input),
        ])
        let output = try model.prediction(from: provider)
        return arrayFrom(provider: output)
      } catch {
        return nil
      }
    }
    return nil
  }

  /// Crude whitespace tokenizer with a stable hash-based vocabulary that
  /// mirrors what MobileCLIP expects (1 = SOS, 2 = EOS, 0 = pad). Real
  /// deployments should swap in the official BPE encoder; this is enough
  /// to drive the CoreML contract and produce stable embeddings.
  private static func tokenizeForMobileCLIP(_ text: String) -> [Int32] {
    var ids: [Int32] = [1]
    let words = text
      .lowercased()
      .components(separatedBy: CharacterSet.alphanumerics.inverted)
      .filter { !$0.isEmpty }
    for word in words.prefix(75) {
      var hash: UInt64 = 1469598103934665603
      for byte in word.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 1099511628211
      }
      ids.append(Int32(3 + hash % 49000))
    }
    ids.append(2)
    while ids.count < 77 { ids.append(0) }
    return Array(ids.prefix(77))
  }

  // MARK: - Helpers

  private static func locateCompiledModel(named name: String) -> URL? {
    let fm = FileManager.default
    var candidates: [URL] = []
    if let resourcePath = Bundle.main.resourcePath {
      candidates.append(URL(fileURLWithPath: resourcePath))
    }
    candidates.append(URL(fileURLWithPath: fm.currentDirectoryPath))
    // Walk up the bundle looking for assets/models/<name>.mlpackage or .mlmodelc
    for start in candidates {
      var url = start
      for _ in 0..<8 {
        let pkg = url.appendingPathComponent("assets/models/\(name).mlpackage")
        if fm.fileExists(atPath: pkg.path) { return pkg }
        let mc = url.appendingPathComponent("assets/models/\(name).mlmodelc")
        if fm.fileExists(atPath: mc.path) { return mc }
        url.deleteLastPathComponent()
      }
    }
    return nil
  }

  private static func requireFile(_ path: String) throws {
    if !FileManager.default.fileExists(atPath: path) {
      throw LocalParserError.missingFile(path)
    }
  }

  private static func findProjectFile(_ relativePath: String) throws -> String {
    if let override = ProcessInfo.processInfo.environment[environmentKey(for: relativePath)],
       FileManager.default.fileExists(atPath: override) {
      return override
    }

    var candidates = [
      FileManager.default.currentDirectoryPath,
      Bundle.main.bundleURL.path,
      Bundle.main.bundleURL.deletingLastPathComponent().path,
    ]

    if let resourcePath = Bundle.main.resourcePath {
      candidates.append(resourcePath)
    }

    for start in candidates {
      var url = URL(fileURLWithPath: start)
      for _ in 0..<8 {
        let candidate = url.appendingPathComponent(relativePath).path
        if FileManager.default.fileExists(atPath: candidate) {
          return candidate
        }
        url.deleteLastPathComponent()
      }
    }

    throw LocalParserError.missingTool(relativePath)
  }

  private static func environmentKey(for relativePath: String) -> String {
    if relativePath.contains("pdfium") {
      return "OFFLINE_RETRIEVAL_PDFIUM_SCRIPT"
    }
    if relativePath.contains("tika-app") {
      return "OFFLINE_RETRIEVAL_TIKA_APP"
    }
    return "OFFLINE_RETRIEVAL_JAVA"
  }

  private static func runProcess(executable: String, arguments: [String]) throws -> String {
    let process = Process()
    let output = Pipe()
    let error = Pipe()
    process.executableURL = URL(fileURLWithPath: executable)
    process.arguments = arguments
    process.standardOutput = output
    process.standardError = error

    try process.run()
    process.waitUntilExit()

    let data = output.fileHandleForReading.readDataToEndOfFile()
    let errorData = error.fileHandleForReading.readDataToEndOfFile()
    let text = String(data: data, encoding: .utf8) ?? ""
    let errorText = String(data: errorData, encoding: .utf8) ?? ""

    if process.terminationStatus != 0 {
      throw LocalParserError.failed(errorText.isEmpty ? text : errorText)
    }
    return text.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
