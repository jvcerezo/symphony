package com.symphony.symphony

import android.content.Context
import android.content.pm.PackageManager
import android.net.wifi.WifiManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null

    /** Held while hosting a Jam so guests' discovery broadcasts arrive. */
    private var multicastLock: WifiManager.MulticastLock? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestPostNotifications" -> requestPostNotifications(result)
                    else -> result.notImplemented()
                }
            }
        YtDlpBridge.attach(this, flutterEngine.dartExecutor.binaryMessenger)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, JAM_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "acquireMulticastLock" -> {
                        val lock = multicastLock ?: (applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager)
                            .createMulticastLock("symphony-jam")
                            .also { it.setReferenceCounted(false); multicastLock = it }
                        lock.acquire()
                        result.success(null)
                    }
                    "releaseMulticastLock" -> {
                        multicastLock?.release()
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
    }

    override fun onDestroy() {
        multicastLock?.release()
        super.onDestroy()
    }

    /**
     * Android 13+ (API 33) requires a runtime grant for POST_NOTIFICATIONS,
     * otherwise the media playback notification is silently hidden.
     * Resolves to true when notifications may be shown.
     */
    private fun requestPostNotifications(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            checkSelfPermission(POST_NOTIFICATIONS) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (pendingPermissionResult != null) {
            result.error("in_progress", "A notification permission request is already running", null)
            return
        }
        pendingPermissionResult = result
        requestPermissions(arrayOf(POST_NOTIFICATIONS), REQUEST_CODE)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_CODE) return
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        pendingPermissionResult?.success(granted)
        pendingPermissionResult = null
    }

    companion object {
        private const val CHANNEL = "com.symphony.symphony/notifications"
        private const val JAM_CHANNEL = "com.symphony.symphony/jam"
        private const val POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
        private const val REQUEST_CODE = 0x5359
    }
}
