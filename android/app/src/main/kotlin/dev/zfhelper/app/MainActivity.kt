package dev.zfhelper.app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.provider.Settings
import android.webkit.CookieManager
import android.webkit.WebViewClient
import androidx.core.content.FileProvider
import androidx.webkit.CookieManagerCompat
import androidx.webkit.WebViewFeature
import com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.io.IOException

private const val LOGIN_COOKIE_CHANNEL = "zfhelper/login_cookies"
private const val APP_INSTALLER_CHANNEL = "zfhelper/app_installer"
private const val APK_MIME_TYPE = "application/vnd.android.package-archive"

class MainActivity : FlutterActivity() {
    private var loginCookieChannel: MethodChannel? = null
    private var appInstallerChannel: MethodChannel? = null
    private val selectionRuntime: SelectionRuntimeHost
        get() = (application as ZfHelperApplication).selectionRuntime
    private val scheduleWidgets: ScheduleWidgetHost
        get() = (application as ZfHelperApplication).scheduleWidgets

    override fun onCreate(savedInstanceState: Bundle?) {
        scheduleWidgets.receiveLaunch(intent)
        super.onCreate(savedInstanceState)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        scheduleWidgets.receiveLaunch(intent)
    }

    override fun provideFlutterEngine(context: Context): FlutterEngine =
        (application as ZfHelperApplication).sharedFlutterEngine

    override fun shouldDestroyEngineWithHost(): Boolean = false

    override fun onResume() {
        super.onResume()
        selectionRuntime.activityResumed(this)
        scheduleWidgets.activityResumed(this)
    }

    override fun onPause() {
        selectionRuntime.activityPaused(this)
        scheduleWidgets.activityPaused(this)
        super.onPause()
    }

    override fun onDestroy() {
        selectionRuntime.activityDestroyed(this)
        scheduleWidgets.activityDestroyed(this)
        super.onDestroy()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode == SELECTION_NOTIFICATION_PERMISSION_REQUEST) {
            selectionRuntime.notificationPermissionResult()
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        loginCookieChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            LOGIN_COOKIE_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "getCookieInfo" -> readCookieInfo(call, result)
                    "destroyLoginWebView" -> destroyLoginWebView(flutterEngine, call, result)
                    else -> result.notImplemented()
                }
            }
        }
        appInstallerChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            APP_INSTALLER_CHANNEL,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "installApk" -> installApk(call, result)
                    else -> result.notImplemented()
                }
            }
        }
    }

    private fun installApk(call: MethodCall, result: MethodChannel.Result) {
        val path = call.argument<String>("path")
        if (path.isNullOrBlank()) {
            result.error("invalid_path", "安装文件路径无效", null)
            return
        }
        val file = try {
            File(path).canonicalFile
        } catch (_: IOException) {
            result.error("invalid_path", "安装文件路径无效", null)
            return
        }
        // Only expose files inside this app's own cache directory through the
        // FileProvider grant; anything else is rejected.
        val appCacheDir = cacheDir.canonicalFile
        if (!file.path.startsWith(appCacheDir.path) || !file.isFile) {
            result.error("file_not_found", "安装包不存在或已失效，请重新下载", null)
            return
        }
        if (!packageManager.canRequestPackageInstalls()) {
            // Let the user grant "install unknown apps" for this app, then
            // return a recognizable error so the UI can ask for a retry.
            try {
                startActivity(
                    Intent(
                        Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES,
                        Uri.parse("package:$packageName"),
                    ),
                )
            } catch (_: RuntimeException) {
                result.error("permission_settings_failed", "无法打开安装权限页面", null)
                return
            }
            result.error("permission_required", "需要允许安装未知应用后重试", null)
            return
        }
        val uri = try {
            FileProvider.getUriForFile(this, "$packageName.fileprovider", file)
        } catch (_: IllegalArgumentException) {
            result.error("install_failed", "安装文件无法访问，请重新下载", null)
            return
        }
        val intent = Intent(Intent.ACTION_VIEW)
            .setDataAndType(uri, APK_MIME_TYPE)
            .addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION or Intent.FLAG_ACTIVITY_NEW_TASK)
        if (intent.resolveActivity(packageManager) == null) {
            result.error("no_installer", "未找到可用的系统安装器", null)
            return
        }
        try {
            startActivity(intent)
            result.success(null)
        } catch (_: RuntimeException) {
            result.error("install_failed", "安装器启动失败，请稍后重试", null)
        }
    }

    private fun destroyLoginWebView(
        flutterEngine: FlutterEngine,
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        try {
            val keepAliveId = call.argument<String>("keepAliveId")
            if (keepAliveId.isNullOrEmpty()) {
                result.error("invalid_view_id", "网页登录组件标识无效", null)
                return
            }
            val plugin = flutterEngine.plugins.get(InAppWebViewFlutterPlugin::class.java)
                as? InAppWebViewFlutterPlugin
            val manager = plugin?.inAppWebViewManager
            if (manager == null) {
                result.error("browser_unavailable", "网页登录组件不可用", null)
                return
            }
            val flutterView = manager.keepAliveWebViews[keepAliveId]
            val webView = flutterView?.webView
            webView?.stopLoading()
            // In plugin 1.1.3, disposeKeepAlive cleans plugin references but
            // schedules destroy() in a later about:blank onPageFinished.
            manager.disposeKeepAlive(keepAliveId)
            manager.keepAliveWebViews.remove(keepAliveId)
            if (webView != null) {
                // These operations stay in the same UI-thread callback, before
                // that pending page callback can run. Destroy synchronously.
                webView.stopLoading()
                webView.setWebViewClient(WebViewClient())
                webView.destroy()
            }
            result.success(null)
        } catch (_: RuntimeException) {
            result.error("browser_dispose_failed", "网页登录组件未能完成关闭", null)
        }
    }

    private fun readCookieInfo(call: MethodCall, result: MethodChannel.Result) {
        try {
            val url = call.argument<String>("url")
            val uri = url?.let(Uri::parse)
            if (url == null || uri == null ||
                uri.scheme !in setOf("http", "https") ||
                uri.host.isNullOrEmpty() ||
                !uri.userInfo.isNullOrEmpty() ||
                uri.fragment != null
            ) {
                result.error("invalid_cookie_url", "Cookie 地址无效", null)
                return
            }
            if (!WebViewFeature.isFeatureSupported(WebViewFeature.GET_COOKIE_INFO)) {
                result.error(
                    "cookie_info_unavailable",
                    "系统 WebView 不支持完整 Cookie 信息",
                    null,
                )
                return
            }
            // Forward the raw attributes; the plugin's parsed DTO incorrectly
            // adds Max-Age seconds to an epoch-milliseconds timestamp.
            result.success(
                CookieManagerCompat.getCookieInfo(CookieManager.getInstance(), url),
            )
        } catch (_: RuntimeException) {
            result.error("cookie_read_failed", "无法读取网页登录会话", null)
        }
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        loginCookieChannel?.setMethodCallHandler(null)
        loginCookieChannel = null
        appInstallerChannel?.setMethodCallHandler(null)
        appInstallerChannel = null
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
