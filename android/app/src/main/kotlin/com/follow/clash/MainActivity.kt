package com.follow.clash

import android.content.Intent
import im.crisp.client.external.Crisp
import im.crisp.client.external.ChatActivity
import io.flutter.plugin.common.MethodChannel

import com.follow.clash.plugins.AppPlugin
import com.follow.clash.plugins.BatteryPlugin
import com.follow.clash.plugins.LinkPlugin
import com.follow.clash.plugins.ServicePlugin
import com.follow.clash.plugins.TilePlugin
import com.follow.clash.plugins.WifiSsidPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var configuredCrispWebsiteId: String? = null
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.plugins.add(AppPlugin())
        flutterEngine.plugins.add(BatteryPlugin())
        flutterEngine.plugins.add(LinkPlugin())
        flutterEngine.plugins.add(ServicePlugin())
        flutterEngine.plugins.add(TilePlugin())
        flutterEngine.plugins.add(WifiSsidPlugin())
        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "qndxx/crisp",
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "openChat" -> {
                    val websiteId = call.argument<String>("websiteId")
                    if (websiteId.isNullOrBlank()) {
                        result.error("CRISP_CONFIG", "Missing Crisp Website ID", null)
                    } else {
                        try {
                            if (configuredCrispWebsiteId != websiteId) {
                                Crisp.configure(applicationContext, websiteId)
                                configuredCrispWebsiteId = websiteId
                            }
                            startActivity(Intent(this, ChatActivity::class.java))
                            result.success(null)
                        } catch (error: Exception) {
                            result.error("CRISP_OPEN_FAILED", error.message, null)
                        }
                    }
                }
                else -> result.notImplemented()
            }
        }
        ServiceState.attachFlutterEngine(flutterEngine)
    }

    override fun onDestroy() {
        flutterEngine?.let(ServiceState::detachFlutterEngine)
        super.onDestroy()
    }
}
