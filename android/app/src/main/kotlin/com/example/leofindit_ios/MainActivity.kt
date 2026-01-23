package com.example.leo_find_it

import android.Manifest
import android.content.Context
import android.content.pm.PackageManager
import android.location.LocationManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {

    companion object {
        private const val PERMISSION_REQUEST = 6001
        private const val CHANNEL = "leo_find_it/scanner"
    }

    private var airTagScanner: AirTagScanner? = null
    private var nonAppleScanner: NonAppleTrackerScanner? = null
    private var channel: MethodChannel? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)

        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "startScan" -> {
                    if (!hasBlePermissions()) {
                        requestBlePermissions()
                        result.success(false)
                        return@setMethodCallHandler
                    }

                    if (!isLocationEnabled()) {
                        result.error(
                            "LOCATION_DISABLED",
                            "Location services must be enabled to scan for trackers",
                            null
                        )
                        return@setMethodCallHandler
                    }

                    initScannersIfNeeded()
                    airTagScanner?.start()
                    nonAppleScanner?.start()
                    result.success(true)
                }

                "stopScan" -> {
                    airTagScanner?.stop()
                    nonAppleScanner?.stop()
                    result.success(true)
                }

                else -> result.notImplemented()
            }
        }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)

        if (hasBlePermissions() && isLocationEnabled()) {
            initScannersIfNeeded()
        } else {
            requestBlePermissions()
        }
    }

    override fun onDestroy() {
        airTagScanner?.stop()
        nonAppleScanner?.stop()
        super.onDestroy()
    }

    private fun initScannersIfNeeded() {
        if (airTagScanner != null) return

        airTagScanner = AirTagScanner(this) { tracker ->
            sendToFlutter(tracker)
        }

        nonAppleScanner = NonAppleTrackerScanner(this) { tracker ->
            sendToFlutter(tracker)
        }
    }

    private fun hasBlePermissions(): Boolean =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.BLUETOOTH_SCAN
            ) == PackageManager.PERMISSION_GRANTED &&
                    ContextCompat.checkSelfPermission(
                        this, Manifest.permission.BLUETOOTH_CONNECT
                    ) == PackageManager.PERMISSION_GRANTED
        } else {
            ContextCompat.checkSelfPermission(
                this, Manifest.permission.ACCESS_FINE_LOCATION
            ) == PackageManager.PERMISSION_GRANTED
        }

    private fun requestBlePermissions() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(
                    Manifest.permission.BLUETOOTH_SCAN,
                    Manifest.permission.BLUETOOTH_CONNECT
                ),
                PERMISSION_REQUEST
            )
        } else {
            ActivityCompat.requestPermissions(
                this,
                arrayOf(Manifest.permission.ACCESS_FINE_LOCATION),
                PERMISSION_REQUEST
            )
        }
    }

    private fun isLocationEnabled(): Boolean {
        val lm = getSystemService(Context.LOCATION_SERVICE) as LocationManager
        return lm.isProviderEnabled(LocationManager.GPS_PROVIDER) ||
                lm.isProviderEnabled(LocationManager.NETWORK_PROVIDER)
    }

    private fun sendToFlutter(tracker: AirTagScanner.DetectedTracker) {
        val payload = mapOf(
            "id" to tracker.id,
            "logicalId" to tracker.logicalId,
            "address" to tracker.address,
            "mac" to (tracker.address ?: ""),
            "kind" to tracker.kind.name,
            "rssi" to tracker.rssi,
            "distanceMeters" to tracker.distanceMeters,
            "lastSeenMs" to tracker.lastSeenMs,
            "signature" to tracker.signature,
            "rawFrame" to tracker.rawFrame,
            "rotatingMacCount" to tracker.rotatingMacCount
        )

        channel?.invokeMethod("onDevice", payload)
    }
}
