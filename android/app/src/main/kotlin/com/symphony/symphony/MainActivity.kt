package com.symphony.symphony

import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.wifi.WifiManager
import android.os.Build
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : AudioServiceActivity() {
    private var pendingPermissionResult: MethodChannel.Result? = null

    /** Held while hosting a Jam so guests' discovery broadcasts arrive. */
    private var multicastLock: WifiManager.MulticastLock? = null

    /** Delivers symphony:// links (Jam invites) to Dart. */
    private var linksChannel: MethodChannel? = null

    /** The link the app was opened with, until Dart asks for it. */
    private var initialLink: String? = null

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
        initialLink = linkFrom(intent)
        linksChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, LINKS_CHANNEL).also {
            it.setMethodCallHandler { call, result ->
                when (call.method) {
                    "initialLink" -> {
                        result.success(initialLink)
                        initialLink = null
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // The audio service keeps the engine (and Dart) running when this
        // activity closes; a new activity opened by a link tells it directly.
        initialLink?.let { linksChannel?.invokeMethod("link", it) }
        // Mobile data or a metered hotspot: background downloads hold back.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NETWORK_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isMetered" -> result.success(
                        (applicationContext.getSystemService(Context.CONNECTIVITY_SERVICE) as ConnectivityManager)
                            .isActiveNetworkMetered
                    )
                    else -> result.notImplemented()
                }
            }
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

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        linkFrom(intent)?.let { linksChannel?.invokeMethod("link", it) }
    }

    private fun linkFrom(intent: Intent?): String? =
        intent?.takeIf { it.action == Intent.ACTION_VIEW }?.dataString?.takeIf { it.startsWith("symphony:") }

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
        private const val LINKS_CHANNEL = "com.symphony.symphony/links"
        private const val NETWORK_CHANNEL = "com.symphony.symphony/network"
        private const val POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
        private const val REQUEST_CODE = 0x5359
    }
}
