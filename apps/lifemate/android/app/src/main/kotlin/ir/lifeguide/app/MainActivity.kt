package ir.lifeguide.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "lifeguide/local_write_guard")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getBlocked" -> result.success(LocalWriteGuard.getBlocked())
                    "beginWrite" -> {
                        val token = LocalWriteGuard.beginWrite()
                        if (token == null) {
                            result.error("local_storage_restart_required", null, null)
                        } else {
                            result.success(token)
                        }
                    }
                    "completeWrite" -> {
                        val token = call.arguments as? String
                        if (token != null && LocalWriteGuard.completeWrite(token)) {
                            result.success(true)
                        } else {
                            result.error("local_storage_restart_required", null, null)
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
