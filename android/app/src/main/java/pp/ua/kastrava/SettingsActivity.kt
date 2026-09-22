package pp.ua.kastrava

import android.os.Bundle
import android.widget.CheckBox
import android.widget.RadioButton
import android.widget.RadioGroup
import android.widget.Toast
import androidx.appcompat.app.AppCompatActivity

class SettingsActivity : AppCompatActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val app = application as KastravaApp
        setContentView(R.layout.activity_settings)

        val engineGroup: RadioGroup = findViewById(R.id.engineGroup)
        val premium = app.license.status().activated
        Prefs.ENGINES.forEach { (key, meta) ->
            val (name, _) = meta
            val locked = !premium && key !in Prefs.FREE_ENGINES
            val rb = RadioButton(this).apply {
                text = if (locked) "$name (Premium)" else name
                tag = key
                isChecked = app.prefs.engine == key
                isEnabled = !locked
            }
            engineGroup.addView(rb)
        }
        engineGroup.setOnCheckedChangeListener { group, checkedId ->
            val rb = group.findViewById<RadioButton>(checkedId) ?: return@setOnCheckedChangeListener
            app.prefs.engine = rb.tag as String
        }

        val themeGroup: RadioGroup = findViewById(R.id.themeGroup)
        when (app.prefs.theme) {
            "light" -> themeGroup.check(R.id.themeLight)
            "dark" -> themeGroup.check(R.id.themeDark)
            else -> themeGroup.check(R.id.themeSystem)
        }
        themeGroup.setOnCheckedChangeListener { _, checkedId ->
            app.prefs.theme = when (checkedId) {
                R.id.themeLight -> "light"
                R.id.themeDark -> "dark"
                else -> "system"
            }
            app.applyTheme()
        }

        val cbBlockers: CheckBox = findViewById(R.id.cbBlockers)
        cbBlockers.isChecked = app.prefs.blockers
        cbBlockers.setOnCheckedChangeListener { _, v -> app.prefs.blockers = v }

        val cbJs: CheckBox = findViewById(R.id.cbJs)
        cbJs.isChecked = app.prefs.javaScript
        cbJs.setOnCheckedChangeListener { _, v ->
            app.prefs.javaScript = v
            Toast.makeText(this, "Applies to new and current tabs", Toast.LENGTH_SHORT).show()
        }
    }
}
