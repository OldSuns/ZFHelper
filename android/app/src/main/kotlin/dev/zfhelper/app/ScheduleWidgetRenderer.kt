package dev.zfhelper.app

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.res.ColorStateList
import android.util.TypedValue
import android.view.View
import android.view.ViewGroup
import android.widget.RemoteViews
import java.time.LocalDate
import java.time.ZonedDateTime
import java.time.format.DateTimeFormatter
import java.util.Locale

internal object ScheduleWidgetRenderer {
    private val dateFormat = DateTimeFormatter.ofPattern("M月d日 EEE", Locale.SIMPLIFIED_CHINESE)
    private val shortDateFormat = DateTimeFormatter.ofPattern("M/d EEE", Locale.SIMPLIFIED_CHINESE)
    private val weekdayFormat = DateTimeFormatter.ofPattern("EEE", Locale.SIMPLIFIED_CHINESE)

    fun render(
        context: Context,
        widgetId: Int,
        snapshot: ScheduleWidgetSnapshot?,
        failure: String?,
        now: ZonedDateTime,
    ): RemoteViews {
        val today = now.toLocalDate()
        val frame = WidgetFrame(
            snapshot,
            snapshot?.days?.firstOrNull { it.date == today },
            focus(snapshot, failure, now),
            colors(context, snapshot),
            now,
        )
        val sizing = ScheduleWidgetSizing(context)
        return RemoteViews(
            sizing.variants().associate { variant ->
                variant.size to when {
                    !frame.focus.usable -> focusLayout(context, widgetId, variant, sizing, frame)
                    variant.style == ScheduleWidgetStyle.TWO_DAY ->
                        twoDayLayout(context, widgetId, variant, sizing, frame)
                    variant.style == ScheduleWidgetStyle.WEEK && snapshot?.weekAt(today) != null ->
                        weekLayout(context, widgetId, snapshot.weekAt(today)!!, frame)
                    else -> focusLayout(context, widgetId, variant, sizing, frame)
                }
            },
        )
    }

    private fun focusLayout(
        context: Context,
        widgetId: Int,
        variant: ScheduleWidgetLayout,
        sizing: ScheduleWidgetSizing,
        frame: WidgetFrame,
    ): RemoteViews {
        val (snapshot, _, focus, colors, now) = frame
        val views = RemoteViews(context.packageName, R.layout.schedule_widget)
        val listDay = if (variant.style == ScheduleWidgetStyle.TODAY_LIST) {
            snapshot?.days?.firstOrNull { it.date == focus.date && it.lessons.isNotEmpty() }
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
        views.visible(R.id.schedule_widget_refresh, showList)
        views.visible(R.id.schedule_widget_list, showList)
        views.visible(R.id.schedule_widget_focus, !showList)
        bindFocus(views, frame, variant, sizing, strip, showList)
        views.tintBackground(R.id.schedule_widget_root, colors.surface)
        val headerDate = listDay?.date ?: focus.date
        val headerDay = snapshot?.days?.firstOrNull { it.date == headerDate }
        val dateLabel = headerDate.format(if (showList) dateFormat else shortDateFormat)
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
        views.setWidgetColor(R.id.schedule_widget_refresh, "setColorFilter", colors.primary)
        views.setOnClickPendingIntent(R.id.schedule_widget_refresh, refresh(context))
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
        if (showList) bindDayList(context, widgetId, views, listDay, frame, variant, sizing)
        return views
    }

    private fun twoDayLayout(
        context: Context,
        widgetId: Int,
        variant: ScheduleWidgetLayout,
        sizing: ScheduleWidgetSizing,
        frame: WidgetFrame,
    ): RemoteViews {
        val today = frame.now.toLocalDate()
        val tomorrow = today.plusDays(1)
        val todayDay = frame.snapshot?.days?.firstOrNull { it.date == today }
        val tomorrowDay = frame.snapshot?.days?.firstOrNull { it.date == tomorrow }
        val minutes = frame.now.hour * 60 + frame.now.minute
        val remaining = todayDay?.lessons.orEmpty().filter { it.end == null || it.end > minutes }
        val tomorrowLessons = tomorrowDay?.lessons.orEmpty()
        if (remaining.isEmpty() && tomorrowLessons.isEmpty()) {
            return focusLayout(context, widgetId, variant, sizing, frame)
        }
        val views = RemoteViews(context.packageName, R.layout.schedule_widget_two_day)
        val week = frame.snapshot?.weekAt(today)?.number
        views.tintBackground(R.id.schedule_widget_two_day_root, frame.colors.surface)
        views.setTextViewText(R.id.schedule_widget_two_day_title, "今明课程")
        views.setTextViewText(
            R.id.schedule_widget_two_day_context,
            listOfNotNull(week?.let { "第 $it 周" }, frame.snapshot?.termLabel)
                .joinToString(" · "),
        )
        views.setTextViewText(
            R.id.schedule_widget_today_heading,
            "今天 ${today.format(shortDateFormat)}",
        )
        views.setTextViewText(
            R.id.schedule_widget_tomorrow_heading,
            "明天 ${tomorrow.format(shortDateFormat)}",
        )
        val rowLimit = sizing.twoDayRowLimit(variant.size.height)
        bindCompactDay(
            context,
            widgetId,
            views,
            R.id.schedule_widget_today_courses,
            R.id.schedule_widget_today_footer,
            today,
            remaining,
            rowLimit,
            frame.colors,
            when {
                todayDay == null -> "今天无课"
                remaining.isEmpty() -> "今日课程已结束"
                else -> "剩余 ${remaining.size} 门"
            },
        )
        bindCompactDay(
            context,
            widgetId,
            views,
            R.id.schedule_widget_tomorrow_courses,
            R.id.schedule_widget_tomorrow_footer,
            tomorrow,
            tomorrowLessons,
            rowLimit,
            frame.colors,
            if (tomorrowLessons.isEmpty()) "明天无课" else "共 ${tomorrowLessons.size} 门",
        )
        for (id in listOf(
            R.id.schedule_widget_two_day_title,
            R.id.schedule_widget_today_heading,
            R.id.schedule_widget_tomorrow_heading,
        )) {
            views.setTextColor(id, frame.colors.text)
        }
        for (id in listOf(
            R.id.schedule_widget_two_day_context,
            R.id.schedule_widget_today_footer,
            R.id.schedule_widget_tomorrow_footer,
        )) {
            views.setTextColor(id, frame.colors.secondary)
        }
        views.setWidgetColor(R.id.schedule_widget_day_divider, "setBackgroundColor", frame.colors.outline)
        views.setWidgetColor(R.id.schedule_widget_two_day_refresh, "setColorFilter", frame.colors.primary)
        views.setOnClickPendingIntent(R.id.schedule_widget_two_day_refresh, refresh(context))
        views.setOnClickPendingIntent(
            R.id.schedule_widget_today_column,
            openDate(context, widgetId, today),
        )
        views.setOnClickPendingIntent(
            R.id.schedule_widget_tomorrow_column,
            openDate(context, widgetId, tomorrow),
        )
        views.setOnClickPendingIntent(
            R.id.schedule_widget_two_day_root,
            openDate(context, widgetId, today),
        )
        views.setContentDescription(
            R.id.schedule_widget_two_day_root,
            "今明课程，今天${remaining.size}门剩余课程，明天${tomorrowLessons.size}门课程",
        )
        return views
    }

    private fun bindCompactDay(
        context: Context,
        widgetId: Int,
        views: RemoteViews,
        containerId: Int,
        footerId: Int,
        date: LocalDate,
        lessons: List<ScheduleWidgetLesson>,
        rowLimit: Int,
        colors: WidgetColors,
        footer: String,
    ) {
        lessons.take(rowLimit).forEach { lesson ->
            val row = RemoteViews(context.packageName, R.layout.schedule_widget_compact_lesson)
            val timing = if (lesson.start != null) {
                scheduleWidgetClock(lesson.start)
            } else {
                lesson.periodLabel.ifBlank { lesson.timeLabel }
            }
            val meta = listOf(timing, lesson.location).filter(String::isNotBlank).joinToString(" · ")
            row.setTextViewText(R.id.schedule_widget_compact_lesson_title, lesson.title)
            row.setTextViewText(R.id.schedule_widget_compact_lesson_meta, meta)
            row.setTextColor(R.id.schedule_widget_compact_lesson_title, colors.text)
            row.setTextColor(R.id.schedule_widget_compact_lesson_meta, colors.secondary)
            row.setOnClickPendingIntent(
                R.id.schedule_widget_compact_lesson_root,
                openDate(context, widgetId, date),
            )
            row.setContentDescription(
                R.id.schedule_widget_compact_lesson_root,
                listOf(lesson.title, timing, lesson.location).filter(String::isNotBlank)
                    .joinToString("，"),
            )
            views.addView(containerId, row)
        }
        val hidden = lessons.size - rowLimit
        views.setTextViewText(footerId, if (hidden > 0) "$footer · 还有 $hidden 门" else footer)
    }

    private fun weekLayout(
        context: Context,
        widgetId: Int,
        week: ScheduleWidgetWeek,
        frame: WidgetFrame,
    ): RemoteViews {
        val views = RemoteViews(context.packageName, R.layout.schedule_widget_week)
        val today = frame.now.toLocalDate()
        val first = week.days.first().date
        val last = week.days.last().date
        views.tintBackground(R.id.schedule_widget_week_root, frame.colors.surface)
        views.setTextViewText(R.id.schedule_widget_week_title, "本周 · 第 ${week.number} 周")
        views.setTextViewText(
            R.id.schedule_widget_week_context,
            "${first.monthValue}/${first.dayOfMonth}–${last.monthValue}/${last.dayOfMonth} · ${week.days.sumOf { it.lessons.size }} 门课",
        )
        views.setTextColor(R.id.schedule_widget_week_title, frame.colors.text)
        views.setTextColor(R.id.schedule_widget_week_context, frame.colors.secondary)
        views.setWidgetColor(R.id.schedule_widget_week_refresh, "setColorFilter", frame.colors.primary)
        views.setOnClickPendingIntent(R.id.schedule_widget_week_refresh, refresh(context))
        val rows = RemoteViews.RemoteCollectionItems.Builder().setViewTypeCount(1)
        week.days.forEachIndexed { index, day ->
            val row = RemoteViews(context.packageName, R.layout.schedule_widget_week_day)
            val isToday = day.date == today
            val names = day.lessons.map { it.title }.distinct()
            row.setTextViewText(
                R.id.schedule_widget_week_day_label,
                if (isToday) "今天" else day.date.format(weekdayFormat),
            )
            row.setTextViewText(
                R.id.schedule_widget_week_day_courses,
                if (names.isEmpty()) "无课" else names.joinToString("、"),
            )
            row.setTextViewText(
                R.id.schedule_widget_week_day_count,
                if (day.lessons.isEmpty()) "" else "${day.lessons.size} 门",
            )
            row.setTextColor(
                R.id.schedule_widget_week_day_label,
                if (isToday) frame.colors.primary else frame.colors.text,
            )
            row.setTextColor(R.id.schedule_widget_week_day_courses, frame.colors.text)
            row.setTextColor(R.id.schedule_widget_week_day_count, frame.colors.secondary)
            row.setOnClickFillInIntent(
                R.id.schedule_widget_week_day_root,
                Intent().putExtra(SCHEDULE_WIDGET_DATE, day.date.toString()),
            )
            row.setContentDescription(
                R.id.schedule_widget_week_day_root,
                "${day.date.format(dateFormat)}，${if (names.isEmpty()) "无课" else names.joinToString("、")}",
            )
            rows.addItem(index.toLong(), row)
        }
        views.setRemoteAdapter(R.id.schedule_widget_week_days, rows.build())
        val template = Intent(context, MainActivity::class.java).apply {
            action = "dev.zfhelper.app.SCHEDULE_WIDGET_OPEN_WEEK_LIST"
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP or
                Intent.FLAG_ACTIVITY_SINGLE_TOP
        }
        views.setPendingIntentTemplate(
            R.id.schedule_widget_week_days,
            PendingIntent.getActivity(
                context,
                widgetId,
                template,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_MUTABLE,
            ),
        )
        views.setOnClickPendingIntent(
            R.id.schedule_widget_week_header,
            openDate(context, widgetId, today),
        )
        views.setOnClickPendingIntent(
            R.id.schedule_widget_week_root,
            openDate(context, widgetId, today),
        )
        views.setContentDescription(
            R.id.schedule_widget_week_root,
            "第${week.number}周，本周${week.days.sumOf { it.lessons.size }}门课",
        )
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
    ) {
        val rows = RemoteViews.RemoteCollectionItems.Builder().setViewTypeCount(1)
        val minutes = if (day.date == frame.now.toLocalDate()) {
            frame.now.hour * 60 + frame.now.minute
        } else {
            -1
        }
        day.lessons.forEachIndexed { index, lesson ->
            rows.addItem(
                index.toLong(),
                lessonRow(context, lesson, frame.colors, day.date, minutes, variant, sizing),
            )
        }
        views.setRemoteAdapter(R.id.schedule_widget_list, rows.build())
        val focusedIndex = day.lessons.indexOfFirst { it.id == frame.focus.lessonId }
        if (focusedIndex >= 0) views.setScrollPosition(R.id.schedule_widget_list, focusedIndex)
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

    private fun lessonRow(
        context: Context,
        lesson: ScheduleWidgetLesson,
        colors: WidgetColors,
        date: LocalDate,
        minutes: Int,
        variant: ScheduleWidgetLayout,
        sizing: ScheduleWidgetSizing,
    ): RemoteViews {
        val row = RemoteViews(context.packageName, R.layout.schedule_widget_lesson)
        val timed = lesson.start != null && lesson.end != null
        val columns = variant.detailed && timed
        row.setViewLayoutWidth(
            R.id.schedule_widget_lesson_time,
            sizing.timeColumnWidth,
            TypedValue.COMPLEX_UNIT_DIP,
        )
        row.visible(R.id.schedule_widget_lesson_time, columns)
        row.visible(R.id.schedule_widget_lesson_when, !columns)
        val phase = lesson.phaseAt(minutes)
        row.setTextViewText(R.id.schedule_widget_lesson_start, lesson.start?.let(::scheduleWidgetClock))
        row.setTextViewText(
            R.id.schedule_widget_lesson_end,
            lesson.end?.let { "${scheduleWidgetClock(it)}\n${phase.label}" },
        )
        row.setInt(R.id.schedule_widget_lesson_end, "setMaxLines", 2)
        row.setTextViewText(
            R.id.schedule_widget_lesson_when,
            listOf(
                if (timed) lesson.timeLabel else lesson.periodLabel.ifBlank { "节次未设置" },
                phase.label,
            ).joinToString(" · "),
        )
        row.setTextViewText(R.id.schedule_widget_lesson_title, lesson.title)
        row.setTextViewText(R.id.schedule_widget_lesson_location, lesson.location)
        row.visible(R.id.schedule_widget_lesson_location, lesson.location.isNotBlank())
        val detail = listOfNotNull(
            lesson.periodLabel.takeIf { timed && it.isNotBlank() },
            lesson.teacher?.takeIf(String::isNotBlank),
        ).joinToString(" · ")
        row.setTextViewText(R.id.schedule_widget_lesson_detail, detail)
        row.visible(R.id.schedule_widget_lesson_detail, variant.detailed && detail.isNotBlank())
        row.setTextColor(R.id.schedule_widget_lesson_when, colors.primary)
        row.setTextColor(R.id.schedule_widget_lesson_start, colors.primary)
        row.setTextColor(R.id.schedule_widget_lesson_end, colors.secondary)
        row.setTextColor(R.id.schedule_widget_lesson_title, colors.text)
        row.setTextColor(R.id.schedule_widget_lesson_location, colors.secondary)
        row.setTextColor(R.id.schedule_widget_lesson_detail, colors.secondary)
        row.setWidgetColor(R.id.schedule_widget_lesson_divider, "setBackgroundColor", colors.outline)
        row.setOnClickFillInIntent(
            R.id.schedule_widget_lesson_root,
            Intent().putExtra(SCHEDULE_WIDGET_DATE, date.toString()),
        )
        row.setContentDescription(
            R.id.schedule_widget_lesson_root,
            listOf(lesson.title, lesson.periodLabel, lesson.timeLabel, lesson.location, detail, phase.label)
                .filter(String::isNotBlank).joinToString("，"),
        )
        return row
    }

    private fun focus(
        snapshot: ScheduleWidgetSnapshot?,
        failure: String?,
        now: ZonedDateTime,
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
        if (active != null) return lessonFocus(today, active.phaseAt(minutes).label, active)
        if (day != null && (day.byPeriod || day.lessons.any { it.start == null })) {
            val pending = day.lessons.firstOrNull { it.end == null || it.end > minutes }
            if (pending != null) {
                return lessonFocus(
                    today,
                    if (day.byPeriod) "今日课程 · 按节次" else "今日课程",
                    pending,
                )
            }
        }
        val next = day?.lessons?.firstOrNull { it.start != null && it.start > minutes }
        if (next != null) return lessonFocus(today, "下一节", next)
        val later = snapshot.days.firstOrNull { it.date > today }
        if (later != null) {
            val label = when {
                later.byPeriod -> "后续课程 · 按节次"
                later.lessons.any { it.start == null } -> "后续课程"
                else -> "下一节"
            }
            return lessonFocus(later.date, label, later.lessons.first())
        }
        return WidgetFocus(
            today,
            "今日课表",
            if (day == null) "今天没有课程" else "今天的课程已结束",
            "点击查看课表与日程",
            usable = true,
        )
    }

    private fun lessonFocus(
        date: LocalDate,
        label: String,
        lesson: ScheduleWidgetLesson,
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
            lesson.location,
            usable = true,
            shortMeta = shortMeta,
            lessonId = lesson.id,
        )
    }

    private fun refresh(context: Context): PendingIntent = PendingIntent.getBroadcast(
        context,
        0,
        Intent(context, ScheduleWidgetProvider::class.java).setAction(SCHEDULE_WIDGET_REFRESH),
        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )

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

    private fun colors(context: Context, snapshot: ScheduleWidgetSnapshot?): WidgetColors {
        val light = snapshot?.light ?: ScheduleWidgetColors(
            context.getColor(android.R.color.system_neutral1_50),
            context.getColor(android.R.color.system_accent1_600),
            context.getColor(android.R.color.system_neutral1_900),
            context.getColor(android.R.color.system_neutral2_600),
            context.getColor(android.R.color.system_neutral2_200),
        )
        val dark = snapshot?.dark ?: ScheduleWidgetColors(
            context.getColor(android.R.color.system_neutral1_900),
            context.getColor(android.R.color.system_accent1_200),
            context.getColor(android.R.color.system_neutral1_50),
            context.getColor(android.R.color.system_neutral2_200),
            context.getColor(android.R.color.system_neutral2_700),
        )
        val day = if (snapshot?.appearance == "dark") dark else light
        val night = if (snapshot?.appearance == "light") light else dark
        return WidgetColors(
            WidgetColor(day.surface, night.surface),
            WidgetColor(day.primary, night.primary),
            WidgetColor(day.text, night.text),
            WidgetColor(day.secondary, night.secondary),
            WidgetColor(day.outline, night.outline),
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
        val primary: WidgetColor,
        val text: WidgetColor,
        val secondary: WidgetColor,
        val outline: WidgetColor,
    )

    private data class WidgetFrame(
        val snapshot: ScheduleWidgetSnapshot?,
        val day: ScheduleWidgetDay?,
        val focus: WidgetFocus,
        val colors: WidgetColors,
        val now: ZonedDateTime,
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
    )
}
