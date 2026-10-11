package com.symphony.symphony

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import com.yausername.youtubedl_android.YoutubeDL
import com.yausername.youtubedl_android.YoutubeDLRequest
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject
import java.net.URLEncoder
import java.util.concurrent.CompletableFuture
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.locks.ReentrantReadWriteLock
import kotlin.concurrent.read
import kotlin.concurrent.write

/**
 * Runs yt-dlp on the phone through youtubedl-android and serves channel
 * `com.symphony.symphony/ytdlp` (contract: `android_ytdlp_extractor.dart`).
 *
 * Process-wide: the library is initialised once, off the main thread, the
 * first time an engine attaches; later activities reuse the same state.
 * Every method replies on the main thread and never throws into Flutter.
 */
object YtDlpBridge {
    private const val TAG = "SymphonyYtDlp"
    private const val CHANNEL = "com.symphony.symphony/ytdlp"
    private const val PREFS = "symphony_ytdlp"
    private const val KEY_LAST_UPDATE = "last_update_ms"
    private const val UPDATE_INTERVAL_MS = 24L * 60 * 60 * 1000
    private const val EXTRACT_TIMEOUT_S = 90L
    private const val FORMAT = "ba[ext=m4a]/ba[acodec^=mp4a]/ba"
    private val VIDEO_ID = Regex("^[A-Za-z0-9_-]{11}$")

    private val workers = Executors.newCachedThreadPool { r ->
        Thread(r, "ytdlp-worker").apply { isDaemon = true }
    }
    private val watchdog = Executors.newSingleThreadScheduledExecutor { r ->
        Thread(r, "ytdlp-watchdog").apply { isDaemon = true }
    }
    private val mainHandler = Handler(Looper.getMainLooper())

    /** Extracts hold the read lock; an update swaps the yt-dlp file under the write lock. */
    private val binaryLock = ReentrantReadWriteLock()
    private val inFlight = ConcurrentHashMap<String, CompletableFuture<Map<String, Any?>>>()

    @Volatile private var appContext: Context? = null
    @Volatile private var initFuture: CompletableFuture<Boolean>? = null
    @Volatile private var updateFuture: CompletableFuture<String?>? = null

    fun attach(context: Context, messenger: BinaryMessenger) {
        ensureInit(context.applicationContext)
        MethodChannel(messenger, CHANNEL).setMethodCallHandler(::onMethodCall)
    }

    @Synchronized
    private fun ensureInit(context: Context): CompletableFuture<Boolean> {
        initFuture?.let { return it }
        appContext = context
        val future = CompletableFuture.supplyAsync({
            try {
                val started = System.currentTimeMillis()
                YoutubeDL.getInstance().init(context)
                Log.i(TAG, "yt-dlp ${YoutubeDL.getInstance().versionName(context)} ready in " +
                    "${System.currentTimeMillis() - started} ms")
                true
            } catch (e: Throwable) {
                Log.e(TAG, "youtubedl-android init failed", e)
                false
            }
        }, workers)
        // Publish before chaining: update() reads initFuture.
        initFuture = future
        future.thenAcceptAsync({ ok -> if (ok) maybeDailyUpdate(context) }, workers)
        return future
    }

    private fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isAvailable" -> initFuture!!.whenComplete { ok, _ -> reply { result.success(ok == true) } }
            "extract" -> {
                val videoId = call.argument<String>("videoId")
                if (videoId == null || !VIDEO_ID.matches(videoId)) {
                    result.error("bad_args", "extract needs an 11-character videoId, got $videoId", null)
                    return
                }
                extract(videoId, "https://www.youtube.com/watch?v=$videoId", listOf("--no-playlist"))
                    .whenComplete { info, err -> replyExtract(result, info, err) }
            }
            "searchSong" -> {
                // YouTube Music "songs" search: canonical album audio whose length
                // matches streaming services; extracts the top result in one run.
                val query = call.argument<String>("query")?.trim()
                if (query.isNullOrEmpty() || query.length > 200) {
                    result.error("bad_args", "searchSong needs a 1-200 character query", null)
                    return
                }
                val url = "https://music.youtube.com/search?q=${URLEncoder.encode(query, "UTF-8")}#songs"
                extract("song:$query", url, listOf("--playlist-items", "1"))
                    .whenComplete { info, err -> replyExtract(result, info, err) }
            }
            "update" -> update().whenComplete { version, err ->
                reply {
                    if (err != null) {
                        val cause = unwrap(err)
                        result.error("update_failed", cause.message ?: cause.toString(), null)
                    } else {
                        result.success(version)
                    }
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun replyExtract(result: MethodChannel.Result, info: Map<String, Any?>?, err: Throwable?) {
        reply {
            if (err != null) {
                val cause = unwrap(err)
                result.error("extract_failed", cause.message ?: cause.toString(), null)
            } else {
                result.success(info)
            }
        }
    }

    /** One yt-dlp run per key (video id or song search); concurrent callers share it. */
    private fun extract(key: String, url: String, extraOptions: List<String>): CompletableFuture<Map<String, Any?>> {
        inFlight[key]?.let { return it }
        val created = CompletableFuture<Map<String, Any?>>()
        val existing = inFlight.putIfAbsent(key, created)
        if (existing != null) return existing

        initFuture!!.thenAcceptAsync({ ok ->
            try {
                if (ok != true) throw IllegalStateException("youtubedl-android failed to initialise")
                created.complete(runExtract(key, url, extraOptions))
            } catch (e: Throwable) {
                Log.w(TAG, "extract $key failed: ${e.message}")
                created.completeExceptionally(e)
            } finally {
                inFlight.remove(key, created)
            }
        }, workers)
        return created
    }

    private fun runExtract(key: String, url: String, extraOptions: List<String>): Map<String, Any?> = binaryLock.read {
        val processId = "extract-${key.hashCode()}-${System.nanoTime()}"
        val request = YoutubeDLRequest(url).apply {
            addOption("-f", FORMAT)
            addOption("--dump-json")
            addOption("--no-warnings")
            var i = 0
            while (i < extraOptions.size) {
                val name = extraOptions[i]
                val value = extraOptions.getOrNull(i + 1)
                if (value != null && !value.startsWith("--")) {
                    addOption(name, value)
                    i += 2
                } else {
                    addOption(name)
                    i += 1
                }
            }
        }
        val kill = watchdog.schedule({
            Log.w(TAG, "extract $key exceeded ${EXTRACT_TIMEOUT_S}s; killing yt-dlp")
            YoutubeDL.getInstance().destroyProcessById(processId)
        }, EXTRACT_TIMEOUT_S, TimeUnit.SECONDS)
        val started = System.currentTimeMillis()
        val response = try {
            YoutubeDL.getInstance().execute(request, processId)
        } finally {
            kill.cancel(false)
        }
        Log.i(TAG, "extract $key took ${System.currentTimeMillis() - started} ms")
        parseDumpJson(response.out)
    }

    /** Maps yt-dlp's `--dump-json` output for the selected format to the channel reply. */
    private fun parseDumpJson(out: String): Map<String, Any?> {
        val line = out.lineSequence().map { it.trim() }.firstOrNull { it.startsWith("{") }
            ?: throw IllegalStateException("yt-dlp printed no JSON")
        val json = JSONObject(line)
        // A single-format pick puts the URL at top level; a merged pick would
        // list it under requested_formats, which "ba" never produces.
        val url = json.optString("url").takeIf { it.isNotEmpty() }
            ?: throw IllegalStateException("yt-dlp JSON has no url")
        val headers = json.optJSONObject("http_headers")?.let { h ->
            h.keys().asSequence().associateWith { h.optString(it) }
        }
        val duration = json.optDouble("duration")
        val abr = json.optDouble("abr").takeUnless { it.isNaN() } ?: json.optDouble("tbr")
        return mapOf(
            "url" to url,
            "id" to json.optString("id").ifEmpty { null },
            "title" to json.optString("title").ifEmpty { null },
            "channel" to (json.optString("channel").ifEmpty { json.optString("uploader") }).ifEmpty { null },
            "ext" to json.optString("ext").ifEmpty { "m4a" },
            "abr" to abr.takeUnless { it.isNaN() },
            "durationMs" to duration.takeUnless { it.isNaN() }?.let { (it * 1000).toLong() },
            "headers" to headers,
        )
    }

    /** Updates yt-dlp from the stable channel; resolves to the new version or null. */
    @Synchronized
    private fun update(): CompletableFuture<String?> {
        updateFuture?.takeUnless { it.isDone }?.let { return it }
        val context = appContext ?: return CompletableFuture.completedFuture(null)
        val future = initFuture!!.thenApplyAsync({ ok ->
            if (ok != true) throw IllegalStateException("youtubedl-android failed to initialise")
            binaryLock.write {
                val status = YoutubeDL.getInstance()
                    .updateYoutubeDL(context, YoutubeDL.UpdateChannel.STABLE)
                prefs(context).edit().putLong(KEY_LAST_UPDATE, System.currentTimeMillis()).apply()
                if (status == YoutubeDL.UpdateStatus.DONE) {
                    YoutubeDL.getInstance().versionName(context).also {
                        Log.i(TAG, "yt-dlp updated to $it")
                    }
                } else {
                    null
                }
            }
        }, workers)
        updateFuture = future
        return future
    }

    private fun maybeDailyUpdate(context: Context) {
        val last = prefs(context).getLong(KEY_LAST_UPDATE, 0L)
        if (System.currentTimeMillis() - last < UPDATE_INTERVAL_MS) return
        update().whenComplete { _, err ->
            if (err != null) Log.w(TAG, "background yt-dlp update failed: ${unwrap(err).message}")
        }
    }

    private fun prefs(context: Context) = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    private fun unwrap(e: Throwable): Throwable {
        var t = e
        while ((t is java.util.concurrent.CompletionException ||
                t is java.util.concurrent.ExecutionException) && t.cause != null) {
            t = t.cause!!
        }
        return t
    }

    private inline fun reply(crossinline block: () -> Unit) {
        mainHandler.post {
            try {
                block()
            } catch (e: Throwable) {
                // Reply already sent or engine detached; nothing to do.
                Log.w(TAG, "could not deliver channel reply", e)
            }
        }
    }
}
