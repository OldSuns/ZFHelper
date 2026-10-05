package dev.zfhelper.app

import android.app.Application
import android.content.res.Configuration
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor

class ZfHelperApplication : Application() {
    val selectionRuntime by lazy { SelectionRuntimeHost(this) }
    val scheduleWidgets by lazy { ScheduleWidgetHost(this) }

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        scheduleWidgets.refreshInBackground()
    }

    // Activity and Service share this engine and its existing Dart repositories.
    val sharedFlutterEngine: FlutterEngine by lazy {
        FlutterEngine(this).also { engine ->
            selectionRuntime.attachEngine(engine)
            scheduleWidgets.attachEngine(engine)
            engine.dartExecutor.executeDartEntrypoint(
                DartExecutor.DartEntrypoint.createDefault(),
            )
        }
    }
}
