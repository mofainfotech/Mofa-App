package com.example.sample_flutter_project

import android.content.Intent
import android.os.Bundle
import android.widget.Toast
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.android.FlutterActivityLaunchConfigs
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.sample_flutter_project/share"
    private var sharedData: String? = null
    private var methodChannel: MethodChannel? = null

    override fun getBackgroundMode(): FlutterActivityLaunchConfigs.BackgroundMode {
        return FlutterActivityLaunchConfigs.BackgroundMode.transparent
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleIntent(intent)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleIntent(intent)
    }

    private fun handleIntent(intent: Intent?) {
        if (intent?.action == Intent.ACTION_SEND && intent.type == "text/plain") {
            val text = intent.getStringExtra(Intent.EXTRA_TEXT)
            if (!text.isNullOrEmpty()) {
                sharedData = text
                methodChannel?.invokeMethod("onSharedText", text)
            }
        } else if (intent?.action == Intent.ACTION_MAIN) {
            methodChannel?.invokeMethod("onMainLauncher", null)
        }
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "getSharedData" -> {
                    result.success(sharedData)
                    sharedData = null // clear after reading
                }
                "closeOverlay" -> {
                    val toast = call.argument<String>("toast")
                    if (!toast.isNullOrEmpty()) {
                        Toast.makeText(applicationContext, toast, Toast.LENGTH_SHORT).show()
                    }
                    moveTaskToBack(true)
                    result.success(true)
                }
                "showToast" -> {
                    val msg = call.argument<String>("message") ?: "Download started"
                    Toast.makeText(applicationContext, msg, Toast.LENGTH_SHORT).show()
                    result.success(true)
                }
                "exitApp" -> {
                    finish()
                    result.success(true)
                }
                else -> {
                    result.notImplemented()
                }
            }
        }
    }
}


