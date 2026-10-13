package dev.spomaxxing.app

import android.content.Intent
import com.ryanheise.audioservice.AudioServiceActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : AudioServiceActivity() {
    private var libraryBridge: LibraryBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        libraryBridge?.dispose()
        libraryBridge = LibraryBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun cleanUpFlutterEngine(flutterEngine: FlutterEngine) {
        libraryBridge?.dispose()
        libraryBridge = null
        super.cleanUpFlutterEngine(flutterEngine)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        super.onActivityResult(requestCode, resultCode, data)
        libraryBridge?.onActivityResult(requestCode, resultCode, data)
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        libraryBridge?.onRequestPermissionsResult(requestCode, grantResults)
    }

    override fun onDestroy() {
        libraryBridge?.dispose()
        libraryBridge = null
        super.onDestroy()
    }
}
