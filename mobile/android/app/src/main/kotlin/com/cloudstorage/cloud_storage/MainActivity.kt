package com.cloudstorage.cloud_storage

import android.app.Activity
import android.app.DownloadManager
import android.os.Environment
import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.content.pm.ActivityInfo
import android.content.pm.PackageManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import org.json.JSONObject

/**
 * UPI Intent payments.
 *
 * The result handler lives here, at activity level, so the UPI app's answer is
 * caught even when Android killed our process while the UPI app was open (the
 * activity is recreated and onActivityResult is delivered to it). The order id
 * is saved before the UPI app opens and the raw answer is saved the moment it
 * arrives; Dart sends it to the server and only then deletes it (see
 * lib/services/payments.dart).
 */
class MainActivity : FlutterActivity() {
    private var channel: MethodChannel? = null
    private var pendingNotify: MethodChannel.Result? = null
    private var notifyChannel: MethodChannel? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        val d = intent.getStringExtra(EXTRA_PUSH) ?: return
        intent.removeExtra(EXTRA_PUSH)
        notifyChannel?.invokeMethod("tapped", d)
    }

    private fun showPush(title: String, body: String, image: String?, data: String) {
        if (title.isEmpty()) return
        Thread {
            // Optional picture (https, up to ~1.5 MB); the text shows without it.
            val picture = try {
                if (image != null && image.startsWith("https://")) {
                    val c = java.net.URL(image).openConnection() as java.net.HttpURLConnection
                    c.connectTimeout = 5000
                    c.readTimeout = 5000
                    c.inputStream.use { input ->
                        val bytes = input.readBytes()
                        if (bytes.size <= 1_600_000) android.graphics.BitmapFactory.decodeByteArray(bytes, 0, bytes.size) else null
                    }
                } else null
            } catch (e: Exception) {
                null
            }
            val open = Intent(this, MainActivity::class.java)
                .putExtra(EXTRA_PUSH, data)
                .addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            val id = (System.currentTimeMillis() and 0x7fffffff).toInt()
            val tap = android.app.PendingIntent.getActivity(
                this, id, open,
                android.app.PendingIntent.FLAG_UPDATE_CURRENT or android.app.PendingIntent.FLAG_IMMUTABLE,
            )
            @Suppress("DEPRECATION")
            val b = if (Build.VERSION.SDK_INT >= 26) {
                android.app.Notification.Builder(this, "flixvault_updates")
            } else {
                android.app.Notification.Builder(this).setPriority(android.app.Notification.PRIORITY_HIGH)
            }
            b.setSmallIcon(R.drawable.ic_stat_notify)
                .setColor(0xFFFF7A1A.toInt())
                .setContentTitle(title)
                .setAutoCancel(true)
                .setContentIntent(tap)
            if (body.isNotEmpty()) b.setContentText(body)
            if (picture != null) {
                b.setLargeIcon(picture)
                b.setStyle(android.app.Notification.BigPictureStyle().bigPicture(picture).setSummaryText(body))
            } else if (body.isNotEmpty()) {
                b.setStyle(android.app.Notification.BigTextStyle().bigText(body))
            }
            try {
                val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
                nm.notify(id, b.build())
            } catch (e: Exception) {
                // notifications turned off for the app
            }
        }.start()
    }

    private fun notifyStatus(): String {
        val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
        val on = if (Build.VERSION.SDK_INT >= 24) nm.areNotificationsEnabled() else true
        return if (on) "allowed" else "denied"
    }

    override fun onRequestPermissionsResult(requestCode: Int, permissions: Array<out String>, grantResults: IntArray) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == REQUEST_NOTIFY) {
            pendingNotify?.success(notifyStatus())
            pendingNotify = null
        }
    }

    private val store get() = getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    override fun onCreate(savedInstanceState: android.os.Bundle?) {
        super.onCreate(savedInstanceState)
        // Channel for push messages (new releases, offers, payment updates):
        // high importance so they pop up at the top of the screen.
        if (Build.VERSION.SDK_INT >= 26) {
            val nm = getSystemService(Context.NOTIFICATION_SERVICE) as android.app.NotificationManager
            nm.createNotificationChannel(
                android.app.NotificationChannel(
                    "flixvault_updates",
                    "New releases & offers",
                    android.app.NotificationManager.IMPORTANCE_HIGH,
                ),
            )
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).apply {
            setMethodCallHandler { call, result ->
                when (call.method) {
                    "launch" -> {
                        val orderId = call.argument<String>("orderId")
                        val uri = call.argument<String>("uri")
                        if (orderId.isNullOrEmpty() || uri.isNullOrEmpty()) {
                            result.error("BAD_ARGS", "orderId and uri are required", null)
                        } else {
                            launch(orderId, uri, result)
                        }
                    }
                    "pending" -> result.success(pendingAnswers())
                    "launchedOrder" -> result.success(store.getString(KEY_LAUNCHED, null))
                    "clear" -> {
                        val orderId = call.argument<String>("orderId") ?: ""
                        removeAnswer(orderId)
                        result.success(null)
                    }
                    else -> result.notImplemented()
                }
            }
        }
        // Notification permission: Android 13+ shows its Allow / Don't allow
        // question; older versions allow notifications unless turned off.
        notifyChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, NOTIFY_CHANNEL)
        notifyChannel!!.setMethodCallHandler { call, result ->
                when (call.method) {
                    "status" -> result.success(notifyStatus())
                    // A push that arrives while the app is open: Android shows
                    // nothing by itself, so show it in the notification bar.
                    "show" -> {
                        showPush(
                            call.argument<String>("title") ?: "",
                            call.argument<String>("body") ?: "",
                            call.argument<String>("image"),
                            call.argument<String>("data") ?: "{}",
                        )
                        result.success(true)
                    }
                    // Tap on such a notification that (re)started the app.
                    "initialTap" -> {
                        val d = intent?.getStringExtra(EXTRA_PUSH)
                        intent?.removeExtra(EXTRA_PUSH)
                        result.success(d)
                    }
                    "request" -> {
                        if (Build.VERSION.SDK_INT >= 33 &&
                            checkSelfPermission(POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
                        ) {
                            pendingNotify?.success(notifyStatus())
                            pendingNotify = result
                            requestPermissions(arrayOf(POST_NOTIFICATIONS), REQUEST_NOTIFY)
                        } else {
                            result.success(notifyStatus())
                        }
                    }
                    else -> result.notImplemented()
                }
            }
        // Downloads (premium): Android's download manager saves the file to
        // Downloads/Flixvault and shows a progress notification.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DOWNLOAD_CHANNEL)
            .setMethodCallHandler { call, result ->
                val url = call.argument<String>("url")
                val name = call.argument<String>("name")
                if (call.method != "download" || url.isNullOrEmpty() || name.isNullOrEmpty()) {
                    result.error("BAD_ARGS", "url and name are required", null)
                    return@setMethodCallHandler
                }
                try {
                    val request = DownloadManager.Request(Uri.parse(url))
                        .setTitle(name)
                        .setDescription("Flixvault")
                        .setNotificationVisibility(DownloadManager.Request.VISIBILITY_VISIBLE_NOTIFY_COMPLETED)
                    call.argument<String>("mime")?.let { request.setMimeType(it) }
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                        request.setDestinationInExternalPublicDir(Environment.DIRECTORY_DOWNLOADS, "Flixvault/$name")
                    } else {
                        // Android 9 and older: app folder, no storage permission needed.
                        request.setDestinationInExternalFilesDir(this, Environment.DIRECTORY_DOWNLOADS, name)
                    }
                    val dm = getSystemService(Context.DOWNLOAD_SERVICE) as DownloadManager
                    result.success(dm.enqueue(request))
                } catch (e: Exception) {
                    result.error("DOWNLOAD_FAILED", e.message, null)
                }
            }
        // Google Play alternative billing (Play build only; a no-op elsewhere).
        PlayBillingChannel.register(flutterEngine, this)
        // Video player rotation (separate from payments): "sensor" follows the
        // phone's tilt like MX Player / VLC, even with auto-rotate off.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREEN_CHANNEL)
            .setMethodCallHandler { call, result ->
                requestedOrientation = when (call.method) {
                    "sensor" -> ActivityInfo.SCREEN_ORIENTATION_FULL_SENSOR
                    "landscape" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_LANDSCAPE
                    "portrait" -> ActivityInfo.SCREEN_ORIENTATION_SENSOR_PORTRAIT
                    else -> ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED
                }
                result.success(null)
            }
    }

    private fun launch(orderId: String, uri: String, result: MethodChannel.Result) {
        val intent = Intent(Intent.ACTION_VIEW, Uri.parse(uri))
        // Some phones (MIUI/ColorOS, work profiles, package-visibility rules)
        // return an empty list here even when UPI apps are installed, so the
        // list only decides between a chooser and a direct launch. Only Android
        // itself saying "no app can open this" counts as "no UPI app".
        val apps = try {
            if (Build.VERSION.SDK_INT >= 33) {
                packageManager.queryIntentActivities(
                    intent, PackageManager.ResolveInfoFlags.of(PackageManager.MATCH_ALL.toLong())
                )
            } else {
                @Suppress("DEPRECATION")
                packageManager.queryIntentActivities(intent, PackageManager.MATCH_ALL)
            }
        } catch (e: Exception) {
            emptyList()
        }
        // Persist the order id BEFORE leaving the app.
        store.edit().putString(KEY_LAUNCHED, orderId).commit()
        try {
            val target = if (apps.size > 1) Intent.createChooser(intent, "Pay with") else intent
            startActivityForResult(target, REQUEST_UPI)
            result.success(true)
        } catch (e: ActivityNotFoundException) {
            store.edit().remove(KEY_LAUNCHED).commit()
            result.error("NO_UPI_APP", e.message, null)
        } catch (e: Exception) {
            store.edit().remove(KEY_LAUNCHED).commit()
            result.error("LAUNCH_FAILED", e.toString(), null)
        }
    }

    @Deprecated("Activity result API is not available to FlutterActivity")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (requestCode == REQUEST_UPI) {
            val orderId = store.getString(KEY_LAUNCHED, null)
            if (orderId != null) {
                saveAnswer(orderId, rawAnswer(data))
                store.edit().remove(KEY_LAUNCHED).commit()
                // If Flutter is running, tell it to send the answer now; otherwise
                // it is picked up from storage when the app starts.
                channel?.invokeMethod("answer", orderId)
            }
            return
        }
        @Suppress("DEPRECATION")
        super.onActivityResult(requestCode, resultCode, data)
    }

    /** "response" extra, else any extra containing "Status=", else Status=NO_RESPONSE. */
    private fun rawAnswer(data: Intent?): String {
        val extras = data?.extras ?: return "Status=NO_RESPONSE"
        data.getStringExtra("response")?.takeIf { it.isNotBlank() }?.let { return it }
        for (key in extras.keySet()) {
            @Suppress("DEPRECATION")
            val value = extras.get(key)?.toString() ?: continue
            if (value.contains("Status=", ignoreCase = true)) return value
        }
        return "Status=NO_RESPONSE"
    }

    private fun answers(): JSONObject =
        try { JSONObject(store.getString(KEY_ANSWERS, "{}") ?: "{}") } catch (e: Exception) { JSONObject() }

    @Synchronized
    private fun saveAnswer(orderId: String, raw: String) {
        val all = answers()
        all.put(orderId, JSONObject().put("raw", raw).put("at", System.currentTimeMillis()))
        store.edit().putString(KEY_ANSWERS, all.toString()).commit()
    }

    @Synchronized
    private fun removeAnswer(orderId: String) {
        val all = answers()
        all.remove(orderId)
        store.edit().putString(KEY_ANSWERS, all.toString()).commit()
    }

    /** {orderId: {"raw": "...", "at": millis}} as a JSON string. */
    private fun pendingAnswers(): String = answers().toString()

    companion object {
        private const val CHANNEL = "cloudstorage/upi"
        private const val SCREEN_CHANNEL = "cloudstorage/screen"
        private const val DOWNLOAD_CHANNEL = "cloudstorage/download"
        private const val NOTIFY_CHANNEL = "cloudstorage/notify"
        private const val POST_NOTIFICATIONS = "android.permission.POST_NOTIFICATIONS"
        private const val REQUEST_NOTIFY = 7302
        private const val EXTRA_PUSH = "flixvault_push"
        private const val PREFS = "upi_payments"
        private const val KEY_LAUNCHED = "launched_order"
        private const val KEY_ANSWERS = "answers"
        private const val REQUEST_UPI = 7301
    }
}
