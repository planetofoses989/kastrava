package pp.ua.kastrava

import android.content.Intent
import android.net.Uri
import android.os.Bundle
import android.widget.Button
import android.widget.EditText
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity

class PremiumActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as KastravaApp
        setContentView(R.layout.activity_premium)

        val status: TextView = findViewById(R.id.premStatus)
        val machine: TextView = findViewById(R.id.premMachine)
        val key: EditText = findViewById(R.id.premKey)
        val msg: TextView = findViewById(R.id.premMsg)
        val activate: Button = findViewById(R.id.premActivate)
        val buy: Button = findViewById(R.id.premBuy)

        machine.text = app.license.machineCode()

        fun refresh() {
            val st = app.license.status()
            status.text = if (st.activated) {
                val exp = st.expiresAtMs?.let {
                    java.text.DateFormat.getDateInstance().format(java.util.Date(it))
                }
                if (st.grace) "Premium active — renewal due (grace until $exp)"
                else "Premium active" + (if (exp != null) " · until $exp" else "")
            } else {
                "Free core" + (if (st.reason != null && st.reason != "no_license") " (${st.reason})" else "")
            }
            if (st.key != null && key.text.isBlank()) key.setText(st.key)
        }
        refresh()

        activate.setOnClickListener {
            val k = key.text.toString().trim()
            if (k.isEmpty()) {
                msg.text = "Enter the license key from your purchase."
                return@setOnClickListener
            }
            msg.text = "Activating…"
            activate.isEnabled = false
            Thread {
                val err = app.license.activate(k)
                runOnUiThread {
                    activate.isEnabled = true
                    if (err == null) {
                        msg.text = "Activated on this device."
                        refresh()
                    } else {
                        msg.text = err
                    }
                }
            }.start()
        }

        buy.setOnClickListener {
            // Checkout lives on the site; the machine code is passed along
            // so the payment page can pre-fill it (same as desktop).
            val url = "https://kastrava.pp.ua/#premium?machine=" +
                Uri.encode(app.license.machineCode())
            startActivity(Intent(Intent.ACTION_VIEW, Uri.parse(url)))
        }
    }
}
