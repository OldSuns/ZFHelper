package dev.zfhelper.app

import android.app.Notification
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Color
import android.graphics.Paint
import android.graphics.Typeface
import android.graphics.drawable.Icon
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.os.SystemClock

internal const val ISLAND_CHANNEL_ID = "schedule_live"
internal const val ISLAND_NOTIFICATION_ID = 47021
internal const val ISLAND_PREVIEW_ID = 47022
internal const val ISLAND_TAG_PREFIX = "schedule-course:"
internal const val ISLAND_SOURCE = "schedule_island_source"
internal const val ISLAND_KEY = "schedule_island_key"
internal const val ISLAND_TOKEN = "schedule_island_token"
internal const val ISLAND_DEADLINE = "schedule_island_deadline"
internal const val ISLAND_ELAPSED_DEADLINE = "schedule_island_elapsed_deadline"
internal const val ISLAND_SIGNATURE = "schedule_island_signature"
internal const val ISLAND_DISMISS = "dev.zfhelper.app.SCHEDULE_ISLAND_DISMISS"
internal const val ISLAND_BOUNDARY = "dev.zfhelper.app.SCHEDULE_ISLAND_BOUNDARY"

internal object ScheduleIslandNotification {
    // HyperOS tints the expanded badge with this color; keep system cards neutral.
    private const val ICON_COLOR = Color.DKGRAY

    fun signature(reminder: ScheduleIslandReminder): String =
        scheduleIslandKey(reminder.token, reminder.title, reminder.detail, reminder.location, ICON_COLOR.toString())

    fun build(
        context: Context,
        reminder: ScheduleIslandReminder,
        now: Long,
        preview: Boolean = false,
    ): Notification {
        val content = listOf(reminder.phase.label, reminder.location).filter(String::isNotBlank).joinToString(" · ")
        val elapsedDeadline = SystemClock.elapsedRealtime() + reminder.deadline - now
        val extras = Bundle().apply {
            putString(ISLAND_KEY, reminder.key)
            putString(ISLAND_TOKEN, reminder.token)
            putLong(ISLAND_DEADLINE, reminder.deadline)
            putLong(ISLAND_ELAPSED_DEADLINE, elapsedDeadline)
            putString(ISLAND_SIGNATURE, signature(reminder))
        }
        val builder = Notification.Builder(context, ISLAND_CHANNEL_ID)
            .setSmallIcon(textIcon(context, reminder.title)
                ?: Icon.createWithResource(context, R.drawable.ic_schedule_notification))
            .setContentTitle(reminder.title)
            .setContentText(content)
            .setSubText(reminder.phase.countdown)
            .setShortCriticalText(reminder.location)
            .setStyle(Notification.BigTextStyle().bigText("$content\n${reminder.detail}"))
            .setContentIntent(contentIntent(context, reminder, preview))
            .setCategory(Notification.CATEGORY_EVENT)
            .setColor(ICON_COLOR)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setWhen(reminder.deadline)
            .setShowWhen(true)
            .setUsesChronometer(true)
            .setChronometerCountDown(true)
            .setTimeoutAfter(reminder.deadline - now)
        if (!preview) {
            builder.setDeleteIntent(deleteIntent(context, reminder, elapsedDeadline))
        }

        if (Build.VERSION.SDK_INT < 36) {
            throw ScheduleIslandException("island_android_version", "Android 实况通知需要 Android 16 或更新版本")
        }
        // The public setter arrived in API 36.1; its documented extra also works on API 36.
        extras.putBoolean("android.requestPromotedOngoing", true)
        builder.addExtras(extras).setColorized(false)
        val modern = builder.build()
        if (modern.hasPromotableCharacteristics()) return modern
        // Initial Android 16 requires colorization; QPR1 instead requires the explicit opt-in above.
        val initialAndroid16 = builder.setColorized(true).build()
        if (initialAndroid16.hasPromotableCharacteristics()) return initialAndroid16
        throw ScheduleIslandException("island_not_promotable", "系统未接受实况通知格式，请检查系统更新后重试")
    }

    // HyperOS 岛的左侧槽位只展示通知图标；把课程名渲染成位图图标，左侧即可显示文字。
    private fun textIcon(context: Context, text: String): Icon? {
        if (text.isBlank()) return null
        return try {
            val density = context.resources.displayMetrics.density
            val densityDpi = context.resources.displayMetrics.densityDpi
            // 3 倍渲染后按 setDensity 缩显示尺寸，下采样保证清晰
            val oversample = 3f
            val fontPx = 16f * density
            val maxTextPx = 96f * density
            val padH = 6f * density
            val padV = 4f * density
            val measure = android.text.TextPaint().apply { isAntiAlias = true; textSize = fontPx }
            // 超出左侧可用宽度时尾部省略
            val label = android.text.TextUtils.ellipsize(
                text, measure, maxTextPx, android.text.TextUtils.TruncateAt.END,
            ).toString()
            val paint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
                textSize = fontPx * oversample
                color = Color.WHITE
                // 中文字形不随 DEFAULT_BOLD 加粗，需要合成假粗体
                flags = flags or Paint.FAKE_BOLD_TEXT_FLAG
                isSubpixelText = true
                isLinearText = true
            }
            val metrics = paint.fontMetrics
            val width = (paint.measureText(label) + padH * 2 * oversample).toInt()
            val height = ((metrics.descent - metrics.ascent) + padV * 2 * oversample).toInt()
            if (width <= 0 || height <= 0) return null
            val bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
            bitmap.density = (densityDpi * oversample).toInt()
            // 文字视觉中心对齐画布中心：baseline = (height - ascent - descent) / 2
            Canvas(bitmap).drawText(label, padH * oversample, (height - metrics.ascent - metrics.descent) / 2, paint)
            Icon.createWithBitmap(bitmap)
        } catch (_: RuntimeException) {
            null
        }
    }

    private fun contentIntent(context: Context, reminder: ScheduleIslandReminder, preview: Boolean): PendingIntent {
        val intent = Intent(context, MainActivity::class.java)
            .setFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or Intent.FLAG_ACTIVITY_SINGLE_TOP)
            .setData(Uri.parse("zfhelper://course-live/${if (preview) "preview" else reminder.key}"))
        if (!preview) {
            intent.putExtra(SCHEDULE_WIDGET_DATE, reminder.date.toString())
            intent.putExtra(ISLAND_SOURCE, reminder.sourceKey)
        }
        return PendingIntent.getActivity(context, 0, intent, PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
    }

    private fun deleteIntent(context: Context, reminder: ScheduleIslandReminder, elapsedDeadline: Long): PendingIntent = PendingIntent.getBroadcast(
        context, 0,
        Intent(context, ScheduleIslandReceiver::class.java).setAction(ISLAND_DISMISS)
            .setData(Uri.parse("zfhelper://course-dismiss/${reminder.token}/$elapsedDeadline"))
            .putExtra(ISLAND_KEY, reminder.key)
            .putExtra(ISLAND_TOKEN, reminder.token)
            .putExtra(ISLAND_DEADLINE, reminder.deadline)
            .putExtra(ISLAND_ELAPSED_DEADLINE, elapsedDeadline),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
}
