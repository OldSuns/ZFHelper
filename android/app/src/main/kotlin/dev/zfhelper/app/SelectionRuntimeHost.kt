package dev.zfhelper.app

import android.Manifest
import android.app.ForegroundServiceStartNotAllowedException
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Handler
import android.os.Looper
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference

internal const val SELECTION_NOTIFICATION_CHANNEL = "selection_running"
internal const val SELECTION_NOTIFICATION_PERMISSION_REQUEST = 4817
private const val START_ACK_TIMEOUT_MS = 8_000L

class SelectionRuntimeHost(private val application: ZfHelperApplication) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {
    private val handler = Handler(Looper.getMainLooper())
    private val notifications = requireNotNull(
        application.getSystemService(NotificationManager::class.java),
    )
    private var activity = WeakReference<MainActivity>(null)
    private var activityResumed = false
    private var eventSink: EventChannel.EventSink? = null
    private var interruption: Map<String, Any?>? = null
    private var service: SelectionForegroundService? = null
    private var requestedCount = 0
    private var startResult: MethodChannel.Result? = null
    private var permissionResult: MethodChannel.Result? = null
    private var permissionFinished = false
    private val startTimeout = Runnable {
        failStart("runtime_start_timeout", "后台运行宿主启动超时，捡漏未开始")
    }

    init {
        notifications.createNotificationChannel(
            NotificationChannel(
                SELECTION_NOTIFICATION_CHANNEL,
                "捡漏运行状态",
                NotificationManager.IMPORTANCE_LOW,
            ).apply { description = "查看手动捡漏运行状态，或停止正在运行的捡漏" },
        )
    }

    fun attachEngine(engine: FlutterEngine) {
        val messenger = engine.dartExecutor.binaryMessenger
        MethodChannel(messenger, "zfhelper/selection_runtime").setMethodCallHandler(this)
        EventChannel(messenger, "zfhelper/selection_runtime/events").setStreamHandler(this)
    }

    fun activityResumed(current: MainActivity) {
        activity = WeakReference(current)
        activityResumed = true
        completePermissionRequest()
        if (service != null && !notificationsGranted()) {
            interrupt("runtimeStopped", "运行通知已关闭，捡漏已停止；请在系统设置中允许通知")
        }
        emitCapabilitiesChanged()
    }

    fun activityPaused(current: MainActivity) {
        if (activity.get() !== current) return
        activityResumed = false
        emitCapabilitiesChanged()
    }

    fun activityDestroyed(current: MainActivity) {
        if (activity.get() !== current) return
        activity.clear()
        activityResumed = false
        if (current.isFinishing) {
            permissionResult?.error("permission_interrupted", "通知授权已中断，请重新操作", null)
            permissionResult = null
            permissionFinished = false
        }
    }

    fun notificationPermissionResult() {
        permissionFinished = true
        completePermissionRequest()
        emitCapabilitiesChanged()
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> result.success(capabilities())
            "prepare" -> prepare(result)
            "sync" -> {
                val count = (call.arguments as? Map<*, *>)?.get("activeWorkCount")
                if (count !is Int || count < 0) {
                    result.error("invalid_work_count", "捡漏运行数量无效", null)
                    return
                }
                sync(count, result)
            }
            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, events: EventChannel.EventSink) {
        eventSink = events
        interruption?.let(events::success)
        emitCapabilitiesChanged()
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun notificationsGranted(): Boolean =
        application.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED &&
            notifications.areNotificationsEnabled() &&
            notifications.getNotificationChannel(SELECTION_NOTIFICATION_CHANNEL)?.importance !=
            NotificationManager.IMPORTANCE_NONE

    private fun capabilities(): Map<String, Any?> {
        val granted = notificationsGranted()
        val reason = when {
            interruption != null -> interruption?.get("reason") as String?
            !granted -> "请允许捡漏运行通知，以便在后台查看状态并随时停止"
            !activityResumed && service == null -> "请在软件前台手动启动捡漏"
            else -> null
        }
        return mapOf(
            "mode" to "androidForegroundService",
            "notificationsGranted" to granted,
            "running" to (service != null),
            "canStart" to (reason == null),
            "reason" to reason,
        )
    }

    private fun prepare(result: MethodChannel.Result) {
        val current = activity.get()
        if (current == null || !activityResumed) {
            result.error("activity_required", "请在软件前台允许通知", null)
            return
        }
        if (permissionResult != null) {
            result.error("permission_pending", "正在等待通知授权", null)
            return
        }
        if (application.checkSelfPermission(Manifest.permission.POST_NOTIFICATIONS) ==
            PackageManager.PERMISSION_GRANTED
        ) {
            result.success(capabilities())
            return
        }
        permissionResult = result
        permissionFinished = false
        current.requestPermissions(
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            SELECTION_NOTIFICATION_PERMISSION_REQUEST,
        )
    }

    private fun completePermissionRequest() {
        if (!permissionFinished || !activityResumed) return
        val pending = permissionResult
        permissionResult = null
        permissionFinished = false
        pending?.success(capabilities())
    }

    private fun sync(count: Int, result: MethodChannel.Result) {
        if (count == 0) {
            requestedCount = 0
            completeStartError("runtime_stopped", "捡漏已停止")
            stopService()
            interruption = null
            result.success(null)
            emitCapabilitiesChanged()
            return
        }
        val state = capabilities()
        if (state["canStart"] != true) {
            result.error("runtime_unavailable", state["reason"] as String?, null)
            return
        }
        if (startResult != null) {
            result.error("runtime_start_pending", "后台运行宿主正在启动", null)
            return
        }
        requestedCount = count
        val running = service
        try {
            if (running != null) {
                running.updateWorkCount(count)
                result.success(null)
                return
            }
            startResult = result
            handler.postDelayed(startTimeout, START_ACK_TIMEOUT_MS)
            val started = application.startForegroundService(
                Intent(application, SelectionForegroundService::class.java),
            )
            if (started == null) failStart("runtime_unavailable", "系统未启动后台运行宿主")
        } catch (_: ForegroundServiceStartNotAllowedException) {
            startResult = result
            failStart("foreground_service_not_allowed", "Android 限制了后台运行，请返回软件前台后重试")
        } catch (_: SecurityException) {
            startResult = result
            failStart("foreground_service_permission", "系统未允许后台运行，请检查应用权限")
        } catch (_: RuntimeException) {
            startResult = result
            failStart("foreground_service_failed", "后台运行宿主启动或更新失败，捡漏已停止")
        }
    }

    fun requestedWorkCount(): Int = requestedCount

    fun serviceStarted(running: SelectionForegroundService) {
        if (requestedCount == 0 || interruption != null) {
            running.stopFromHost()
            return
        }
        service = running
        handler.removeCallbacks(startTimeout)
        val pending = startResult
        startResult = null
        pending?.success(null)
        emitCapabilitiesChanged()
    }

    fun serviceFailed(code: String, message: String) {
        failStart(code, message)
    }

    fun stopFromNotification() {
        interrupt("stopRequested", "已从通知停止捡漏")
    }

    fun serviceTimedOut() {
        // Android 15 gives dataSync services six background hours per 24 hours.
        // Stop immediately; the Dart owner must persist an interrupted state.
        interrupt("runtimeStopped", "Android 后台同步时限已到，捡漏已停止；返回软件后可手动重新开始")
    }

    fun serviceDestroyed(destroyed: SelectionForegroundService) {
        if (service !== destroyed) return
        service = null
        if (requestedCount > 0) {
            interrupt("runtimeStopped", "后台运行宿主已被系统停止，捡漏已中断")
        }
    }

    private fun failStart(code: String, message: String) {
        completeStartError(code, message)
        interrupt("runtimeStopped", message)
    }

    private fun completeStartError(code: String, message: String) {
        handler.removeCallbacks(startTimeout)
        val pending = startResult
        startResult = null
        pending?.error(code, message, null)
    }

    private fun interrupt(kind: String, message: String) {
        requestedCount = 0
        completeStartError("runtime_stopped", message)
        stopService()
        interruption = mapOf("kind" to kind, "reason" to message)
        eventSink?.success(interruption)
        emitCapabilitiesChanged()
    }

    private fun stopService() {
        val running = service
        service = null
        running?.stopFromHost()
        application.stopService(Intent(application, SelectionForegroundService::class.java))
    }

    private fun emitCapabilitiesChanged() {
        eventSink?.success(mapOf("kind" to "capabilitiesChanged", "reason" to null))
    }
}
