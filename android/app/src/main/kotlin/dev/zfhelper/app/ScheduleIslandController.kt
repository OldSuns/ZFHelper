package dev.zfhelper.app

import android.app.AlarmManager
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import org.json.JSONObject
import java.time.ZonedDateTime

private const val PREVIEW_DURATION_MILLIS = 120_000L
private val LEAD_MINUTES = setOf(0, 5, 10, 15, 30)

/** A second consumer of the widget snapshot; never owns another timetable cache. */
internal class ScheduleIslandController(private val context: Context) {
    private val preferences = context.getSharedPreferences("schedule_island", Context.MODE_PRIVATE)
    private val notifications = context.getSystemService(NotificationManager::class.java)
    private val alarms = context.getSystemService(AlarmManager::class.java)
    private var memoryFailure: String? = null

    private val enabled: Boolean get() = preferences.getBoolean("enabled", false)
    private val leadMinutes: Int
        get() = preferences.getInt("leadMinutes", 10).also {
            if (it !in LEAD_MINUTES) throw ScheduleIslandException("island_settings_invalid", "课前提醒时间无效，请重新设置")
        }

    fun configure(arguments: Any?, snapshot: ScheduleWidgetSnapshot?) {
        val settings = arguments as? Map<*, *>
            ?: throw ScheduleIslandException("island_settings_invalid", "缺少课程实况设置")
        val nextEnabled = settings["enabled"] as? Boolean
            ?: throw ScheduleIslandException("island_settings_invalid", "课程实况开关无效")
        val nextLead = settings["leadMinutes"] as? Int
        if (nextLead !in LEAD_MINUTES) throw ScheduleIslandException("island_settings_invalid", "课前提醒时间无效")
        removeLegacyMode()
        if (nextEnabled) requireLiveUpdates()
        save(preferences.edit().putBoolean("enabled", nextEnabled)
            .putInt("leadMinutes", nextLead!!).commit())
        if (!nextEnabled) stopPreview()
        reconcile(snapshot)
    }

    fun reconcile(snapshot: ScheduleWidgetSnapshot?, now: ZonedDateTime = ZonedDateTime.now(), forceTimers: Boolean = false) {
        removeLegacyMode()
        if (!enabled || snapshot?.status != "ready") {
            clearReminders()
            clearFailure()
            return
        }
        ensureChannel()
        if (!notificationsAllowed()) {
            clearReminders()
            clearFailure()
            return
        }
        requireLiveUpdates()
        val dismissed = dismissed(now.toInstant().toEpochMilli())
        val plan = ScheduleIslandPlan.create(snapshot, leadMinutes, dismissed.keys, now)
        // A transient display failure must not sever later course transitions.
        schedule(plan.nextBoundary)
        val desiredTags = plan.reminders.map { ISLAND_TAG_PREFIX + it.key }.toSet()
        val active = notifications.activeNotifications.filter { it.id == ISLAND_NOTIFICATION_ID }
        // Remove the old scope before publishing a newly selected account or term.
        active.filter { it.tag !in desiredTags }.forEach { notifications.cancel(it.tag, it.id) }
        for (reminder in plan.reminders) {
            val tag = ISLAND_TAG_PREFIX + reminder.key
            val previous = active.firstOrNull { it.tag == tag }?.notification
            val signature = ScheduleIslandNotification.signature(reminder)
            if (!forceTimers && previous?.extras?.getString(ISLAND_SIGNATURE) == signature) continue
            val notification = ScheduleIslandNotification.build(context, reminder, now.toInstant().toEpochMilli())
            notifications.notify(tag, ISLAND_NOTIFICATION_ID, notification)
        }
        clearFailure()
    }

    fun dismiss(intent: Intent, snapshot: ScheduleWidgetSnapshot?) {
        val now = ZonedDateTime.now()
        val nowMillis = now.toInstant().toEpochMilli()
        val deadline = intent.getLongExtra(ISLAND_DEADLINE, 0)
        // Android also sends deleteIntent for timeout expiry. That must advance the phase.
        val elapsedDeadline = intent.getLongExtra(ISLAND_ELAPSED_DEADLINE, 0)
        if (nowMillis >= deadline || SystemClock.elapsedRealtime() >= elapsedDeadline) return
        val key = intent.getStringExtra(ISLAND_KEY) ?: return
        val token = intent.getStringExtra(ISLAND_TOKEN) ?: return
        val current = ScheduleIslandPlan.create(snapshot, leadMinutes, emptySet(), now).reminders
            .firstOrNull { it.key == key && it.token == token } ?: return
        val dismissed = dismissed(nowMillis).toMutableMap()
        dismissed[key] = current.lessonEnd
        writeDismissed(dismissed)
    }

    fun restore(snapshot: ScheduleWidgetSnapshot?) {
        save(preferences.edit().remove("dismissed").commit())
        reconcile(snapshot)
    }

    fun preview() {
        removeLegacyMode()
        ensureChannel()
        if (!notificationsAllowed()) throw ScheduleIslandException("island_notifications_denied", "请先允许课程实况通知，再发送示例")
        requireLiveUpdates()
        val now = ZonedDateTime.now()
        val nowMillis = now.toInstant().toEpochMilli()
        val deadline = nowMillis + PREVIEW_DURATION_MILLIS
        val reminder = ScheduleIslandReminder(
            "preview", "preview", now.toLocalDate(), "示例课程", "2 分钟显示示例 · 到时自动移除",
            "教学楼 A101", ScheduleIslandPhase.IN_CLASS, deadline, deadline,
        )
        notifications.notify(ISLAND_PREVIEW_ID,
            ScheduleIslandNotification.build(context, reminder, nowMillis, preview = true))
        clearFailure()
    }

    fun stopPreview() { notifications.cancel(ISLAND_PREVIEW_ID) }

    fun invalidateSource(message: String) {
        clearReminders()
        recordFailure(ScheduleIslandException("island_snapshot_unavailable", message))
    }

    fun clearReminders() {
        clearCourseNotifications()
        schedule(null)
    }

    fun status(snapshot: ScheduleWidgetSnapshot?, sourceFailure: String? = null): Map<String, Any?> {
        ensureChannel()
        val now = ZonedDateTime.now()
        val hiddenKeys = dismissed(now.toInstant().toEpochMilli()).keys
        val plan = ScheduleIslandPlan.create(snapshot, leadMinutes, emptySet(), now)
        val active = notifications.activeNotifications.filter { it.id == ISLAND_NOTIFICATION_ID || it.id == ISLAND_PREVIEW_ID }
        val real = active.filter { it.id == ISLAND_NOTIFICATION_ID }
        val preview = active.firstOrNull { it.id == ISLAND_PREVIEW_ID }
        // Derive UI refresh timing from the actual notification, including after clock changes.
        val previewExpires = preview?.notification?.extras?.getLong(ISLAND_ELAPSED_DEADLINE)?.let {
            System.currentTimeMillis() + it - SystemClock.elapsedRealtime()
        }
        val activeKeys = real.mapNotNull { it.notification.extras.getString(ISLAND_KEY) }.toSet()
        val labels = plan.reminders.filter { it.key in activeKeys }.map { it.label }
        return mapOf(
            "enabled" to enabled, "leadMinutes" to leadMinutes,
            "androidVersion" to Build.VERSION.SDK_INT,
            "notificationsAllowed" to notificationsAllowed(),
            "channelSupportsLiveUpdates" to (notifications.getNotificationChannel(ISLAND_CHANNEL_ID).importance >
                NotificationManager.IMPORTANCE_MIN),
            "exactAlarmsAllowed" to alarms.canScheduleExactAlarms(),
            "liveUpdatesSupported" to (Build.VERSION.SDK_INT >= 36),
            "promotionAllowed" to (Build.VERSION.SDK_INT >= 36 && notifications.canPostPromotedNotifications()),
            "notificationVisible" to real.isNotEmpty(),
            "previewVisible" to (preview != null),
            "previewExpires" to previewExpires,
            "promoted" to (Build.VERSION.SDK_INT >= 36 && active.any {
                it.notification.flags and Notification.FLAG_PROMOTED_ONGOING != 0
            }),
            "hidden" to plan.reminders.any { it.key in hiddenKeys },
            "activeLabel" to labels.takeIf { it.isNotEmpty() }?.joinToString("\n"),
            "sourceLabel" to snapshot?.let { listOfNotNull(it.accountLabel, it.termLabel).joinToString(" · ").ifBlank { null } },
            "sourceNotice" to (sourceFailure ?: sourceNotice(snapshot, plan)),
            "nextUpdate" to preferences.getLong("nextUpdate", 0).takeIf { it > 0 },
            "failure" to (memoryFailure ?: preferences.getString("failure", null)),
        )
    }

    private fun sourceNotice(snapshot: ScheduleWidgetSnapshot?, plan: ScheduleIslandPlan): String? = when (snapshot?.status) {
        null -> "课表尚未同步，导入后会自动用于课程实况。可以先发送示例检查显示效果。"
        "noAccount" -> "还没有选择课表账号。可以先发送示例检查显示效果。"
        "noSchedule" -> "所选学期尚未导入课表。"
        "calendarMissing" -> "请先设置本学期第一周周一，课程实况才能对应到日期。"
        else -> if (plan.untimedLessons > 0) "有 ${plan.untimedLessons} 次待上课程的作息不完整，这些课程暂不发送提醒。" else null
    }

    private fun removeLegacyMode() {
        if (!preferences.contains("mode")) return
        clearReminders()
        stopPreview()
        // Remove the migration marker only after both old notification types are cleared.
        save(preferences.edit().remove("mode").commit())
    }

    private fun requireLiveUpdates() {
        if (Build.VERSION.SDK_INT < 36) {
            throw ScheduleIslandException("island_android_version", "Android 实况通知需要 Android 16 或更新版本")
        }
    }

    private fun ensureChannel() {
        notifications.createNotificationChannel(NotificationChannel(ISLAND_CHANNEL_ID, "课程实况", NotificationManager.IMPORTANCE_DEFAULT).apply {
            description = "课前、上课中与课间的课程倒计时"
            setSound(null, null)
            enableVibration(false)
        })
    }

    private fun notificationsAllowed(): Boolean = notifications.areNotificationsEnabled() &&
        notifications.getNotificationChannel(ISLAND_CHANNEL_ID)?.importance != NotificationManager.IMPORTANCE_NONE

    fun clearCourseNotifications() {
        notifications.activeNotifications.filter { it.id == ISLAND_NOTIFICATION_ID }
            .forEach { notifications.cancel(it.tag, it.id) }
    }

    private fun schedule(next: Long?) {
        val pending = PendingIntent.getBroadcast(context, 0,
            Intent(context, ScheduleIslandReceiver::class.java).setAction(ISLAND_BOUNDARY),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
        if (next == null) {
            alarms.cancel(pending)
            pending.cancel()
        } else if (alarms.canScheduleExactAlarms()) {
            alarms.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending)
        } else {
            // Settings reports this inexact mode explicitly; no permission is inferred from posting a notification.
            alarms.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, next, pending)
        }
        val saved = preferences.getLong("nextUpdate", 0)
        if (saved != (next ?: 0)) save(preferences.edit().putLong("nextUpdate", next ?: 0).commit())
    }

    private fun dismissed(now: Long): Map<String, Long> {
        val raw = preferences.getString("dismissed", null) ?: return emptyMap()
        val json = JSONObject(raw)
        val all = json.keys().asSequence().associateWith { key ->
            if (!key.matches(Regex("[0-9a-f]{64}")) || json.get(key) !is Number) {
                throw ScheduleIslandException("island_dismissal_invalid", "课程实况关闭记录无效，请点击恢复本节提醒")
            }
            json.getLong(key)
        }
        val current = all.filterValues { it > now }
        if (current.size != all.size) writeDismissed(current)
        return current
    }

    private fun writeDismissed(values: Map<String, Long>) {
        save(preferences.edit().putString("dismissed", JSONObject(values).toString()).commit())
    }

    private fun save(success: Boolean) {
        if (!success) throw ScheduleIslandException("island_settings_write", "课程实况状态未能保存，请检查本机存储并重试")
    }

    private fun clearFailure() {
        if (preferences.contains("failure")) save(preferences.edit().remove("failure").commit())
        memoryFailure = null
    }

    fun recordFailure(failure: ScheduleIslandException) {
        Log.e("ScheduleIsland", failure.code)
        memoryFailure = failure.message
        try {
            if (!preferences.edit().putString("failure", failure.message).commit()) {
                memoryFailure = "${failure.message}；错误状态未能保存"
                Log.e("ScheduleIsland", "island_failure_state_write")
            }
        } catch (error: RuntimeException) {
            memoryFailure = "${failure.message}；错误状态未能保存"
            Log.e("ScheduleIsland", "island_failure_state_write: ${error.javaClass.simpleName}")
        }
    }

    fun platformFailure(error: Exception): ScheduleIslandException {
        Log.e("ScheduleIsland", "island_platform_failed: ${error.javaClass.simpleName}")
        return ScheduleIslandException("island_platform_failed", "系统未能完成课程实况操作，请检查通知权限后重试")
    }
}
