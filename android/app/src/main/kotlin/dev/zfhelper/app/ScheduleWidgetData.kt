package dev.zfhelper.app

import android.content.Context
import android.util.AtomicFile
import android.util.Log
import org.json.JSONArray
import org.json.JSONException
import org.json.JSONObject
import org.json.JSONTokener
import java.io.File
import java.io.IOException
import java.time.LocalDate
import java.time.format.DateTimeParseException

internal enum class ScheduleWidgetFailureKind { SNAPSHOT, DISPLAY }

internal class ScheduleWidgetException(
    val code: String,
    override val message: String,
    val kind: ScheduleWidgetFailureKind = ScheduleWidgetFailureKind.SNAPSHOT,
) : Exception(message)

internal data class ScheduleWidgetColors(
    val surface: Int,
    val primary: Int,
    val text: Int,
    val secondary: Int,
    val outline: Int,
    val card: Int = surface,
)

internal data class ScheduleWidgetTheme(
    val appearance: String,
    val light: ScheduleWidgetColors,
    val dark: ScheduleWidgetColors,
)

internal data class ScheduleWidgetSettings(
    val showCountdown: Boolean = true,
    val showLocation: Boolean = true,
    val showTeacher: Boolean = true,
) {
    fun toMap(): Map<String, Boolean> = mapOf(
        "showCountdown" to showCountdown,
        "showLocation" to showLocation,
        "showTeacher" to showTeacher,
    )

    companion object {
        val defaults = ScheduleWidgetSettings()

        fun fromArguments(arguments: Any?): ScheduleWidgetSettings {
            val values = arguments as? Map<*, *>
                ?: invalidWidgetPayload("小组件显示设置")
            widgetPayloadCheck(
                values.keys.all { it in setOf("showCountdown", "showLocation", "showTeacher") },
                "未知显示设置",
            )
            fun read(key: String): Boolean = values[key] as? Boolean
                ?: invalidWidgetPayload("显示设置.$key")
            return ScheduleWidgetSettings(
                showCountdown = read("showCountdown"),
                showLocation = read("showLocation"),
                showTeacher = read("showTeacher"),
            )
        }
    }
}

internal data class ScheduleWidgetPeriod(val start: Int, val end: Int)

internal data class ScheduleWidgetSource(val schoolId: String, val accountId: String, val termKey: String)

internal enum class ScheduleWidgetPhase(val label: String) {
    IN_CLASS("上课中"),
    BREAK("课间"),
    FINISHED("已结束"),
    UPCOMING("待上课"),
    NO_CLOCK("作息未设置"),
    PARTIAL_CLOCK("作息不完整");

    val isActive: Boolean
        get() = this == IN_CLASS || this == BREAK
}

internal data class ScheduleWidgetLesson(
    val id: String,
    val title: String,
    val periodLabel: String,
    val location: String,
    val place: String,
    val teacher: String?,
    val start: Int?,
    val end: Int?,
    val periods: List<ScheduleWidgetPeriod>,
) {
    fun phaseAt(minutes: Int): ScheduleWidgetPhase = when {
        periods.any { minutes >= it.start && minutes < it.end } -> ScheduleWidgetPhase.IN_CLASS
        start == null || end == null ->
            if (periods.isEmpty()) ScheduleWidgetPhase.NO_CLOCK else ScheduleWidgetPhase.PARTIAL_CLOCK
        minutes >= end -> ScheduleWidgetPhase.FINISHED
        minutes >= start -> ScheduleWidgetPhase.BREAK
        else -> ScheduleWidgetPhase.UPCOMING
    }

    val timeLabel: String
        get() = if (start != null && end != null) {
            "${scheduleWidgetClock(start)}–${scheduleWidgetClock(end)}"
        } else {
            if (periods.isEmpty()) "作息未设置" else "作息不完整"
        }
}

internal data class ScheduleWidgetDay(
    val date: LocalDate,
    val week: Int,
    val byPeriod: Boolean,
    val lessons: List<ScheduleWidgetLesson>,
)

internal data class ScheduleWidgetSnapshot(
    val generatedAt: Long,
    val appearance: String,
    val status: String,
    val accountLabel: String?,
    val termLabel: String?,
    val source: ScheduleWidgetSource?,
    val light: ScheduleWidgetColors,
    val dark: ScheduleWidgetColors,
    val days: List<ScheduleWidgetDay>,
) {
    companion object {
        fun parse(payload: String): ScheduleWidgetSnapshot {
            try {
                val tokenizer = JSONTokener(payload)
                val json = tokenizer.nextValue() as? JSONObject
                    ?: invalidWidgetPayload("根对象")
                json.allowedKeys("version", "generatedAt", "appearance", "status", "account", "term", "palette", "days")
                widgetPayloadCheck(tokenizer.nextClean() == '\u0000', "根对象")
                widgetPayloadCheck(json.integer("version") == 1L, "version")
                val generatedAt = json.integer("generatedAt")
                widgetPayloadCheck(generatedAt >= 0, "generatedAt")
                val appearance = json.string("appearance")
                widgetPayloadCheck(appearance in setOf("system", "light", "dark"), "appearance")
                val status = json.string("status")
                widgetPayloadCheck(
                    status in setOf("ready", "noAccount", "noSchedule", "calendarMissing"),
                    "status",
                )
                val account = json.nullableObject("account")
                val term = json.nullableObject("term")
                val accountLabel = account?.let {
                    it.allowedKeys("schoolId", "accountId", "schoolName", "accountName")
                    it.nonEmptyString("schoolId")
                    it.nonEmptyString("accountId")
                    listOf(it.string("schoolName"), it.string("accountName"))
                        .filter(String::isNotBlank).joinToString(" · ")
                }
                val termLabel = term?.let {
                    it.allowedKeys("key", "label")
                    it.nonEmptyString("key")
                    it.nonEmptyString("label")
                }
                val palette = json.objectValue("palette")
                palette.allowedKeys("light", "dark")
                val days = json.array("days").objects().map(::parseDay)
                widgetPayloadCheck(
                    days.zipWithNext().all { (first, second) -> first.date < second.date },
                    "days 日期顺序",
                )
                widgetPayloadCheck(status == "ready" || days.isEmpty(), "days 状态")
                widgetPayloadCheck((status == "noAccount") == (account == null), "account 状态")
                widgetPayloadCheck(
                    status !in setOf("ready", "calendarMissing") || term != null,
                    "term 状态",
                )
                widgetPayloadCheck(status != "noAccount" || term == null, "term 状态")
                return ScheduleWidgetSnapshot(
                    generatedAt, appearance, status, accountLabel, termLabel,
                    if (account != null && term != null) ScheduleWidgetSource(
                        account.nonEmptyString("schoolId"), account.nonEmptyString("accountId"),
                        term.nonEmptyString("key"),
                    ) else null,
                    parseColors(palette.objectValue("light")),
                    parseColors(palette.objectValue("dark")), days,
                )
            } catch (_: JSONException) {
                invalidWidgetPayload("JSON")
            }
        }

        fun parseColors(json: JSONObject): ScheduleWidgetColors {
            json.allowedKeys("surface", "primary", "text", "secondary", "outline", "card")
            val surface = json.color("surface")
            return ScheduleWidgetColors(
                surface,
                json.color("primary"),
                json.color("text"),
                json.color("secondary"),
                json.color("outline"),
                if (json.has("card")) json.color("card") else surface,
            )
        }

        private fun parseDay(json: JSONObject): ScheduleWidgetDay {
            json.allowedKeys("date", "week", "byPeriod", "lessons")
            val date = scheduleWidgetDate(json.string("date"))
            val week = json.integer("week")
            widgetPayloadCheck(week in 1..Int.MAX_VALUE.toLong(), "week")
            val byPeriod = json.get("byPeriod") as? Boolean
                ?: invalidWidgetPayload("byPeriod")
            val lessons = json.array("lessons").objects().map(::parseLesson)
            widgetPayloadCheck(lessons.isNotEmpty(), "lessons")
            widgetPayloadCheck(lessons.map { it.id }.distinct().size == lessons.size, "lessons 标识")
            return ScheduleWidgetDay(date, week.toInt(), byPeriod, lessons)
        }

        private fun parseLesson(json: JSONObject): ScheduleWidgetLesson {
            json.allowedKeys("id", "title", "periodLabel", "location", "place", "teacher", "startMinutes", "endMinutes", "periods")
            val start = json.nullableMinute("startMinutes")
            val end = json.nullableMinute("endMinutes")
            widgetPayloadCheck((start == null) == (end == null), "课程作息")
            widgetPayloadCheck(start == null || start < end!!, "课程作息")
            val periods = json.array("periods").objects().map {
                it.allowedKeys("startMinutes", "endMinutes")
                val from = it.minute("startMinutes")
                val to = it.minute("endMinutes")
                widgetPayloadCheck(from < to, "课节作息")
                ScheduleWidgetPeriod(from, to)
            }
            if (start != null) {
                widgetPayloadCheck(
                    periods.isNotEmpty() && periods.first().start == start && periods.last().end == end &&
                        periods.zipWithNext().all { (first, second) -> first.end <= second.start },
                    "完整课程作息",
                )
            }
            return ScheduleWidgetLesson(
                json.nonEmptyString("id"), json.nonEmptyString("title"), json.string("periodLabel"),
                // Version-1 snapshots predate "place"; default missing to "".
                json.string("location"), json.nullableString("place") ?: "", json.nullableString("teacher"), start, end, periods,
            )
        }
    }
}

internal fun scheduleWidgetDate(value: String): LocalDate {
    val date = try {
        LocalDate.parse(value)
    } catch (_: DateTimeParseException) {
        invalidWidgetPayload("date")
    }
    widgetPayloadCheck(date.toString() == value && date.year in 1..9999, "date")
    return date
}

internal fun scheduleWidgetClock(minutes: Int): String =
    "%02d:%02d".format(java.util.Locale.ROOT, minutes / 60, minutes % 60)

internal class ScheduleWidgetStore(context: Context) {
    private val file = AtomicFile(File(context.filesDir, "schedule_widget.json"))
    private val preferences = context.getSharedPreferences("schedule_widget_status", Context.MODE_PRIVATE)
    private var memoryFailure: ScheduleWidgetException? = null

    val failure: ScheduleWidgetException?
        get() {
            memoryFailure?.let { return it }
            val saved = preferences.getString("failure", null) ?: return null
            return try {
                val json = JSONObject(saved)
                ScheduleWidgetException(
                    json.string("code"), json.string("message"),
                    ScheduleWidgetFailureKind.valueOf(json.string("kind")),
                )
            } catch (_: JSONException) {
                invalidFailureState()
            } catch (_: IllegalArgumentException) {
                invalidFailureState()
            } catch (_: ScheduleWidgetException) {
                invalidFailureState()
            }
        }

    private fun invalidFailureState() = ScheduleWidgetException(
        "widget_status_invalid", "小组件同步状态无效，请打开应用重新同步",
    )

    fun read(): ScheduleWidgetSnapshot? {
        val payload = try {
            if (!file.baseFile.exists()) return null
            file.readFully().toString(Charsets.UTF_8)
        } catch (_: IOException) {
            throw ScheduleWidgetException("widget_read_failed", "小组件课表读取失败，请打开应用重新同步")
        } catch (_: RuntimeException) {
            throw ScheduleWidgetException("widget_read_failed", "小组件课表读取失败，请打开应用重新同步")
        }
        return ScheduleWidgetSnapshot.parse(payload)
    }

    fun theme(snapshot: ScheduleWidgetSnapshot? = null): ScheduleWidgetTheme? {
        val saved = try {
            preferences.getString("theme", null)
        } catch (_: ClassCastException) {
            Log.e("ScheduleWidget", "widget_saved_theme_invalid")
            null
        }
        val savedTheme = if (saved == null) {
            null
        } else {
            try {
                val json = JSONObject(saved)
                json.allowedKeys("appearance", "light", "dark")
                val appearance = json.string("appearance")
                widgetPayloadCheck(appearance in setOf("system", "light", "dark"), "外观")
                ScheduleWidgetTheme(
                    appearance,
                    ScheduleWidgetSnapshot.parseColors(json.objectValue("light")),
                    ScheduleWidgetSnapshot.parseColors(json.objectValue("dark")),
                )
            } catch (_: JSONException) {
                Log.e("ScheduleWidget", "widget_saved_theme_invalid")
                null
            } catch (_: ScheduleWidgetException) {
                Log.e("ScheduleWidget", "widget_saved_theme_invalid")
                null
            }
        }
        if (savedTheme != null || snapshot == null) return savedTheme
        val legacyTheme = ScheduleWidgetTheme(snapshot.appearance, snapshot.light, snapshot.dark)
        if (!preferences.edit().putString("theme", legacyTheme.toJson().toString()).commit()) {
            Log.e("ScheduleWidget", "widget_saved_theme_migration_failed")
        }
        return legacyTheme
    }

    fun settings(): ScheduleWidgetSettings = try {
        ScheduleWidgetSettings(
            showCountdown = preferences.getBoolean("show_countdown", true),
            showLocation = preferences.getBoolean("show_location", true),
            showTeacher = preferences.getBoolean("show_teacher", true),
        )
    } catch (_: ClassCastException) {
        Log.e("ScheduleWidget", "widget_saved_settings_invalid")
        ScheduleWidgetSettings.defaults
    }

    fun writeSettings(settings: ScheduleWidgetSettings) {
        if (!preferences.edit()
                .putBoolean("show_countdown", settings.showCountdown)
                .putBoolean("show_location", settings.showLocation)
                .putBoolean("show_teacher", settings.showTeacher)
                .commit()
        ) {
            throw ScheduleWidgetException(
                "widget_settings_write_failed",
                "小组件显示设置未能保存，请重试",
                ScheduleWidgetFailureKind.DISPLAY,
            )
        }
    }

    fun write(payload: String) {
        val snapshot = ScheduleWidgetSnapshot.parse(payload)
        val theme = ScheduleWidgetTheme(snapshot.appearance, snapshot.light, snapshot.dark)
            .toJson()
            .toString()
        if (!preferences.edit().putString("theme", theme).commit()) {
            throw ScheduleWidgetException(
                "widget_theme_write_failed",
                "小组件外观设置未能保存，请重新同步",
                ScheduleWidgetFailureKind.SNAPSHOT,
            )
        }
        val stream = try {
            file.startWrite()
        } catch (_: IOException) {
            throw ScheduleWidgetException("widget_write_failed", "小组件课表未能保存，请检查本机存储后重试")
        }
        try {
            val bytes = payload.toByteArray(Charsets.UTF_8)
            stream.write(bytes)
            stream.flush()
            stream.fd.sync()
            file.finishWrite(stream)
            // AtomicFile reports a failed rename only to Log; read back before acknowledging publication.
            if (!file.readFully().contentEquals(bytes)) {
                throw IOException("Widget snapshot was not replaced")
            }
        } catch (_: IOException) {
            file.failWrite(stream)
            throw ScheduleWidgetException("widget_write_failed", "小组件课表未能保存，请检查本机存储后重试")
        }
    }

    private fun ScheduleWidgetColors.toJson(): JSONObject = JSONObject()
        .put("surface", surface)
        .put("primary", primary)
        .put("text", text)
        .put("secondary", secondary)
        .put("outline", outline)
        .put("card", card)

    private fun ScheduleWidgetTheme.toJson(): JSONObject = JSONObject()
        .put("appearance", appearance)
        .put("light", light.toJson())
        .put("dark", dark.toJson())

    fun clearFailure() {
        if (!preferences.edit().remove("failure").commit()) {
            throw ScheduleWidgetException(
                "widget_status_failed", "小组件同步状态未能保存，请重试", ScheduleWidgetFailureKind.DISPLAY,
            )
        }
        memoryFailure = null
    }

    fun recordFailure(failure: ScheduleWidgetException) {
        memoryFailure = failure
        if (failure.kind == ScheduleWidgetFailureKind.SNAPSHOT) {
            // This is a derived cache. Removing it also prevents a failed account switch
            // from showing the previous account after a failed error-state write and restart.
            try {
                file.delete()
                if (file.baseFile.exists()) Log.e("ScheduleWidget", "widget_invalid_snapshot_delete_failed")
            } catch (failure: RuntimeException) {
                Log.e("ScheduleWidget", "widget_invalid_snapshot_delete_failed: ${failure.javaClass.simpleName}")
            }
        }
        try {
            val saved = JSONObject()
                .put("code", failure.code)
                .put("message", failure.message)
                .put("kind", failure.kind.name)
                .toString()
            if (preferences.edit().putString("failure", saved).commit()) return
            Log.e("ScheduleWidget", "widget_failure_state_write_failed")
        } catch (_: JSONException) {
            Log.e("ScheduleWidget", "widget_failure_state_invalid")
        } catch (failure: RuntimeException) {
            Log.e("ScheduleWidget", "widget_failure_state_write_failed: ${failure.javaClass.simpleName}")
        }
    }
}

private fun invalidWidgetPayload(field: String): Nothing =
    throw ScheduleWidgetException("widget_payload_invalid", "小组件课表数据无效（$field），请重新同步")

private fun widgetPayloadCheck(valid: Boolean, field: String) {
    if (!valid) invalidWidgetPayload(field)
}

private fun JSONObject.string(key: String): String =
    get(key) as? String ?: invalidWidgetPayload(key)

private fun JSONObject.nonEmptyString(key: String): String =
    string(key).also { widgetPayloadCheck(it.isNotBlank(), key) }

private fun JSONObject.nullableString(key: String): String? =
    if (!has(key) || isNull(key)) null else string(key)

private fun JSONObject.integer(key: String): Long = when (val value = get(key)) {
    is Int -> value.toLong()
    is Long -> value
    else -> invalidWidgetPayload(key)
}

private fun JSONObject.minute(key: String): Int = integer(key).also {
    widgetPayloadCheck(it in 0L..1440L, key)
}.toInt()

private fun JSONObject.nullableMinute(key: String): Int? =
    if (get(key) === JSONObject.NULL) null else minute(key)

private fun JSONObject.color(key: String): Int = integer(key).also {
    widgetPayloadCheck(it in Int.MIN_VALUE.toLong()..0xffffffffL, key)
}.toInt()

private fun JSONObject.objectValue(key: String): JSONObject =
    get(key) as? JSONObject ?: invalidWidgetPayload(key)

private fun JSONObject.nullableObject(key: String): JSONObject? =
    if (get(key) === JSONObject.NULL) null else objectValue(key)

private fun JSONObject.array(key: String): JSONArray =
    get(key) as? JSONArray ?: invalidWidgetPayload(key)

private fun JSONArray.objects(): List<JSONObject> = (0 until length()).map {
    get(it) as? JSONObject ?: invalidWidgetPayload("列表条目")
}

private fun JSONObject.allowedKeys(vararg fields: String) {
    widgetPayloadCheck(keys().asSequence().all { it in fields }, "未知字段")
}
