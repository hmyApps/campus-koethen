import CoreNFC
import Flutter
import UIKit
import UserNotifications
// Nur fuer setPluginRegistrantCallback noetig — das Plugin registriert damit
// die Plugins im eigenen Isolate, wenn eine Benachrichtigung die App startet.
import flutter_local_notifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var canteenBalanceBridge: CanteenBalanceNfcBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Ohne diese Zeile liefert iOS den Tap auf eine Benachrichtigung nicht an
    // die App aus; das Ziel-Routing bliebe still wirkungslos.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    FlutterLocalNotificationsPlugin.setPluginRegistrantCallback { (registry) in
      GeneratedPluginRegistrant.register(with: registry)
    }
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "CanteenBalanceNfcBridge"
    )
    canteenBalanceBridge = CanteenBalanceNfcBridge(
      messenger: registrar.messenger()
    )
  }
}

/// One-shot CoreNFC transport for the Flutter-owned, read-only APDU protocol.
///
/// This bridge never reads the UID, never persists data and never logs tag or
/// response bytes. It only appends SW1/SW2 to CoreNFC's payload so Android and
/// iOS feed the exact same parser in Dart.
private final class CanteenBalanceNfcBridge: NSObject, NFCTagReaderSessionDelegate {
  private static let channelName =
    "dev.erikengler.campuskoethen/canteen_balance"

  private let channel: FlutterMethodChannel
  private var session: NFCTagReaderSession?
  private var activeTag: NFCTag?
  private var pendingStartResult: FlutterResult?
  private var transceivePending = false
  private var operationGeneration = 0
  private var scanPrompt = ""

  init(messenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: messenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "availability":
      result(NFCTagReaderSession.readingAvailable ? "available" : "notSupported")
    case "hasPendingExternalTag":
      // iOS has no third-party equivalent of Android TECH_DISCOVERED dispatch.
      result(false)
    case "start":
      start(call, result: result)
    case "transceive":
      transceive(call.arguments, result: result)
    case "finish":
      finish()
      result(nil)
    case "cancel":
      cancel()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func start(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard NFCTagReaderSession.readingAvailable else {
      result(FlutterError(
        code: "nfc_not_supported",
        message: "NFC tag reading is not supported.",
        details: nil
      ))
      return
    }
    guard session == nil, pendingStartResult == nil, activeTag == nil else {
      result(FlutterError(
        code: "busy",
        message: "An NFC read is already active.",
        details: nil
      ))
      return
    }

    let arguments = call.arguments as? [String: Any]
    if arguments?["usePendingTag"] as? Bool == true {
      result(FlutterError(
        code: "no_pending_tag",
        message: "System tag dispatch is unavailable on iOS.",
        details: nil
      ))
      return
    }

    guard let readerSession = NFCTagReaderSession(
      pollingOption: .iso14443,
      delegate: self,
      queue: .main
    ) else {
      result(FlutterError(
        code: "nfc_not_supported",
        message: "NFC tag reading is not supported.",
        details: nil
      ))
      return
    }
    operationGeneration += 1
    scanPrompt = arguments?["prompt"] as? String ?? ""
    pendingStartResult = result
    session = readerSession
    readerSession.alertMessage = scanPrompt
    readerSession.begin()
  }

  private func transceive(_ arguments: Any?, result: @escaping FlutterResult) {
    guard !transceivePending else {
      result(FlutterError(code: "busy", message: "An NFC command is active.", details: nil))
      return
    }
    guard
      let typedData = arguments as? FlutterStandardTypedData,
      let apdu = NFCISO7816APDU(data: typedData.data),
      let tag = activeTag
    else {
      result(FlutterError(code: "invalid_response", message: "Invalid APDU.", details: nil))
      return
    }

    transceivePending = true
    let requestGeneration = operationGeneration
    let completion: (Data, UInt8, UInt8, Error?) -> Void = {
      [weak self] payload, sw1, sw2, error in
      DispatchQueue.main.async {
        guard let self else { return }
        guard self.operationGeneration == requestGeneration else {
          result(FlutterError(
            code: "cancelled",
            message: "NFC session cancelled.",
            details: nil
          ))
          return
        }
        self.transceivePending = false
        if error != nil {
          result(FlutterError(
            code: "tag_lost",
            message: "NFC communication ended.",
            details: nil
          ))
          return
        }
        var response = payload
        response.append(sw1)
        response.append(sw2)
        result(FlutterStandardTypedData(bytes: response))
      }
    }

    switch tag {
    case .iso7816(let isoTag):
      isoTag.sendCommand(apdu: apdu, completionHandler: completion)
    case .miFare(let miFareTag):
      guard miFareTag.mifareFamily == .desfire || miFareTag.mifareFamily == .plus else {
        transceivePending = false
        result(FlutterError(
          code: "unsupported_tag",
          message: "This MIFARE tag is not supported.",
          details: nil
        ))
        return
      }
      miFareTag.sendMiFareISO7816Command(apdu, completionHandler: completion)
    default:
      transceivePending = false
      result(FlutterError(
        code: "unsupported_tag",
        message: "This NFC tag is not supported.",
        details: nil
      ))
    }
  }

  private func finish() {
    operationGeneration += 1
    let activeSession = session
    session = nil
    pendingStartResult = nil
    transceivePending = false
    activeTag = nil
    activeSession?.invalidate()
  }

  private func cancel() {
    operationGeneration += 1
    let activeSession = session
    session = nil
    let startResult = pendingStartResult
    pendingStartResult = nil
    transceivePending = false
    activeTag = nil
    activeSession?.invalidate()
    startResult?(FlutterError(
      code: "cancelled",
      message: "NFC session cancelled.",
      details: nil
    ))
  }

  func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

  func tagReaderSession(
    _ session: NFCTagReaderSession,
    didInvalidateWithError error: Error
  ) {
    DispatchQueue.main.async { [weak self] in
      guard let self else { return }
      guard self.session === session else { return }
      self.operationGeneration += 1
      let startResult = self.pendingStartResult
      self.pendingStartResult = nil
      self.activeTag = nil
      self.transceivePending = false
      self.session = nil
      let code: String
      if let readerError = error as? NFCReaderError,
         readerError.code == .readerSessionInvalidationErrorUserCanceled {
        code = "cancelled"
      } else {
        code = "tag_lost"
      }
      startResult?(FlutterError(
        code: code,
        message: "NFC session ended.",
        details: nil
      ))
    }
  }

  func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
    guard self.session === session else { return }
    guard tags.count == 1, let tag = tags.first else {
      session.alertMessage = scanPrompt
      session.restartPolling()
      return
    }
    switch tag {
    case .iso7816, .miFare:
      break
    default:
      let startResult = pendingStartResult
      pendingStartResult = nil
      operationGeneration += 1
      self.session = nil
      session.invalidate()
      startResult?(FlutterError(
        code: "unsupported_tag",
        message: "This NFC tag is not supported.",
        details: nil
      ))
      return
    }

    session.connect(to: tag) { [weak self] error in
      DispatchQueue.main.async {
        guard let self else { return }
        guard self.session === session else { return }
        if error != nil {
          self.operationGeneration += 1
          self.pendingStartResult?(FlutterError(
            code: "tag_lost",
            message: "The NFC tag could not be connected.",
            details: nil
          ))
          self.pendingStartResult = nil
          self.session = nil
          session.invalidate()
          return
        }
        self.activeTag = tag
        let startResult = self.pendingStartResult
        self.pendingStartResult = nil
        startResult?(nil)
      }
    }
  }
}
