// ---------------------------
// leofindit_ios/ios/Runner/BluetoothManager.swift
// send invokeMethod("onDevice", payload)
// Channel owned by AppDelegate: "leo_find_it/scanner"
// ---------------------------

import CoreBluetooth
import Flutter
import Foundation

final class BluetoothManager: NSObject, CBCentralManagerDelegate {

  // ===== Contract constants (match Android) =====
  private let TX_POWER: Double = -59.0  // same assumption used on Android distance estimate
  private let PATH_LOSS_N: Double = 2.0  // indoor-ish
  private let TRACKER_TTL_MS: Int64 = 30_000  // similar spirit to Android TTL eviction

  private let channel: FlutterMethodChannel
  private var central: CBCentralManager!

  private var scanning = false

  // Minimal state so we can emit stable "signature" + TTL eviction
  private struct TrackerState {
    var lastSeenMs: Int64
    var firstSeenMs: Int64
    var sightings: Int
    var rotatingMacCount: Int  // iOS can't read MAC -> stays 0
    var rawFrame: String
    var kind: String
    var lastRssi: Int
  }

  private var states: [String: TrackerState] = [:]  // signature -> state

  init(channel: FlutterMethodChannel) {
    self.channel = channel
    super.init()
    self.central = CBCentralManager(delegate: self, queue: nil)
  }

  // ===== Flutter -> iOS =====
  func startScan() {
    guard central.state == .poweredOn else {
      // Flutter side doesn’t currently listen for an error callback in BleBridge,
      // so we just no-op. (You can add a "onError" later if you want.)
      return
    }
    if scanning { return }
    scanning = true

    // We scan broadly (same as Android startScan(null,...)).
    central.scanForPeripherals(
      withServices: nil,
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: true]
    )
  }

  func stopScan() {
    if !scanning { return }
    scanning = false
    central.stopScan()
  }

  // ===== CBCentralManagerDelegate =====
  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    // Do nothing here — scan starts only when Flutter calls startScan,
    // matching the Android UX.
    if central.state != .poweredOn {
      stopScan()
    }
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {

    // iOS uses 127 as invalid RSSI (ignore those)
    let rssi = RSSI.intValue
    if rssi == 127 { return }

    let nowMs = Int64(Date().timeIntervalSince1970 * 1000)

    // TTL eviction (prevents phantom buildup)
    states = states.filter { nowMs - $0.value.lastSeenMs <= TRACKER_TTL_MS }

    // ---- Determine "kind" (best-effort, mirrors Android categories) ----
    let kind = classifyKind(advertisementData: advertisementData)

    // ---- signature: stable identity for Flutter merge logic ----
    // Android derives signature from non-rotating bytes; on iOS we often can't see the same raw data,
    // so we use a stable surrogate: peripheral UUID + kind
    let signature = "IOS_\(kind)_\(peripheral.identifier.uuidString)"

    // ---- raw frame (hex) best-effort ----
    // iOS does not expose full scanRecord bytes like Android.
    // We store manufacturer data (if present) as hex.
    let rawFrame = extractManufacturerHex(advertisementData: advertisementData)

    let isConnectable = (advertisementData[CBAdvertisementDataIsConnectable] as? Bool) ?? false
    let localName = (advertisementData[CBAdvertisementDataLocalNameKey] as? String) ?? ""
    let serviceUUIDs = (advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID]) ?? []
    let serviceUuidStrings = serviceUUIDs.map { $0.uuidString.uppercased() }

    // ---- update state ----
    let prev = states[signature]
    let firstSeen = prev?.firstSeenMs ?? nowMs
    let sightings = (prev?.sightings ?? 0) + 1

    states[signature] = TrackerState(
      lastSeenMs: nowMs,
      firstSeenMs: firstSeen,
      sightings: sightings,
      rotatingMacCount: 0,  // iOS cannot read device MAC
      rawFrame: rawFrame,
      kind: kind,
      lastRssi: rssi
    )

    // ---- distance estimate (meters) ----
    let distanceMeters = estimateDistanceMeters(rssi: rssi)

    // ---- payload MUST match Android/Flutter expectations ----
    // (TrackerDevice.fromNative reads these keys)
    // See Android sendToFlutter payload fields. :contentReference[oaicite:4]{index=4}
    let payload: [String: Any] = [
      "id": "\(kind)_\(signature)",
      "logicalId": "\(kind)_\(signature)",
      "address": NSNull(),  // iOS: not available
      "mac": "",  // iOS: not available
      "kind": kind,
      "rssi": rssi,
      "distanceMeters": distanceMeters,
      "firstSeenMs": Int(firstSeen),
      "lastSeenMs": Int(nowMs),
      "sightings": sightings,
      "signature": signature,
      "rawFrame": rawFrame,
      "rotatingMacCount": 0,
      "localName": localName,
      "isConnectable": isConnectable,
      "serviceUuids": serviceUuidStrings,
    ]

    if kind == "UNKNOWN" {
      print(
        "BLE UNKNOWN name=\(localName) rssi=\(rssi) conn=\(isConnectable) services=\(serviceUuidStrings) mfg=\(rawFrame)"
      )
    }
    // Native -> Flutter callback: onDevice (matches BleBridge) :contentReference[oaicite:5]{index=5}
    channel.invokeMethod("onDevice", arguments: payload)
  }

  // ===== Helpers =====

  private func estimateDistanceMeters(rssi: Int) -> Double {
    // same shape as Android: 10 ^ ((txPower - rssi) / (10*n))
    let ratio = (TX_POWER - Double(rssi)) / (10.0 * PATH_LOSS_N)
    return pow(10.0, ratio)
  }

  private func classifyKind(advertisementData: [String: Any]) -> String {
    let localName =
      (advertisementData[CBAdvertisementDataLocalNameKey] as? String)?.lowercased() ?? ""
    // 1) Name-based hint (Tiles often broadcast a name)
    if localName.contains("tile") {
      return "TILE"
    }
    if localName.contains("smarttag") || localName.contains("samsung") {
      return "SAMSUNG"
    }

    // 2) Manufacturer data company id (best when present)
    if let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data, mfg.count >= 2
    {
      let b0 = UInt16(mfg[mfg.startIndex])
      let b1 = UInt16(mfg[mfg.startIndex + 1])
      let companyId = b0 | (b1 << 8)
      if companyId == 0x0075 { return "SAMSUNG" }
      if companyId == 0x0131 { return "TILE" }
      // Apple is noisy: AirPods/phones/etc.
      if companyId == 0x004C { return "APPLE_DEVICE" }
    }

    // 3) Service UUID heuristic (sometimes present)
    if let uuids = advertisementData[CBAdvertisementDataServiceUUIDsKey] as? [CBUUID] {
      let s = uuids.map { $0.uuidString.uppercased() }
      // Find My is not consistently visible on iOS, but keep the heuristic
      if s.contains(where: { $0.contains("FD44") }) {
        return "AIRTAG"
      }
    }

    return "UNKNOWN"
  }

  private func extractManufacturerHex(advertisementData: [String: Any]) -> String {
    guard let mfg = advertisementData[CBAdvertisementDataManufacturerDataKey] as? Data else {
      return ""
    }
    return mfg.map { String(format: "%02x", $0) }.joined()
  }
}
