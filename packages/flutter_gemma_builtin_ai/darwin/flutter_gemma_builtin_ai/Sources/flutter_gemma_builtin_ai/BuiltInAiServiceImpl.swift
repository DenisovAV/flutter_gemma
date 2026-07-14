import Foundation

#if os(iOS)
  import Flutter
#elseif os(macOS)
  import FlutterMacOS
#endif

#if canImport(FoundationModels)
  import FoundationModels
#endif

/// Backs the pigeon `BuiltInAiService` with Apple's FoundationModels
/// (`SystemLanguageModel` / `LanguageModelSession`) and drives the shared
/// "flutter_gemma_builtin_ai_stream" `FlutterEventChannel`.
///
/// Native → Dart stream contract (the Dart demux depends on all three — this is
/// IDENTICAL to the Android `BuiltInAiServiceImpl`):
///  1. EVERY data event carries a `sessionId` (token / done / error).
///  2. Completion is a TAGGED DATA event `["partialResult":"", "done":true,
///     "sessionId":id]` — NEVER `FlutterEndOfEventStream` and NEVER a
///     `FlutterError` (the channel is shared across sessions, so both would hit
///     every listener and drop the id). Generation errors are the tagged data
///     event `["code":"ERROR", "message":..., "sessionId":id]`.
///  3. `checkAvailability` reflects readiness — `.modelNotReady` maps to
///     `downloading`, which Dart's `ensureReady` polls until it flips to
///     `available`.
///
/// FoundationModels only exists on iOS 26+/macOS 26+, so every use is gated with
/// `if #available(iOS 26.0, macOS 26.0, *)` and sessions are stored TYPE-ERASED
/// (`[Int64: Any]`, boxed as `SessionState`) so this class itself compiles on
/// the iOS-16 / macOS-10.15 floor declared in the podspec.
///
/// Unlike the Android Prompt API (single-turn, no server history), a
/// `LanguageModelSession` keeps its OWN transcript across `respond`/`stream`
/// calls, so we do NOT replay history — we only buffer the CURRENT turn's text
/// and clear it once the turn is sent.
public class BuiltInAiServiceImpl: NSObject, BuiltInAiService, FlutterStreamHandler {

  // MARK: - Per-session state (available-gated, boxed into [Int64: Any])

  /// Holds the FoundationModels session, its sampling options, the pending
  /// (current-turn) prompt text, and the in-flight streaming `Task`.
  /// Only ever constructed inside `if #available(iOS 26.0, macOS 26.0, *)`.
  ///
  /// `pendingText` and `task` are mutated without a per-field lock: the pigeon
  /// `FlutterBasicMessageChannel` handlers all dispatch serially on the platform
  /// (main) thread on Darwin, so `addQueryChunk` / `generate*` / `stop` never run
  /// concurrently for the same session. If pigeon dispatch is ever moved off the
  /// main queue, these mutations must be guarded.
  @available(iOS 26.0, macOS 26.0, *)
  private final class SessionState {
    let session: LanguageModelSession
    let options: GenerationOptions
    var pendingText: String = ""
    var task: Task<Void, Never>?

    init(session: LanguageModelSession, options: GenerationOptions) {
      self.session = session
      self.options = options
    }
  }

  // MARK: - Fields

  /// Type-erased so the property type does not reference FoundationModels; each
  /// value is a `SessionState` boxed as `Any` (only created on OS 26+).
  private var sessions: [Int64: Any] = [:]
  private let sessionsLock = NSLock()

  private var eventSink: FlutterEventSink?
  private let sinkLock = NSLock()

  // MARK: - FlutterStreamHandler

  public func onListen(
    withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink
  ) -> FlutterError? {
    sinkLock.lock()
    eventSink = events
    sinkLock.unlock()
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sinkLock.lock()
    eventSink = nil
    sinkLock.unlock()
    return nil
  }

  /// Post a payload to the shared sink on the main thread (a `FlutterEventSink`
  /// must be called from the platform thread). NEVER closes the channel — it is
  /// shared across sessions.
  private func postEvent(_ payload: [String: Any?]) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self else { return }
      self.sinkLock.lock()
      let sink = self.eventSink
      self.sinkLock.unlock()
      sink?(payload)
    }
  }

  // MARK: - Session storage helpers

  @available(iOS 26.0, macOS 26.0, *)
  private func state(for sessionId: Int64) -> SessionState? {
    sessionsLock.lock()
    defer { sessionsLock.unlock() }
    return sessions[sessionId] as? SessionState
  }

  // MARK: - BuiltInAiService

  func checkAvailability(completion: @escaping (Result<AvailabilityStatus, Error>) -> Void) {
    guard #available(iOS 26.0, macOS 26.0, *) else {
      // The framework itself is absent below OS 26.
      completion(.success(.unavailableOsTooOld))
      return
    }
    let status: AvailabilityStatus
    switch SystemLanguageModel.default.availability {
    case .available:
      status = .available
    case .unavailable(.deviceNotEligible):
      status = .unavailableDeviceUnsupported
    case .unavailable(.appleIntelligenceNotEnabled):
      status = .unavailableDisabled
    case .unavailable(.modelNotReady):
      // Apple Intelligence is downloading / preparing assets. Dart's
      // `ensureReady` treats this as `downloading` and polls until `available`.
      status = .downloading
    case .unavailable:
      // Any future reason we don't map explicitly.
      status = .unavailableOther
    }
    completion(.success(status))
  }

  /// Darwin no-op: there is no app-triggerable download. Apple Intelligence is
  /// enabled in Settings by the user, and `.modelNotReady` (→ `downloading`) is
  /// resolved by the OS, which Dart's `ensureReady` polls for. Returns success
  /// immediately so `ensureReady` proceeds straight to polling.
  func downloadFeature(completion: @escaping (Result<Void, Error>) -> Void) {
    completion(.success(()))
  }

  func createModel(supportImage: Bool, completion: @escaping (Result<Void, Error>) -> Void) {
    // The OS owns the weights; there is no model handle to allocate. Sessions
    // are created lazily in `createSession`. `supportImage` is advisory —
    // multimodality is decided per turn (and requires OS 27, see `addImage`).
    completion(.success(()))
  }

  func closeModel(completion: @escaping (Result<Void, Error>) -> Void) {
    if #available(iOS 26.0, macOS 26.0, *) {
      sessionsLock.lock()
      let states = sessions.values.compactMap { $0 as? SessionState }
      sessions.removeAll()
      sessionsLock.unlock()
      for state in states { state.task?.cancel() }
    } else {
      sessionsLock.lock()
      sessions.removeAll()
      sessionsLock.unlock()
    }
    completion(.success(()))
  }

  func createSession(
    sessionId: Int64,
    temperature: Double,
    topK: Int64,
    topP: Double?,
    maxOutputTokens: Int64?,
    systemInstruction: String?,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard #available(iOS 26.0, macOS 26.0, *) else {
      completion(
        .failure(
          PigeonError(
            code: "OS_TOO_OLD",
            message: "Apple Foundation Models requires iOS 26 / macOS 26 or newer.",
            details: nil)))
      return
    }

    // topK > 0 → nucleus/top-k random sampling; topK <= 0 → greedy (nil).
    // topP has no GenerationOptions counterpart in this SDK; it is accepted for
    // contract parity but not applied.
    let sampling: GenerationOptions.SamplingMode? =
      topK > 0 ? .random(top: Int(topK)) : nil
    let maxTokens: Int? = maxOutputTokens.map { Int($0) }
    let options = GenerationOptions(
      sampling: sampling,
      temperature: temperature,
      maximumResponseTokens: maxTokens)

    let instructions = (systemInstruction?.isEmpty == false) ? systemInstruction : nil
    let session = LanguageModelSession(instructions: instructions)
    let state = SessionState(session: session, options: options)

    sessionsLock.lock()
    // Replace any prior session at this id, cancelling its in-flight task.
    (sessions[sessionId] as? SessionState)?.task?.cancel()
    sessions[sessionId] = state
    sessionsLock.unlock()

    completion(.success(()))
  }

  func closeSession(sessionId: Int64, completion: @escaping (Result<Void, Error>) -> Void) {
    sessionsLock.lock()
    let removed = sessions.removeValue(forKey: sessionId)
    sessionsLock.unlock()
    if #available(iOS 26.0, macOS 26.0, *) {
      (removed as? SessionState)?.task?.cancel()
    }
    // If a generation stream was still active, emit a tagged completion so a
    // consumer awaiting getResponseAsync() closes cleanly instead of hanging —
    // closing a session mid-stream must terminate that stream, same as
    // stopGeneration does (the task cancel alone is silent to Dart).
    if removed != nil {
      postEvent([
        "partialResult": "",
        "done": true,
        "sessionId": sessionId,
      ])
    }
    completion(.success(()))
  }

  func addQueryChunk(
    sessionId: Int64, text: String, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard #available(iOS 26.0, macOS 26.0, *) else {
      completion(.failure(sessionMissingError(sessionId)))
      return
    }
    guard let state = state(for: sessionId) else {
      completion(.failure(sessionMissingError(sessionId)))
      return
    }
    // Normal multi-turn relies on the native LanguageModelSession retaining its
    // own transcript, so each turn appends only the current message. LIMITATION
    // (v1): on a context-overflow recreate, core replays the whole history via
    // addQueryChunk, and this concatenation folds prior user+assistant turns
    // into one prompt with no role/turn structure (the iOS 26 API exposes no
    // Transcript seeding). Acceptable degradation after overflow; revisit when a
    // transcript-seeding init ships. See spec §10 roadmap.
    state.pendingText += text
    completion(.success(()))
  }

  func addImage(
    sessionId: Int64, imageBytes: FlutterStandardTypedData,
    completion: @escaping (Result<Void, Error>) -> Void
  ) {
    // Image input requires `FoundationModels.Attachment`, which only exists on
    // iOS 27 / macOS 27. This plugin builds against the iOS 26 / macOS 26 SDK,
    // where the `Attachment` type is not present, so the multimodal branch
    // cannot be compiled here. We therefore reject image input on every OS this
    // SDK targets. This surfaces on the Dart side as a `PlatformException` with
    // code `IMAGE_UNSUPPORTED_OS` (image support is deferred to an OS-27 SDK build).
    completion(
      .failure(
        PigeonError(
          code: "IMAGE_UNSUPPORTED_OS",
          message:
            "Image input for Apple Foundation Models requires iOS 27 / macOS 27; "
            + "this build targets the iOS 26 / macOS 26 SDK (text only).",
          details: nil)))
  }

  func generateResponse(
    sessionId: Int64, completion: @escaping (Result<String, Error>) -> Void
  ) {
    guard #available(iOS 26.0, macOS 26.0, *) else {
      completion(.failure(sessionMissingError(sessionId)))
      return
    }
    guard let state = state(for: sessionId) else {
      completion(.failure(sessionMissingError(sessionId)))
      return
    }

    let prompt = state.pendingText
    // Clear the buffer up front: the session keeps native transcript continuity,
    // so the next turn must start from empty regardless of success/failure.
    state.pendingText = ""

    Task {
      do {
        let response = try await state.session.respond(
          to: Prompt(prompt), options: state.options)
        completion(.success(response.content))
      } catch {
        completion(
          .failure(
            PigeonError(
              code: "ERROR",
              message: describeGenerationError(error),
              details: nil)))
      }
    }
  }

  func generateResponseAsync(
    sessionId: Int64, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    guard #available(iOS 26.0, macOS 26.0, *) else {
      completion(.failure(sessionMissingError(sessionId)))
      return
    }
    guard let state = state(for: sessionId) else {
      completion(.failure(sessionMissingError(sessionId)))
      return
    }

    let prompt = state.pendingText
    state.pendingText = ""

    // A fresh converter per generation: `streamResponse` snapshots are
    // cumulative, so we convert each snapshot to the newly-added tail (delta).
    var converter = SnapshotDeltaConverter()

    let task = Task { [weak self] in
      guard let self = self else { return }
      do {
        let stream = state.session.streamResponse(
          to: Prompt(prompt), options: state.options)
        for try await snapshot in stream {
          if Task.isCancelled { break }
          let delta = converter.delta(from: snapshot.content)
          if !delta.isEmpty {
            // (1) tagged token event.
            self.postEvent([
              "partialResult": delta,
              "done": false,
              "sessionId": sessionId,
            ])
          }
        }
        if Task.isCancelled {
          // Cancellation from `stopGeneration` — that path already posted the
          // single `done` completion, so do not post a second one here.
          return
        }
        // (2) completion as a TAGGED DATA event — NOT FlutterEndOfEventStream.
        self.postEvent([
          "partialResult": "",
          "done": true,
          "sessionId": sessionId,
        ])
      } catch is CancellationError {
        // Cooperative cancellation — `stopGeneration` owns the completion event.
        return
      } catch {
        // (3) Surface as a TAGGED DATA error, never a FlutterError (which would
        // broadcast to every session on the shared channel and lose the id).
        self.postEvent([
          "code": "ERROR",
          "message": self.describeGenerationError(error),
          "sessionId": sessionId,
        ])
      }
    }
    state.task = task
    completion(.success(()))
  }

  func stopGeneration(
    sessionId: Int64, completion: @escaping (Result<Void, Error>) -> Void
  ) {
    if #available(iOS 26.0, macOS 26.0, *) {
      state(for: sessionId)?.task?.cancel()
    }
    // Emit a tagged completion so the Dart stream closes cleanly on cancel —
    // this is the single completion signal on the stop path.
    postEvent([
      "partialResult": "",
      "done": true,
      "sessionId": sessionId,
    ])
    completion(.success(()))
  }

  func countTokens(text: String, completion: @escaping (Result<Int64, Error>) -> Void) {
    // `SystemLanguageModel.tokenCount(for:)` is gated to iOS 26.4 / macOS 26.4
    // (stricter than the 26.0 floor of the rest of the framework). On any OS
    // below that — including 26.0–26.3, where the model exists but the tokenizer
    // API does not — we return a pigeon error so Dart falls back to its
    // (text.length / 4) char heuristic.
    guard #available(iOS 26.4, macOS 26.4, *) else {
      completion(
        .failure(
          PigeonError(
            code: "TOKENIZER_UNAVAILABLE",
            message: "Token counting requires iOS 26.4 / macOS 26.4 or newer.",
            details: nil)))
      return
    }
    Task {
      do {
        let count = try await SystemLanguageModel.default.tokenCount(for: text)
        completion(.success(Int64(count)))
      } catch {
        completion(
          .failure(
            PigeonError(
              code: "TOKENIZER_ERROR",
              message: error.localizedDescription,
              details: nil)))
      }
    }
  }

  // MARK: - Error mapping

  // NOTE on the error type: `.failure` on the pigeon `Result<_, Error>` must
  // carry a value that conforms to Swift.Error. `PigeonError` (generated in
  // PigeonInterface.g.swift) does; `FlutterError` does NOT conform to Error on
  // macOS (it only does on iOS), so it cannot be used here in the shared source
  // set. `PigeonError`'s (code, message, details) decode to a Dart
  // `PlatformException(code:, message:)`, which is exactly what the Dart layer
  // keys on (e.g. `IMAGE_UNSUPPORTED_OS` → UnsupportedError; a `countTokens`
  // PigeonError → the char-heuristic fallback). `FlutterError` remains only in
  // the two `FlutterStreamHandler` protocol returns above (required signature).
  private func sessionMissingError(_ sessionId: Int64) -> PigeonError {
    PigeonError(
      code: "SESSION_NOT_FOUND",
      message: "Session \(sessionId) not found.",
      details: nil)
  }

  /// Maps a thrown generation error to a readable message. Switches over the
  /// documented `LanguageModelSession.GenerationError` cases; anything else
  /// falls back to `localizedDescription`.
  private func describeGenerationError(_ error: Error) -> String {
    if #available(iOS 26.0, macOS 26.0, *) {
      if let genError = error as? LanguageModelSession.GenerationError {
        switch genError {
        case .exceededContextWindowSize:
          return "The conversation exceeded the model's context window. "
            + "Start a new session or shorten the input."
        case .assetsUnavailable:
          return "The on-device model assets are unavailable. "
            + "Ensure Apple Intelligence is enabled and finished downloading."
        case .guardrailViolation:
          return "The request was blocked by the model's safety guardrails."
        case .unsupportedGuide:
          return "The requested generation guide is not supported."
        case .unsupportedLanguageOrLocale:
          return "The requested language or locale is not supported by the model."
        case .decodingFailure:
          return "The model response could not be decoded."
        case .rateLimited:
          return "The model is rate limited. Please retry shortly."
        case .concurrentRequests:
          return "Another request is already in flight on this session. "
            + "Wait for it to finish before starting a new one."
        case .refusal:
          return "The model refused to respond to this request."
        @unknown default:
          return genError.errorDescription ?? "Generation failed."
        }
      }
    }
    if error is CancellationError {
      return "Generation was cancelled."
    }
    return (error as NSError).localizedDescription
  }
}
