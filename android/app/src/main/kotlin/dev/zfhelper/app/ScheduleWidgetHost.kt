package dev.zfhelper.app

import android.app.AlarmManager
import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Intent
import android.os.Handler
import android.os.Looper
import android.util.Log
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.lang.ref.WeakReference
import java.time.ZonedDateTime
import java.util.concurrent.Executors

internal const val SCHEDULE_WIDGET_DATE = "schedule_widget_date"
internal const val SCHEDULE_WIDGET_REFRESH = "dev.zfhelper.app.SCHEDULE_WIDGET_REFRESH"
internal const val SCHEDULE_WIDGET_BOUNDARY = "dev.zfhelper.app.SCHEDULE_WIDGET_BOUNDARY"
private const val WIDGET_CHANNEL = "zfhelper/schedule_widget"
private const val UPDATE_WINDOW_MILLIS = 10 * 60 * 1000L

class ScheduleWidgetHost(private val application: ZfHelperApplication) : MethodChannel.MethodCallHandler {
    private val store = ScheduleWidgetStore(application)
    private val executor = Executors.newSingleThreadExecutor()
    private val handler = Handler(Looper.getMainLooper())
    private val manager = AppWidgetManager.getInstance(application)
    private val provider = ComponentName(application, ScheduleWidgetProvider::class.java)
    private var channel: MethodChannel? = null
    private var activity = WeakReference<MainActivity>(null)
    private var resumed = false
    private var dartReady = false
    private var pendingDate: String? = null
    private var launchSequence = 0L

    fun attachEngine(engine: FlutterEngine) {
        dartReady = false
        channel = MethodChannel(engine.dartExecutor.binaryMessenger, WIDGET_CHANNEL).also {
            it.setMethodCallHandler(this)
        }
    }

    fun activityResumed(current: MainActivity) {
        activity = WeakReference(current)
        resumed = true
        refreshInBackground()
    }

    fun activityPaused(current: MainActivity) {
        if (activity.get() === current) resumed = false
    }

    fun activityDestroyed(current: MainActivity) {
        if (activity.get() !== current) return
        resumed = false
        activity.clear()
    }

    fun receiveLaunch(intent: Intent) {
        val rawDate = intent.getStringExtra(SCHEDULE_WIDGET_DATE) ?: return
        // Each Activity intent is consumed once; another widget tap has a fresh intent.
        intent.removeExtra(SCHEDULE_WIDGET_DATE)
        val date = try {
            scheduleWidgetDate(rawDate).toString()
        } catch (_: ScheduleWidgetException) {
            Log.e("ScheduleWidget", "widget_launch_date_invalid")
            return
        }
        val sequence = ++launchSequence
        val currentChannel = channel
        if (!dartReady || currentChannel == null) {
            pendingDate = date
            return
        }
        currentChannel.invokeMethod("openSchedule", date, object : MethodChannel.Result {
            override fun success(result: Any?) = Unit

            override fun error(code: String, message: String?, details: Any?) = retainLaunch()

            override fun notImplemented() = retainLaunch()

            private fun retainLaunch() {
                if (sequence != launchSequence) return
                pendingDate = date
                dartReady = false
                Log.e("ScheduleWidget", "widget_launch_not_consumed")
            }
        })
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "capabilities" -> complete(result) {
                val snapshot = try {
                    store.read()
                } catch (failure: ScheduleWidgetException) {
                    showFailure(failure)
                    null
                }
                mapOf(
                    "supported" to true,
                    "canPin" to manager.isRequestPinAppWidgetSupported,
                    "count" to manager.getAppWidgetIds(provider).size,
                    "lastSync" to snapshot?.generatedAt,
                    "failure" to store.failure?.message,
                )
            }
            "publish" -> complete(result) {
                val snapshot = try {
                    val payload = (call.arguments as? Map<*, *>)?.get("payload") as? String
                        ?: throw ScheduleWidgetException("widget_payload_invalid", "缺少小组件课表数据")
                    val snapshot = ScheduleWidgetSnapshot.parse(payload)
                    store.write(payload)
                    store.clearFailure()
                    snapshot
                } catch (failure: RuntimeException) {
                    Log.e("ScheduleWidget", "widget_publish_failed: ${failure.javaClass.simpleName}")
                    throw ScheduleWidgetException("widget_write_failed", "小组件课表未能保存，请重新同步")
                }
                renderAndSchedule(snapshot)
                null
            }
            "requestPin" -> requestPin(result)
            "consumeLaunch" -> {
                dartReady = true
                val date = pendingDate
                pendingDate = null
                result.success(date)
            }
            else -> result.notImplemented()
        }
    }

    fun refreshInBackground(finished: () -> Unit = {}) {
        executor.execute {
            try {
                renderAndSchedule(store.read())
            } catch (failure: ScheduleWidgetException) {
                showFailure(failure)
            } catch (failure: RuntimeException) {
                showFailure(platformFailure(failure))
            } finally {
                finished()
            }
        }
    }

    private fun complete(result: MethodChannel.Result, operation: () -> Any?) {
        executor.execute {
            try {
                val value = operation()
                handler.post { result.success(value) }
            } catch (failure: ScheduleWidgetException) {
                showFailure(failure)
                handler.post { result.error(failure.code, failure.message, null) }
            } catch (failure: RuntimeException) {
                val problem = platformFailure(failure)
                showFailure(problem)
                handler.post { result.error(problem.code, problem.message, null) }
            }
        }
    }

    private fun requestPin(result: MethodChannel.Result) {
        if (!resumed || activity.get() == null) {
            result.error("widget_activity_required", "请在应用前台添加桌面小组件", null)
            return
        }
        try {
            result.success(
                manager.isRequestPinAppWidgetSupported && manager.requestPinAppWidget(provider, null, null),
            )
        } catch (_: IllegalStateException) {
            result.error("widget_pin_unavailable", "当前无法添加小组件，请解锁设备后重试", null)
        } catch (_: SecurityException) {
            result.error("widget_pin_restricted", "系统限制了添加桌面小组件", null)
        } catch (failure: RuntimeException) {
            Log.e("ScheduleWidget", "widget_pin_failed: ${failure.javaClass.simpleName}")
            result.error("widget_pin_failed", "系统未能打开小组件添加窗口，请重试", null)
        }
    }

    private fun renderAndSchedule(snapshot: ScheduleWidgetSnapshot?) {
        val now = ZonedDateTime.now()
        val ids = manager.getAppWidgetIds(provider)
        val failure = store.failure
        val blockingFailure = failure?.takeIf { it.kind == ScheduleWidgetFailureKind.SNAPSHOT }
        val visibleSnapshot = if (blockingFailure == null) snapshot else null
        for (id in ids) {
            manager.updateAppWidget(
                id,
                ScheduleWidgetRenderer.render(application, id, visibleSnapshot, blockingFailure?.message, now),
            )
        }
        scheduleNextUpdate(visibleSnapshot, now, ids.isNotEmpty())
        if (failure != null && blockingFailure == null) store.clearFailure()
    }

    private fun scheduleNextUpdate(
        snapshot: ScheduleWidgetSnapshot?,
        now: ZonedDateTime,
        hasWidgets: Boolean,
    ) {
        val alarm = application.getSystemService(AlarmManager::class.java)
        val intent = Intent(application, ScheduleWidgetProvider::class.java).setAction(SCHEDULE_WIDGET_BOUNDARY)
        val pending = PendingIntent.getBroadcast(
            application, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        if (!hasWidgets) {
            alarm.cancel(pending)
            pending.cancel()
            return
        }
        val today = now.toLocalDate()
        val startOfDay = today.atStartOfDay()
        var next = today.plusDays(1).atStartOfDay(now.zone)
        snapshot?.days?.firstOrNull { it.date == today }?.lessons?.forEach { lesson ->
            lesson.periods.forEach { period ->
                for (minutes in listOf(period.start, period.end)) {
                    val boundary = startOfDay.plusMinutes(minutes.toLong()).atZone(now.zone)
                    if (boundary > now && boundary < next) next = boundary
                }
            }
        }
        // Widgets do not need exact alarms or a wake-up while the screen is off.
        alarm.setWindow(AlarmManager.RTC, next.toInstant().toEpochMilli(), UPDATE_WINDOW_MILLIS, pending)
    }

    private fun showFailure(failure: ScheduleWidgetException) {
        Log.e("ScheduleWidget", failure.code)
        store.recordFailure(failure)
        try {
            val now = ZonedDateTime.now()
            val ids = manager.getAppWidgetIds(provider)
            for (id in ids) {
                manager.updateAppWidget(id, ScheduleWidgetRenderer.render(application, id, null, failure.message, now))
            }
            scheduleNextUpdate(null, now, ids.isNotEmpty())
        } catch (renderFailure: RuntimeException) {
            // Keep the explicit persisted failure available to Flutter even if the host rejects RemoteViews.
            Log.e("ScheduleWidget", "widget_error_render_failed: ${renderFailure.javaClass.simpleName}")
        }
    }

    private fun platformFailure(failure: RuntimeException): ScheduleWidgetException {
        Log.e("ScheduleWidget", "widget_platform_failed: ${failure.javaClass.simpleName}")
        return ScheduleWidgetException(
            "widget_platform_failed", "系统未能显示小组件，点击刷新重试", ScheduleWidgetFailureKind.DISPLAY,
        )
    }
}
