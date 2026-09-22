package pp.ua.kastrava

import android.content.Context
import android.util.Base64
import org.bouncycastle.jce.provider.BouncyCastleProvider
import org.json.JSONObject
import java.net.HttpURLConnection
import java.net.URL
import java.security.KeyFactory
import java.security.Security
import java.security.Signature
import java.security.spec.X509EncodedKeySpec

/**
 * Premium licensing against https://nexufog.pp.ua — same protocol as desktop:
 * POST /api/activate { key, machine_id } -> { license: { key, payload, sig } }.
 * The payload signature (Ed25519, server-held private key) is verified
 * on-device before the license is stored, exactly like src/license.js.
 */
class LicenseManager(private val context: Context) {

    companion object {
        const val API = "https://nexufog.pp.ua"
        private const val PREFS = "kastrava_license"
        // SPKI DER of the kastrasoft Ed25519 public key (same key as
        // src/kastraPublic.js on desktop). Signature authority, not a secret.
        private const val PUBLIC_KEY_B64 =
            "MCowBQYDK2VwAyEAxI4SQmMrvkzEaNmw+ZgR+pmuS5J5pB6yER+5qZ9l7IQ="

        // Canonical bytes the server signs: Node JSON.stringify(payload) with
        // insertion order sub, mid, product, edition, iss, iat, exp, sub_end?.
        // Values are alphanumeric/dashes/ints, so plain quoting is exact.
        fun canonicalPayloadBytes(payload: JSONObject): ByteArray {
            val sb = StringBuilder("{")
            fun str(k: String) {
                if (sb.length > 1) sb.append(',')
                sb.append('"').append(k).append("\":\"")
                    .append(payload.getString(k)).append('"')
            }
            fun num(k: String) {
                if (sb.length > 1) sb.append(',')
                sb.append('"').append(k).append("\":").append(payload.getLong(k))
            }
            str("sub"); str("mid"); str("product"); str("edition"); str("iss")
            num("iat"); num("exp")
            if (payload.has("sub_end") && !payload.isNull("sub_end")) num("sub_end")
            sb.append('}')
            return sb.toString().toByteArray(Charsets.UTF_8)
        }
    }

    data class Status(
        val activated: Boolean,
        val reason: String?,
        val expiresAtMs: Long?,
        val subEndMs: Long?,
        val grace: Boolean,
        val key: String?,
    )

    private val prefs = context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)

    fun androidId(): String =
        Settings.Secure.getString(context.contentResolver, Settings.Secure.ANDROID_ID)
            ?: "unknown"

    fun machineCode(): String = MachineCode.current(androidId())

    fun status(): Status {
        val key = prefs.getString("key", null)
        val payloadRaw = prefs.getString("payload", null)
        val sig = prefs.getString("sig", null)
        val machine = machineCode()
        if (key == null || payloadRaw == null || sig == null)
            return Status(false, "no_license", null, null, false, null)
        return try {
            val payload = JSONObject(payloadRaw)
            if (!verifySignature(payload, sig))
                return Status(false, "bad_signature", null, null, false, key)
            if (payload.optString("iss") != "kastrasoft" ||
                payload.optString("product") != "kastrava-premium"
            ) return Status(false, "bad_issuer", null, null, false, key)
            if (!payload.optString("mid").equals(machine, ignoreCase = true))
                return Status(false, "machine_mismatch", null, null, false, key)
            val now = System.currentTimeMillis() / 1000
            val exp = payload.optLong("exp", 0)
            if (exp != 0L && now > exp)
                return Status(false, "expired", exp * 1000, null, false, key)
            val subEnd = if (payload.has("sub_end") && !payload.isNull("sub_end"))
                payload.optLong("sub_end") * 1000 else null
            val grace = subEnd != null && now > subEnd / 1000
            Status(true, null, if (exp != 0L) exp * 1000 else null, subEnd, grace, key)
        } catch (e: Exception) {
            Status(false, "bad_signature", null, null, false, key)
        }
    }

    fun verifySignature(payload: JSONObject, sigB64: String): Boolean {
        return try {
            if (Security.getProvider("BC") == null)
                Security.addProvider(BouncyCastleProvider())
            val keyBytes = Base64.decode(PUBLIC_KEY_B64, Base64.DEFAULT)
            val pub = KeyFactory.getInstance("Ed25519", "BC")
                .generatePublic(X509EncodedKeySpec(keyBytes))
            val sig = Signature.getInstance("Ed25519", "BC")
            sig.initVerify(pub)
            sig.update(canonicalPayloadBytes(payload))
            sig.verify(Base64.decode(sigB64, Base64.DEFAULT))
        } catch (e: Exception) {
            false
        }
    }

    /** Network call — must run off the main thread. Returns null on success. */
    fun activate(key: String): String? {
        val machine = machineCode()
        return try {
            val url = URL("$API/api/activate")
            val conn = (url.openConnection() as HttpURLConnection).apply {
                requestMethod = "POST"
                setRequestProperty("Content-Type", "application/json")
                connectTimeout = 20000
                readTimeout = 20000
                doOutput = true
            }
            val body = JSONObject()
                .put("key", key.trim())
                .put("machine_id", machine)
                .toString()
            conn.outputStream.use { it.write(body.toByteArray(Charsets.UTF_8)) }
            val code = conn.responseCode
            val text = try {
                (if (code in 200..299) conn.inputStream else conn.errorStream)
                    ?.bufferedReader()?.readText() ?: ""
            } catch (e: Exception) { "" }
            if (code !in 200..299) {
                val err = try { JSONObject(text).optString("error") } catch (e: Exception) { "" }
                return when (err) {
                    "machine_mismatch" -> "This key is already activated on another device."
                    "invalid_key" -> "Unknown license key."
                    else -> "Activation failed (HTTP $code)."
                }
            }
            val lic = JSONObject(text).optJSONObject("license")
                ?: return "Empty activation response."
            val payload = lic.getJSONObject("payload")
            val sig = lic.getString("sig")
            if (!verifySignature(payload, sig)) return "Server signature invalid."
            if (!payload.optString("mid").equals(machine, ignoreCase = true))
                return "License is bound to a different device."
            prefs.edit()
                .putString("key", lic.optString("key", key.trim()))
                .putString("payload", payload.toString())
                .putString("sig", sig)
                .putLong("activated_at", System.currentTimeMillis())
                .apply()
            null
        } catch (e: Exception) {
            "Could not reach the Kastrava license server. Check your connection."
        }
    }

    fun clear() {
        prefs.edit().clear().apply()
    }
}
