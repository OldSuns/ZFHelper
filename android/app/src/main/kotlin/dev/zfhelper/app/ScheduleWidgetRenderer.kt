package dev.zfhelper.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.RemoteViews
import androidx.core.graphics.ColorUtils
import java.time.LocalDate
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

internal const val SCHEDULE_WIDGET_UPCOMING_MINUTES = 30

internal data class ScheduleWidgetListState(
    val source: ScheduleWidgetSource?,
    val date: LocalDate,
    val lessons: List<ScheduleWidgetLesson>,
)

internal data class ScheduleWidgetRendering(
    val views: RemoteViews,
    val listState: ScheduleWidgetListState?,
)

internal object ScheduleWidgetRenderer {
    private val dateFormat = DateTimeFormatter.ofPattern("M月d日 EEE", Locale.SIMPLIFIED_CHINESE)
    private val shortDateFormat = DateTimeFormatter.ofPattern("M/d EEE", Locale.SIMPLIFIED_CHINESE)

    fun render(
        context: Context,
        widgetId: Int,
        snapshot: ScheduleWidgetSnapshot?,
        failure: String?,
        now: ZonedDateTime,
        savedTheme: ScheduleWidgetTheme?,
        settings: ScheduleWidgetSettings = ScheduleWidgetSettings.defaults,
        previousListState: ScheduleWidgetListState? = null,
    ): ScheduleWidgetRendering {
        val today = now.toLocalDate()
        val frame = WidgetFrame(
            snapshot,
            snapshot?.days?.firstOrNull { it.date == today },
            focus(snapshot, failure, now, settings),
            colors(context, snapshot, savedTheme),
            now,
            settings,
        )
        val listDay = snapshot?.days?.firstOrNull { day ->
            day.date == frame.focus.date && day.lessons.any { it.id == frame.focus.lessonId }
        }
        val listState = listDay?.let { day ->
            ScheduleWidgetListState(snapshot?.source, day.date, listLessons(day, frame))
        }
        val sizing = ScheduleWidgetSizing(context)
        val countdownWidth = frame.focus.countdown?.let { sizing.countdownWidth(frame.focus.title, it) }
        return ScheduleWidgetRendering(
            RemoteViews(
                sizing.variants(countdownWidth).associate { variant ->
                    variant.size to focusLayout(context, widgetId, variant, sizing, frame, listState != previousListState)
                },
            ),
            listState,
        )
    }

    private fun focusLayout(
        context: Context,
        widgetId: Int,
        variant: ScheduleWidgetLayout,
        sizing: ScheduleWidgetSizing,
        frame: WidgetFrame,
        resetScroll: Boolean,
    ): RemoteViews {
        val (snapshot, _, focus, colors, now, _) = frame
        val views = RemoteViews(context.packageName, R.layout.schedule_widget)
        val listDay = if (variant.style == ScheduleWidgetStyle.TODAY_LIST) {
            snapshot?.days?.firstOrNull { day ->
                day.date == focus.date && day.lessons.any { it.id == focus.lessonId }
            }
        } else {
            null
        }
        val showList = listDay != null
        val strip = variant.style == ScheduleWidgetStyle.NEXT
        val padding = sizing.pixels(sizing.padding)
        val verticalPadding = sizing.pixels(
            when {
                showList -> sizing.padding
                strip -> sizing.compactPadding
                else -> sizing.cardPadding
            },
        )
        views.setViewPadding(R.id.schedule_widget_root, padding, verticalPadding, padding, verticalPadding)
        views.visible(R.id.schedule_widget_header, showList)
        views.visible(R.id.schedule_widget_list, showList)
        views.visible(R.id.schedule_widget_focus, !showList)
        bindFocus(views, frame, variant, sizing, strip, showList)
        views.tintBackground(R.id.schedule_widget_root, colors.surface)
        val headerDate = listDay?.date ?: focus.date
        val headerDay = snapshot?.days?.firstOrNull { it.date == headerDate }
        val dateLabel = headerDate.format(shortDateFormat)
        views.setTextViewText(R.id.schedule_widget_date, dateLabel)
        val summary = listOfNotNull(
            headerDay?.week?.let { "第 $it 周" },
            headerDay?.lessons?.size?.let { "$it 门课" },
            "按节次".takeIf { headerDay?.byPeriod == true },
        ).joinToString(" · ")
        views.setTextViewText(R.id.schedule_widget_context, summary)
        views.setContentDescription(
            R.id.schedule_widget_header,
            listOfNotNull(dateLabel, summary, snapshot?.accountLabel, snapshot?.termLabel)
                .joinToString("，"),
        )
        views.setTextColor(R.id.schedule_widget_date, colors.text)
        views.setTextColor(R.id.schedule_widget_context, colors.secondary)
        views.setTextColor(R.id.schedule_widget_focus_label, colors.primary)
        views.setTextColor(R.id.schedule_widget_focus_title, colors.text)
        views.setTextColor(R.id.schedule_widget_focus_meta, colors.secondary)
        views.setTextColor(R.id.schedule_widget_focus_location, colors.secondary)
        views.setOnClickPendingIntent(
            R.id.schedule_widget_header,
            openDate(context, widgetId, headerDate),
        )
        views.setOnClickPendingIntent(R.id.schedule_widget_focus, openDate(context, widgetId, focus.date))
        views.setOnClickPendingIntent(R.id.schedule_widget_root, openDate(context, widgetId, headerDate))
        views.setContentDescription(
            R.id.schedule_widget_focus,
            listOf(focus.date.format(dateFormat), focus.label, focus.title, focus.meta, focus.location)
                .filter(String::isNotBlank).joinToString("，"),
        )
        if (showList) bindDayList(context, widgetId, views, listDay, frame, variant, sizing, resetScroll)
        return views
    }

    private fun bindFocus(
        views: RemoteViews,
        frame: WidgetFrame,
        variant: ScheduleWidgetLayout,
        sizing: ScheduleWidgetSizing,
        strip: Boolean,
        showList: Boolean,
    ) {
        val focus = frame.focus
        val metaFits = !strip || showList ||
            sizing.stripTitleLine + sizing.bodyLine + 2 * sizing.compactPadding + 6 <= variant.size.height
        val locationFits = !strip || (!showList &&
            sizing.stripTitleLine + 2 * sizing.bodyLine + 2 * sizing.compactPadding + 8 <= variant.size.height)
        val showLocation = locationFits && focus.location.isNotBlank()
        val shortMeta = focus.shortMeta ?: focus.meta
        val datedMeta = if (focus.date != frame.now.toLocalDate()) {
            "${focus.date.monthValue}/${focus.date.dayOfMonth} · $shortMeta"
        } else {
            shortMeta
        }
        val meta = listOfNotNull(
            if (strip) datedMeta else shortMeta,
            focus.location.takeIf { strip && !showLocation && it.isNotBlank() },
        ).joinToString(" · ")
        views.visible(R.id.schedule_widget_focus_label, !strip)
        views.visible(R.id.schedule_widget_focus_meta, metaFits)
        views.visible(R.id.schedule_widget_focus_location, showLocation)
        val titleLines = if (strip) {
            1
        } else {
            val metaHeight = sizing.bodyHeight(shortMeta) * if (focus.usable) 1 else 2
            val locationHeight = if (showLocation) sizing.bodyLine + 2 else 0f
            ((variant.size.height - 2 * sizing.cardPadding - sizing.captionLine - metaHeight - locationHeight - 4) /
                sizing.titleLine).toInt().coerceIn(1, 2)
        }
        views.setTextViewTextSize(
            R.id.schedule_widget_focus_title,
            TypedValue.COMPLEX_UNIT_PX,
            if (strip) sizing.stripTitlePixels else sizing.titlePixels,
        )
        views.setInt(R.id.schedule_widget_focus_title, "setMaxLines", titleLines)
        views.setInt(R.id.schedule_widget_focus_meta, "setMaxLines", if (strip || focus.usable) 1 else 2)
        views.setInt(R.id.schedule_widget_focus_location, "setMaxLines", 1)
        views.setTextViewText(
            R.id.schedule_widget_focus_label,
            "${focus.date.format(shortDateFormat)} · ${focus.label}",
        )
        views.setTextViewText(
            R.id.schedule_widget_focus_title,
            if (metaFits) focus.title else "${focus.title} · $datedMeta",
        )
        views.setTextViewText(R.id.schedule_widget_focus_meta, meta)
        views.setTextViewText(R.id.schedule_widget_focus_location, focus.location)
        views.setViewLayoutHeight(
            R.id.schedule_widget_focus,
            (if (showList) ViewGroup.LayoutParams.WRAP_CONTENT else ViewGroup.LayoutParams.MATCH_PARENT).toFloat(),
            TypedValue.COMPLEX_UNIT_PX,
        )
        views.setViewPadding(
            R.id.schedule_widget_focus,
            0,
            0,
            0,
            if (showList) sizing.pixels(sizing.padding) else 0,
        )
    }

    private fun bindDayList(
        context: Context,
        widgetId: Int,
        views: RemoteViews,
        day: ScheduleWidgetDay,
        frame: WidgetFrame,
        variant: ScheduleWidgetLayout,
        sizing: ScheduleWidgetSizing,
        resetScroll: Boolean,
    ) {
        val rows = RemoteViews.RemoteCollectionItems.Builder().setViewTypeCount(1)
        val minutes = if (day.date == frame.now.toLocalDate()) {
            frame.now.hour * 60 + frame.now.minute
        } else {
            -1
        }
        val lessons = listLessons(day, frame)
        lessons.forEachIndexed { index, lesson ->
            rows.addItem(
                index.toLong(),
                lessonRow(
                    context,
                    lesson,
                    frame.colors,
                    day.date,
                    minutes,
                    variant,
                    sizing,
                    focusLabel = frame.focus.label.takeIf { lesson.id == frame.focus.lessonId },
                    countdown = frame.focus.countdown.takeIf {
                        variant.showCountdown && lesson.id == frame.focus.lessonId
                    },
                    settings = frame.settings,
                ),
            )
        }
        views.setRemoteAdapter(R.id.schedule_widget_list, rows.build())
        if (resetScroll) views.setScrollPosition(R.id.schedule_widget_list, 0)
        val template = Intent(context, MainActivity::class.java).apply {
            action = "dev.zfhelper.app.SCHEDULE_WIDGET_OPEN_LIST"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        views.setPendingIntentTemplate(
            R.id.schedule_widget_list,
            PendingIntent.getActivity(
                context,
                widgetId,
                template,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            ),
        )
    }

    private fun listLessons(day: ScheduleWidgetDay, frame: WidgetFrame): List<ScheduleWidgetLesson> {
        val minutes = if (day.date == frame.now.toLocalDate()) frame.now.hour * 60 + frame.now.minute else -1
        val focusedIndex = day.lessons.indexOfFirst { it.id == frame.focus.lessonId }
        return day.lessons.drop(focusedIndex).filterIndexed { index, lesson ->
            index == 0 || lesson.phaseAt(minutes) != ScheduleWidgetPhase.FINISHED
        }
    }

    private fun lessonRow(
        context: Context,
        lesson: ScheduleWidgetLesson,
        colors: WidgetColors,
        date: LocalDate,
        minutes: Int,
        variant: ScheduleWidgetLayout,
        sizing: ScheduleWidgetSizing,
        focusLabel: String?,
        countdown: String?,
        settings: ScheduleWidgetSettings,
    ): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.schedule_widget_lesson)
        val focused = focusLabel != null
        val timed = lesson.start != null && lesson.end != null
        val columns = timed
        row.setViewLayoutWidth(
            R.id.schedule_widget_lesson_time,
            sizing.timeColumnWidth,
            TypedValue.COMPLEX_UNIT_DIP,
        )
        row.visible(R.id.schedule_widget_lesson_time, columns)
        row.visible(R.id.schedule_widget_lesson_when, !columns)
        row.visible(R.id.schedule_widget_lesson_accent, focused)
        row.tintBackground(R.id.schedule_widget_lesson_root, colors.card)
        row.visible(R.id.schedule_widget_lesson_state, focused)
        row.visible(R.id.schedule_widget_lesson_status_row, true)
        row.setTextViewText(R.id.schedule_widget_lesson_state, focusLabel.orEmpty())
        row.setTextColor(R.id.schedule_widget_lesson_state, colors.primary)
        row.visible(R.id.schedule_widget_lesson_countdown, countdown != null)
        if (countdown != null) {
            row.setTextViewText(R.id.schedule_widget_lesson_countdown, countdown)
            row.setTextColor(R.id.schedule_widget_lesson_countdown, colors.text)
            row.tintBackground(
                R.id.schedule_widget_lesson_countdown,
                WidgetColor(
                    ColorUtils.blendARGB(colors.card.day, colors.primary.day, 0.18f),
                    ColorUtils.blendARGB(colors.card.night, colors.primary.night, 0.18f),
                ),
            )
        }
        row.setWidgetColor(
            R.id.schedule_widget_lesson_accent,
            "setBackgroundColor",
            colors.primary,
        )
        val phase = lesson.phaseAt(minutes)
        row.setTextViewText(R.id.schedule_widget_lesson_start, lesson.start?.let(::scheduleWidgetClock))
        row.setTextViewText(
            R.id.schedule_widget_lesson_end,
            lesson.end?.let(::scheduleWidgetClock),
        )
        row.setTextViewText(
            R.id.schedule_widget_lesson_when,
            listOf(
                if (timed) lesson.timeLabel else lesson.periodLabel.ifBlank { "节次未设置" },
                phase.label,
            ).joinToString(" · "),
        )
        row.setTextViewText(R.id.schedule_widget_lesson_title, lesson.title)
        row.setInt(
            R.id.schedule_widget_lesson_title,
            "setMaxLines",
            if (countdown != null) 1 else 2,
        )
        val location = lesson.location.takeIf { settings.showLocation }.orEmpty()
        row.setTextViewText(R.id.schedule_widget_lesson_location, location)
        row.visible(R.id.schedule_widget_lesson_location, location.isNotBlank())
        val detail = listOfNotNull(
            lesson.periodLabel.takeIf(String::isNotBlank),
            lesson.teacher?.takeIf { settings.showTeacher && variant.detailed && it.isNotBlank() },
        ).joinToString(" · ")
        row.setTextViewText(R.id.schedule_widget_lesson_detail, detail)
        row.visible(R.id.schedule_widget_lesson_detail, detail.isNotBlank())
        row.setTextColor(R.id.schedule_widget_lesson_when, colors.primary)
        row.setTextColor(R.id.schedule_widget_lesson_start, colors.primary)
        row.setTextColor(R.id.schedule_widget_lesson_end, colors.secondary)
        row.setTextColor(R.id.schedule_widget_lesson_title, colors.text)
        row.setTextColor(R.id.schedule_widget_lesson_location, colors.secondary)
        row.setTextColor(R.id.schedule_widget_lesson_detail, colors.secondary)
        row.setOnClickFillInIntent(
            R.id.schedule_widget_lesson_root,
            Intent().putExtra(SCHEDULE_WIDGET_DATE, date.toString()),
        )
        row.setContentDescription(
            R.id.schedule_widget_lesson_root,
            listOfNotNull(lesson.title, lesson.periodLabel, lesson.timeLabel, location, detail, phase.label, countdown)
                .filter(String::isNotBlank).joinToString("，"),
        )
        return row
    }

    private fun focus(
        snapshot: ScheduleWidgetSnapshot?,
        failure: String?,
        now: ZonedDateTime,
        settings: ScheduleWidgetSettings,
    ): WidgetFocus {
        val today = now.toLocalDate()
        if (failure != null) return WidgetFocus(today, "同步异常", "课表暂不可用", failure)
        if (snapshot == null) {
            return WidgetFocus(today, "桌面课表", "先同步课表", "打开 ZFHelper，完成课表设置")
        }
        when (snapshot.status) {
            "noAccount" -> return WidgetFocus(
                today,
                "桌面课表",
                "尚未添加账号",
                "请在应用设置中添加学校与账号",
            )
            "noSchedule" -> return WidgetFocus(
                today,
                "桌面课表",
                "尚未导入课表",
                "请在应用设置中获取并保存课表",
            )
            "calendarMissing" -> return WidgetFocus(
                today,
                "校历待设置",
                "无法确定上课日期",
                "请在校历与作息中填写第一周周一",
            )
        }
        val minutes = now.hour * 60 + now.minute
        val day = snapshot.days.firstOrNull { it.date == today }
        val active = day?.lessons?.firstOrNull { it.phaseAt(minutes).isActive }
        if (active != null) {
            val phase = active.phaseAt(minutes)
            val countdown = active.end?.takeIf { settings.showCountdown && phase == ScheduleWidgetPhase.IN_CLASS && it > minutes }
                ?.let { "剩 ${it - minutes} 分钟" }
            return lessonFocus(today, phase.label, active, settings, countdown)
        }
        val next = day?.lessons?.filter { it.start != null && it.start > minutes }?.minByOrNull { it.start!! }
        val untilNext = next?.start?.minus(minutes)
        if (next != null && untilNext != null && untilNext <= SCHEDULE_WIDGET_UPCOMING_MINUTES) {
            val countdown = if (settings.showCountdown) "还有 $untilNext 分钟" else null
            return lessonFocus(today, "下一节", next, settings, countdown)
        }
        if (day != null && (day.byPeriod || day.lessons.any { it.start == null })) {
            val pending = day.lessons.firstOrNull { it.end == null || it.end > minutes }
            if (pending != null) {
                return lessonFocus(
                    today,
                    if (day.byPeriod) "今日课程 · 按节次" else "今日课程",
                    pending,
                    settings,
                )
            }
        }
        if (next != null) return lessonFocus(today, "下一节", next, settings)
        val later = snapshot.days.firstOrNull { it.date > today }
        if (later != null) {
            val label = when {
                later.byPeriod -> "后续课程 · 按节次"
                later.lessons.any { it.start == null } -> "后续课程"
                else -> "下一节"
            }
            return lessonFocus(later.date, label, later.lessons.first(), settings)
        }
        return WidgetFocus(
            today,
            "今日课表",
            if (day == null) "今天没有课程" else "今天的课程已结束",
            "点击查看周课表",
            usable = true,
        )
    }

    private fun lessonFocus(
        date: LocalDate,
        label: String,
        lesson: ScheduleWidgetLesson,
        settings: ScheduleWidgetSettings,
        countdown: String? = null,
    ): WidgetFocus {
        val timing = listOfNotNull(
            lesson.periodLabel.takeIf(String::isNotBlank),
            lesson.timeLabel,
        ).joinToString(" · ")
        val shortMeta = if (lesson.start != null) {
            lesson.timeLabel
        } else {
            lesson.periodLabel.ifBlank { lesson.timeLabel }
        }
        return WidgetFocus(
            date,
            label,
            lesson.title,
            timing,
            lesson.location.takeIf { settings.showLocation }.orEmpty(),
            usable = true,
            shortMeta = shortMeta,
            lessonId = lesson.id,
            countdown = countdown,
        )
    }

    fun hasCountdown(
        snapshot: ScheduleWidgetSnapshot,
        now: ZonedDateTime,
        settings: ScheduleWidgetSettings = ScheduleWidgetSettings.defaults,
    ): Boolean = focus(snapshot, null, now, settings).countdown != null

    private fun openDate(context: Context, widgetId: Int, date: LocalDate): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            action = "dev.zfhelper.app.SCHEDULE_WIDGET_OPEN.$date"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
            putExtra(SCHEDULE_WIDGET_DATE, date.toString())
        }
        return PendingIntent.getActivity(
            context,
            widgetId,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
    }

    private fun colors(
        context: Context,
        snapshot: ScheduleWidgetSnapshot?,
        savedTheme: ScheduleWidgetTheme?,
    ): WidgetColors {
        val theme = savedTheme ?: snapshot?.let { ScheduleWidgetTheme(it.appearance, it.light, it.dark) }
        val light = theme?.light ?: ScheduleWidgetColors(
            context.getColor(android.R.color.system_neutral1_50),
            context.getColor(android.R.color.system_accent1_600),
            context.getColor(android.R.color.system_neutral1_900),
            context.getColor(android.R.color.system_neutral2_600),
            context.getColor(android.R.color.system_neutral2_200),
        )
        val dark = theme?.dark ?: ScheduleWidgetColors(
            context.getColor(android.R.color.system_neutral1_900),
            context.getColor(android.R.color.system_accent1_200),
            context.getColor(android.R.color.system_neutral1_50),
            context.getColor(android.R.color.system_neutral2_200),
            context.getColor(android.R.color.system_neutral2_700),
        )
        val appearance = theme?.appearance
        val day = if (appearance == "dark") dark else light
        val night = if (appearance == "light") light else dark
        return WidgetColors(
            WidgetColor(day.surface, night.surface),
            WidgetColor(day.card, night.card),
            WidgetColor(day.primary, night.primary),
            WidgetColor(day.text, night.text),
            WidgetColor(day.secondary, night.secondary),
        )
    }

    private fun RemoteViews.setTextColor(viewId: Int, color: WidgetColor) =
        setWidgetColor(viewId, "setTextColor", color)

    private fun RemoteViews.visible(viewId: Int, visible: Boolean) =
        setViewVisibility(viewId, if (visible) View.VISIBLE else View.GONE)

    private fun RemoteViews.tintBackground(viewId: Int, color: WidgetColor) = setColorStateList(
        viewId,
        "setBackgroundTintList",
        ColorStateList.valueOf(color.day),
        ColorStateList.valueOf(color.night),
    )

    private fun RemoteViews.setWidgetColor(viewId: Int, method: String, color: WidgetColor) =
        setColorInt(viewId, method, color.day, color.night)

    private data class WidgetColor(val day: Int, val night: Int)

    private data class WidgetColors(
        val surface: WidgetColor,
        val card: WidgetColor,
        val primary: WidgetColor,
        val text: WidgetColor,
        val secondary: WidgetColor,
    )

    private data class WidgetFrame(
        val snapshot: ScheduleWidgetSnapshot?,
        val day: ScheduleWidgetDay?,
        val focus: WidgetFocus,
        val colors: WidgetColors,
        val now: ZonedDateTime,
        val settings: ScheduleWidgetSettings,
    )

    private data class WidgetFocus(
        val date: LocalDate,
        val label: String,
        val title: String,
        val meta: String,
        val location: String = "",
        val usable: Boolean = false,
        val shortMeta: String? = null,
        val lessonId: String? = null,
        val countdown: String? = null,
    )
}
