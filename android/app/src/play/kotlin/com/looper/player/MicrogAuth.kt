package com.looper.player

import android.app.Activity
import android.content.Intent
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/** Play build: no online music, so no Google sign-in. See src/github for the real one. */
@Suppress("UNUSED_PARAMETER")
class MicrogAuth(activity: Activity) {
    companion object {
        const val CHANNEL = "com.looper.player/microg"
    }

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        if (call.method == "detect") result.success(mapOf("variant" to "none")) else result.notImplemented()
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean = false
}
