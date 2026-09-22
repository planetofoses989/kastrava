package pp.ua.kastrava

import android.os.Bundle
import android.widget.ArrayAdapter
import android.widget.ListView
import android.widget.Toast
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity

class DownloadsActivity : AppCompatActivity() {

    private lateinit var app: KastravaApp
    private lateinit var adapter: ArrayAdapter<String>

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        app = application as KastravaApp
        setContentView(R.layout.activity_downloads)

        val list: ListView = findViewById(R.id.dlList)
        adapter = ArrayAdapter(this, android.R.layout.simple_list_item_1, labels())
        list.adapter = adapter
        list.setOnItemClickListener { _, _, pos, _ ->
            val item = app.downloads.items.getOrNull(pos) ?: return@setOnItemClickListener
            AlertDialog.Builder(this)
                .setTitle(item.filename)
                .setMessage("State: ${item.state}\nSize: ${formatSize(item.received)}")
                .setPositiveButton("Save to Downloads") { _, _ ->
                    Thread {
                        val ok = app.downloads.saveToDownloads(item)
                        runOnUiThread {
                            Toast.makeText(
                                this,
                                if (ok) "Saved to Downloads" else "Save failed",
                                Toast.LENGTH_SHORT,
                            ).show()
                        }
                    }.start()
                }
                .setNegativeButton("Close", null)
                .show()
        }
    }

    override fun onResume() {
        super.onResume()
        adapter.clear()
        adapter.addAll(labels())
    }

    private fun labels(): List<String> {
        val items = app.downloads.items
        if (items.isEmpty()) return listOf("No downloads this session.")
        return items.map {
            val extra = when (it.state) {
                "downloading" -> "… ${formatSize(it.received)}"
                "done" -> "· ${formatSize(it.received)}"
                else -> "· ${it.state}"
            }
            "${it.filename} $extra"
        }
    }

    private fun formatSize(n: Long): String {
        if (n < 0) return "?"
        if (n < 1024) return "$n B"
        if (n < 1024 * 1024) return "${n / 1024} KB"
        return "${n / (1024 * 1024)} MB"
    }
}
