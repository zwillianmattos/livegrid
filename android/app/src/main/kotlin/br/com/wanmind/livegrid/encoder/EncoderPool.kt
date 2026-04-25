package br.com.wanmind.livegrid.encoder

import android.media.MediaCodec
import android.util.Log
import br.com.wanmind.livegrid.camera.GlRenderer
import br.com.wanmind.livegrid.stream.UdpPublisher
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
        val horizontal: UdpPublisher?,
        val vertical: UdpPublisher?,
    )

    private var horizontal: HardwareEncoder? = null
    private var vertical: HardwareEncoder? = null
    private var horizontalTarget: GlRenderer.Target? = null
    private var verticalTarget: GlRenderer.Target? = null
    private var publishers: Publishers = Publishers(null, null)

    fun start(
        horizontalProfile: HardwareEncoder.Profile,
        verticalProfile: HardwareEncoder.Profile,
        renderer: GlRenderer,
        publishers: Publishers = Publishers(null, null),
        recordToDisk: Boolean = true,
    ): Output {
        val hFile: File?
        val vFile: File?
        if (recordToDisk) {
            if (!recordingsDir.exists()) recordingsDir.mkdirs()
            val stamp = SimpleDateFormat("yyyyMMdd_HHmmss", Locale.US).format(Date())
            hFile = File(recordingsDir, "h_$stamp.h264")
            vFile = File(recordingsDir, "v_$stamp.h264")
        } else {
            hFile = null
            vFile = null
        }
        this.publishers = publishers
        publishers.horizontal?.open()
        publishers.vertical?.open()

        val h = HardwareEncoder(horizontalProfile, hFile, onFrame = { data, pts, flags ->
            val isKey = flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0 ||
                flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
            publishers.horizontal?.publish(data, pts, isKey)
        })
        val v = HardwareEncoder(verticalProfile, vFile, onFrame = { data, pts, flags ->
            val isKey = flags and MediaCodec.BUFFER_FLAG_KEY_FRAME != 0 ||
                flags and MediaCodec.BUFFER_FLAG_CODEC_CONFIG != 0
            publishers.vertical?.publish(data, pts, isKey)
        })

        val hSurface = h.start()
        val vSurface = v.start()
        horizontal = h
        vertical = v

        horizontalTarget = renderer.addTarget(
            hSurface,
            horizontalProfile.width,
            horizontalProfile.height,
            GlRenderer.CROP_HORIZONTAL_16_9,
            releaseSurface = true,
        )
        verticalTarget = renderer.addTarget(
            vSurface,
            verticalProfile.width,
            verticalProfile.height,
            GlRenderer.CROP_VERTICAL_9_16,
            releaseSurface = true,
        )

        Log.i(TAG, "encoders on (file=$recordToDisk, hPub=${publishers.horizontal != null}, vPub=${publishers.vertical != null})")
        return Output(hFile, vFile)
    }

    fun setHorizontalBitrate(bps: Int) = horizontal?.setBitrate(bps)
    fun setVerticalBitrate(bps: Int) = vertical?.setBitrate(bps)
    fun requestKeyframes() {
        horizontal?.requestSyncFrame()
        vertical?.requestSyncFrame()
    }

    fun horizontalBitrate(): Int = horizontal?.bitrateMeter?.sampleBps() ?: 0
    fun verticalBitrate(): Int = vertical?.bitrateMeter?.sampleBps() ?: 0

    fun horizontalPublisherSnapshot(): UdpPublisher.Snapshot? =
        publishers.horizontal?.snapshot()
    fun verticalPublisherSnapshot(): UdpPublisher.Snapshot? =
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
