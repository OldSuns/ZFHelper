package dev.zfhelper.app

import org.json.JSONArray
import java.security.MessageDigest
import java.time.LocalDate
import java.time.ZonedDateTime

internal class ScheduleIslandException(val code: String, override val message: String) : Exception(message)

internal enum class ScheduleIslandPhase(val label: String, val countdown: String) {
    UPCOMING("即将上课", "距上课"), IN_CLASS("上课中", "距下课"), BREAK("课间", "距继续上课");
}

internal data class ScheduleIslandReminder(
    val key: String,
    val sourceKey: String,
    val date: LocalDate,
    val title: String,
    val detail: String,
    val location: String,
    val phase: ScheduleIslandPhase,
    val deadline: Long,
    val lessonEnd: Long,
) {
    val token: String get() = scheduleIslandKey(key, phase.name, deadline.toString())
    val label: String get() = "${phase.label} · $title"
}

internal data class ScheduleIslandPlan(
    val reminders: List<ScheduleIslandReminder>,
    val nextBoundary: Long?,
    val untimedLessons: Int,
) {
    companion object {
        fun create(
            snapshot: ScheduleWidgetSnapshot?,
            leadMinutes: Int,
            dismissed: Set<String>,
            now: ZonedDateTime,
        ): ScheduleIslandPlan {
            val source = snapshot?.source
            if (source == null || snapshot.status != "ready") return ScheduleIslandPlan(emptyList(), null, 0)
            val sourceKey = source.islandKey
            val nowMillis = now.toInstant().toEpochMilli()
            val today = now.toLocalDate()
            val reminders = mutableListOf<ScheduleIslandReminder>()
            var nextBoundary: Long? = null
            var untimed = 0
            fun consider(boundary: Long) {
                if (boundary > nowMillis && (nextBoundary == null || boundary < nextBoundary!!)) {
                    nextBoundary = boundary
                }
            }
            for (day in snapshot.days) {
                if (day.date < today) continue
                fun at(minutes: Int) = day.date.atStartOfDay().plusMinutes(minutes.toLong())
                    .atZone(now.zone).toInstant().toEpochMilli()
                for (lesson in day.lessons) {
                    // Partial period clocks must never become guessed reminder times.
                    if (lesson.start == null || lesson.end == null) {
                        untimed++
                        continue
                    }
                    val end = at(lesson.end)
                    if (nowMillis >= end) continue
                    val key = scheduleIslandKey(sourceKey, day.date.toString(), lesson.id)
                    if (key in dismissed) continue
                    val start = at(lesson.start)
                    val noticeStart = start - leadMinutes * 60_000L
                    consider(noticeStart)
                    lesson.periods.forEach { consider(at(it.start)); consider(at(it.end)) }
                    if (nowMillis < noticeStart) continue
                    val period = lesson.periods.firstOrNull { nowMillis < at(it.end) } ?: continue
                    val phase = when {
                        nowMillis < start -> ScheduleIslandPhase.UPCOMING
                        nowMillis < at(period.start) -> ScheduleIslandPhase.BREAK
                        else -> ScheduleIslandPhase.IN_CLASS
                    }
                    val deadline = if (phase == ScheduleIslandPhase.IN_CLASS) at(period.end) else at(period.start)
                    reminders += ScheduleIslandReminder(
                        key, sourceKey, day.date, lesson.title,
                        listOf(lesson.periodLabel, lesson.timeLabel).filter(String::isNotBlank).joinToString(" · "),
                        lesson.location, phase, deadline, end,
                    )
                }
            }
            return ScheduleIslandPlan(reminders.sortedBy { it.deadline }, nextBoundary, untimed)
        }
    }
}

internal val ScheduleWidgetSource.islandKey: String
    get() = scheduleIslandKey(schoolId, accountId, termKey)

internal fun scheduleIslandKey(vararg values: String): String =
    MessageDigest.getInstance("SHA-256").digest(JSONArray(values.toList()).toString().toByteArray(Charsets.UTF_8))
        .joinToString("") { "%02x".format(it) }
