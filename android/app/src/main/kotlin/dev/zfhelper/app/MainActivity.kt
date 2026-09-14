package dev.zfhelper.app

import android.net.Uri
import android.webkit.CookieManager
import android.webkit.WebViewClient
import androidx.webkit.CookieManagerCompat
import androidx.webkit.WebViewFeature
import com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

private const val LOGIN_COOKIE_CHANNEL = "zfhelper/login_cookies"

class MainActivity : FlutterActivity() {
    private var loginCookieChannel: MethodChannel? = null

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
        super.cleanUpFlutterEngine(flutterEngine)
    }
}
