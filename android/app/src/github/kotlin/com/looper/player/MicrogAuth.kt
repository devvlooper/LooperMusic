package com.looper.player

import android.accounts.Account
import android.accounts.AccountManager
import android.accounts.AccountManagerCallback
import android.app.Activity
import android.content.ComponentName
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import android.webkit.CookieManager
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.security.KeyStore
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec

/**
 * Google sign-in for online music (github flavor; the play build has a stub).
 * Talks to microG / ReVanced GmsCore through AccountManager, reads the login
 * WebView's cookies, and seals the saved session with an Android Keystore key.
 * Tokens and cookies are never logged.
 */
class MicrogAuth(private val activity: Activity) {
    companion object {
        const val CHANNEL = "com.looper.player/microg"
        private const val CHOOSE_REQUEST_CODE = 9277
        private const val KEY_ALIAS = "looper_account_session"

        // GmsCore builds that can hold Google accounts for other apps.
        private val GMS_PACKAGES = listOf(
            "app.revanced.android.gms",
            "com.google.android.gms",
            "com.mgoogle.android.gms",
        )

        // Google only issues YouTube scopes to apps it knows, so ask GmsCore
        // for the token as YouTube Music. GmsCore shows its own approval dialog.
        private const val YTM_PACKAGE = "com.google.android.apps.youtube.music"

        // YouTube Music's original signing certificate (CN=ytmusic, SHA-1
        // afb0fed5eeaebdd86f56a97742f4b6b33ef59875), read with apksigner from
        // the Play build installed on a test phone, November 2026.
        private const val YTM_CERT =
            "MIIDuzCCAqOgAwIBAgIJAKEkO2fQIFpxMA0GCSqGSIb3DQEBBQUAMHQxCzAJBgNVBAYTAlVTMRMwEQYDVQQIDApDYWxpZm9ybmlh" +
            "MRYwFAYDVQQHDA1Nb3VudGFpbiBWaWV3MRQwEgYDVQQKDAtHb29nbGUgSW5jLjEQMA4GA1UECwwHQW5kcm9pZDEQMA4GA1UEAwwH" +
            "eXRtdXNpYzAeFw0xNDEwMTAxOTE4MTBaFw00MjAyMjUxOTE4MTBaMHQxCzAJBgNVBAYTAlVTMRMwEQYDVQQIDApDYWxpZm9ybmlh" +
            "MRYwFAYDVQQHDA1Nb3VudGFpbiBWaWV3MRQwEgYDVQQKDAtHb29nbGUgSW5jLjEQMA4GA1UECwwHQW5kcm9pZDEQMA4GA1UEAwwH" +
            "eXRtdXNpYzCCASIwDQYJKoZIhvcNAQEBBQADggEPADCCAQoCggEBAN7ZdAMBV+hqhqAbyQEUKGlsQzy471NGE1LpYeq9rQVbZyBr" +
            "EjcEahgotjB1Dv30cq5J8vBjgkH1MsF4yKHjfqtKTZH0SfxecgFVixinzuiqiE7Y2NhqVy/Dq9BT4NaD0Eae1y3bKoux3Apgnxwc" +
            "NXR0TD7/vKcdxe0jF9PwBAMTdmESXP/oXWwYyxKH0hVjxPdVUUsns3TfBd3Zie//DoSdthYyHZs9pU4ZPARa/SM4VLR1+wnOynl3" +
            "+ODhcxsnvM9J3csBAjIoVSKH2WmoQuZKYz/ef3ran6o5shljJ5RaW3uUsQlmgwFhdsndTL8kFgTtZ6ihp33FQMdjPTkMkWMCAwEA" +
            "AaNQME4wHQYDVR0OBBYEFJIbStuhYWO9Xi9hkfJdPn0gz0dBMB8GA1UdIwQYMBaAFJIbStuhYWO9Xi9hkfJdPn0gz0dBMAwGA1Ud" +
            "EwQFMAMBAf8wDQYJKoZIhvcNAQEFBQADggEBAK/aUW/U2lkTQJDLafac6HkNWWBtSyGTZO2P/mduXudzLBZgTKooKl7FT3EkCFvi" +
            "/vMsakGCwDf/xIg1Glv0PVdx29IzTQzHKRBjpy4eBeD4r0RodvamX/O5w510hDihU5JrO8UsiNWtA6mB0vVSUcFQUSMw5tlqeW3O" +
            "Z0v+gq2kmJKQNBwDoHX9i1tlIPdVKlzXzIMa9rux3U5wNDDTgSdkkaf3gXIB9yr4Z+YPS/WuEAzXCzgEBiayDO/SAObuefIu75BH" +
            "rfEkUIlqsGT764bx2HhrVxI2x3EZcuqvkbfslErKb8mcaBNtapkgFrsd81z/cJ9X3zeq4xYfiaEUEm4="
    }

    private val am = AccountManager.get(activity)
    private val main = Handler(Looper.getMainLooper())
    private var pendingChoose: MethodChannel.Result? = null

    fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "detect" -> result.success(detect())
            "chooseAccount" -> chooseAccount(call.argument<String>("type")!!, result)
            "token" -> token(
                call.argument<String>("name")!!,
                call.argument<String>("type")!!,
                call.argument<String>("scope")!!,
                result,
            )
            "webCookies" -> result.success(CookieManager.getInstance().getCookie(call.argument<String>("url")))
            "clearWebCookies" -> CookieManager.getInstance().removeAllCookies {
                CookieManager.getInstance().flush()
                result.success(null)
            }
            "seal" -> result.success(seal(call.argument<String>("text")!!))
            "open" -> result.success(open(call.argument<String>("text")!!))
            else -> result.notImplemented()
        }
    }

    /** {variant, package, accountType}; variant is revanced, microg, vanced, playServices or none. */
    private fun detect(): Map<String, String?> {
        var playServices = false
        for (pkg in GMS_PACKAGES) {
            if (!installed(pkg)) continue
            if (pkg == "com.google.android.gms" && !isMicrog(pkg)) {
                playServices = true // real Play Services never issues YouTube tokens to us
                continue
            }
            val type = am.authenticatorTypes.firstOrNull { it.packageName == pkg }?.type ?: continue
            val variant = when (pkg) {
                "app.revanced.android.gms" -> "revanced"
                "com.mgoogle.android.gms" -> "vanced"
                else -> "microg"
            }
            return mapOf("variant" to variant, "package" to pkg, "accountType" to type)
        }
        return mapOf("variant" to if (playServices) "playServices" else "none")
    }

    private fun installed(pkg: String) = try {
        activity.packageManager.getPackageInfo(pkg, 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    // Upstream microG ships as com.google.android.gms; its settings screen tells it apart.
    private fun isMicrog(pkg: String) = try {
        activity.packageManager.getActivityInfo(ComponentName(pkg, "org.microg.gms.ui.SettingsActivity"), 0)
        true
    } catch (_: PackageManager.NameNotFoundException) {
        false
    }

    // The system picker also makes the chosen account visible to Looper, so
    // no GET_ACCOUNTS permission is needed.
    private fun chooseAccount(type: String, result: MethodChannel.Result) {
        pendingChoose?.success(null) // superseded
        pendingChoose = result
        val intent = AccountManager.newChooseAccountIntent(
            null, null, arrayOf(type), null, null, null, null,
        )
        try {
            activity.startActivityForResult(intent, CHOOSE_REQUEST_CODE)
        } catch (e: Exception) {
            pendingChoose = null
            result.success(null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode != CHOOSE_REQUEST_CODE) return false
        val result = pendingChoose ?: return true
        pendingChoose = null
        result.success(
            if (resultCode == Activity.RESULT_OK) data?.getStringExtra(AccountManager.KEY_ACCOUNT_NAME) else null,
        )
        return true
    }

    /** {token} or {error}. For a weblogin: scope the token is a sign-in URL. */
    private fun token(name: String, type: String, scope: String, result: MethodChannel.Result) {
        val account = Account(name, type)
        val options = Bundle().apply {
            putString("overridePackage", YTM_PACKAGE)
            putByteArray("overrideCertificate", Base64.decode(YTM_CERT, Base64.DEFAULT))
        }
        val callback = AccountManagerCallback<Bundle> { future ->
            val reply = try {
                val bundle = future.result
                val token = bundle.getString(AccountManager.KEY_AUTHTOKEN)
                if (token != null) mapOf("token" to token) else mapOf("error" to "no token")
            } catch (e: Exception) {
                mapOf("error" to (e.message ?: e.javaClass.simpleName))
            }
            result.success(reply)
        }
        // With an activity, AccountManager runs GmsCore's approval dialogs itself.
        am.getAuthToken(account, scope, options, activity, callback, main)
    }

    private fun key(): SecretKey {
        val store = KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        (store.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val gen = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, "AndroidKeyStore")
        gen.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return gen.generateKey()
    }

    // AES-256-GCM; the output is base64(iv + ciphertext).
    private fun seal(text: String): String {
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key())
        return Base64.encodeToString(cipher.iv + cipher.doFinal(text.toByteArray()), Base64.NO_WRAP)
    }

    // Null when the key is gone (app data cleared, restored backup): sign in again.
    private fun open(sealed: String): String? = try {
        val raw = Base64.decode(sealed, Base64.NO_WRAP)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, raw, 0, 12))
        String(cipher.doFinal(raw, 12, raw.size - 12))
    } catch (_: Exception) {
        null
    }
}
