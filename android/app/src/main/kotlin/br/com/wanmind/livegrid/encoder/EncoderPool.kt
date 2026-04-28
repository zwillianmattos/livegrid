package br.com.wanmind.livegrid.encoder

import android.media.MediaCodec
import android.util.Log
import br.com.wanmind.livegrid.camera.GlRenderer
import br.com.wanmind.livegrid.stream.TcpPublisher
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

class EncoderPool(private val recordingsDir: File) {

    data class Output(
        val horizontalFile: File?,
        val verticalFile: File?,
    )

    data class Publishers(
        val horizontal: TcpPublisher?,
        val vertical: TcpPublisher?,
    )

    private var horizontal: HardwareEncoder? = null
    private var vertical: HardwareEncoder? = null
    private var horizontalTarget: GlRenderer.Target? = null
    private var verticalTarget: GlRenderer.Target? = null
    private var publishers: Publishers = Publishers(null, null)

    fun start(
        horizontalProfile: HardwareEncoder.Profile?,
        verticalProfile: HardwareEncoder.Profile?,
        renderer: GlRenderer,
        publishers: Publishers = Publishers(null, null),
        recordToDisk: Boolean = true,
    ): Output {
        val hFile: File?
        val vFile: File?
        if (recordToDisk) {
            if (!recordingsDir.exists()) recordingsDir.mkdirs()
            val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            hFile = if (horizontalProfile != null) File(recordingsDir, "livegrid_${stamp}_horizontal.mp4") else null
            vFile = if (verticalProfile != null) File(recordingsDir, "livegrid_${stamp}_vertical.mp4") else null
        } else {
            hFile = null
            vFile = null
        }
        this.publishers = publishers
        publishers.horizontal?.open()
        publishers.vertical?.open()

        horizontalProfile?.let { hp ->
            val h = HardwareEncoder(hp, hFile, onFrame = { data, pts, flags ->
                val isKey = flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0 ||
                    flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                publishers.horizontal?.publish(data, pts, isKey)
            })
            val hSurface = h.start()
            horizontal = h
            horizontalTarget = renderer.addTarget(
                hSurface,
                hp.width,
                hp.height,
                GlRenderer.CROP_HORIZONTAL_16_9,
                releaseSurface = true,
            )
        }

        verticalProfile?.let { vp ->
            val v = HardwareEncoder(vp, vFile, onFrame = { data, pts, flags ->
                val isKey = flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0 ||
                    flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
                publishers.vertical?.publish(data, pts, isKey)
            })
            val vSurface = v.start()
            vertical = v
            verticalTarget = renderer.addTarget(
                vSurface,
                vp.width,
                vp.height,
                GlRenderer.CROP_VERTICAL_9_16,
                releaseSurface = true,
            )
        }

        Log.i(TAG, "encoders on (file=$recordToDisk, h=${horizontal != null}, v=${vertical != null}, hPub=${publishers.horizontal != null}, vPub=${publishers.vertical != null})")
        return Output(hFile, vFile)
    }

    fun setHorizontalBitrate(bps: Int) = horizontal?.setBitrate(bps)
    fun setVerticalBitrate(bps: Int) = vertical?.setBitrate(bps)
    fun setFrameRate(fps: Int) {
        horizontal?.setFrameRate(fps)
        vertical?.setFrameRate(fps)
    }
    fun requestKeyframes() {
        horizontal?.requestSyncFrame()
        vertical?.requestSyncFrame()
    }

    fun horizontalBitrate(): Int = horizontal?.bitrateMeter?.sampleBps() ?: 0
    fun verticalBitrate(): Int = vertical?.bitrateMeter?.sampleBps() ?: 0
    fun currentFps(): Int = horizontal?.fps() ?: vertical?.fps() ?: 0

    fun horizontalPublisherSnapshot(): TcpPublisher.Snapshot? =
        publishers.horizontal?.snapshot()
    fun verticalPublisherSnapshot(): TcpPublisher.Snapshot? =
        publishers.vertical?.snapshot()

    val isRunning: Boolean get() = horizontal != null || vertical != null

    fun stop(renderer: GlRenderer) {
        horizontalTarget?.let { renderer.removeTarget(it) }
        verticalTarget?.let { renderer.removeTarget(it) }
        horizontalTarget = null
        verticalTarget = null
        horizontal?.stop()
        vertical?.stop()
        horizontal = null
        vertical = null
        publishers.horizontal?.close()
        publishers.vertical?.close()
        publishers = Publishers(null, null)
    }

    companion object {
        private const val TAG = "EncoderPool"
    }
}
