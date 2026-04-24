package br.com.wanmind.livegrid

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var bridge: FlutterBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        bridge = FlutterBridge(applicationContext, flutterEngine)
    }

    override fun onDestroy() {
        bridge?.detach()
        bridge = null
        super.onDestroy()
    }
}
