package br.com.wanmind.livegrid.camera

import android.graphics.SurfaceTexture
import android.opengl.GLES11Ext
import android.opengl.GLES20
import android.os.Handler
import android.os.HandlerThread
import android.view.Surface
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.FloatBuffer
import java.util.concurrent.CopyOnWriteArrayList

class GlRenderer(private val core: GlCore) {

    data class Target(
        val surface: WindowSurface,
        val width: Int,
        val height: Int,
        val cropMode: Int,
    )

    private val thread = HandlerThread("livegrid-gl").apply { start() }
    val handler: Handler = Handler(thread.looper)

    private var program = 0
    private var aPosition = 0
    private var aTexCoord = 0
    private var uTexMatrix = 0
    private var uCrop = 0
    private var oesTextureId = 0

    private lateinit var inputSurfaceTexture: SurfaceTexture
    private lateinit var inputSurface: Surface

    private var sensorWidth = 0
    private var sensorHeight = 0

    private val targets = CopyOnWriteArrayList<Target>()
    private val texMatrix = FloatArray(16)

    private val vertexBuffer: FloatBuffer = ByteBuffer
        .allocateDirect(QUAD.size * 4)
        .order(ByteOrder.nativeOrder())
        .asFloatBuffer()
        .apply { put(QUAD).position(0) }

    fun setup(onReady: (Surface) -> Unit) {
        handler.post {
            core.makeCurrentNothing()

            program = GlUtils.linkProgram(VERTEX_SHADER, FRAGMENT_SHADER)
            aPosition = GLES20.glGetAttribLocation(program, "aPosition")
            aTexCoord = GLES20.glGetAttribLocation(program, "aTexCoord")
            uTexMatrix = GLES20.glGetUniformLocation(program, "uTexMatrix")
            uCrop = GLES20.glGetUniformLocation(program, "uCrop")

            val tex = IntArray(1)
            GLES20.glGenTextures(1, tex, 0)
            oesTextureId = tex[0]
            GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTextureId)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MIN_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_MAG_FILTER, GLES20.GL_LINEAR)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_S, GLES20.GL_CLAMP_TO_EDGE)
            GLES20.glTexParameteri(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, GLES20.GL_TEXTURE_WRAP_T, GLES20.GL_CLAMP_TO_EDGE)

            inputSurfaceTexture = SurfaceTexture(oesTextureId)
            inputSurfaceTexture.setOnFrameAvailableListener({ drawFrame() }, handler)
            inputSurface = Surface(inputSurfaceTexture)
            onReady(inputSurface)
        }
    }

    fun configureInputSize(width: Int, height: Int) {
        handler.post {
            sensorWidth = width
            sensorHeight = height
            inputSurfaceTexture.setDefaultBufferSize(width, height)
        }
    }

    fun addTarget(surface: Surface, width: Int, height: Int, cropMode: Int, releaseSurface: Boolean = false): Target {
        val ws = WindowSurface(core, surface, releaseSurface = releaseSurface)
        val target = Target(ws, width, height, cropMode)
        targets.add(target)
        return target
    }

    fun removeTarget(target: Target) {
        targets.remove(target)
        handler.post {
            try {
                target.surface.release()
            } catch (_: Throwable) {
            }
        }
    }

    private fun drawFrame() {
        if (sensorWidth == 0 || sensorHeight == 0) return
        inputSurfaceTexture.updateTexImage()
        inputSurfaceTexture.getTransformMatrix(texMatrix)
        val ts = inputSurfaceTexture.timestamp

        val snapshot = targets.toList()
        for (target in snapshot) {
            try {
                target.surface.makeCurrent()
                drawInto(target)
                target.surface.swapBuffers(ts)
            } catch (_: Throwable) {
            }
        }
    }

    private fun drawInto(target: Target) {
        GLES20.glViewport(0, 0, target.width, target.height)
        GLES20.glClearColor(0f, 0f, 0f, 1f)
        GLES20.glClear(GLES20.GL_COLOR_BUFFER_BIT)
        GLES20.glUseProgram(program)

        vertexBuffer.position(0)
        GLES20.glEnableVertexAttribArray(aPosition)
        GLES20.glVertexAttribPointer(aPosition, 2, GLES20.GL_FLOAT, false, 4 * 4, vertexBuffer)
        vertexBuffer.position(2)
        GLES20.glEnableVertexAttribArray(aTexCoord)
        GLES20.glVertexAttribPointer(aTexCoord, 2, GLES20.GL_FLOAT, false, 4 * 4, vertexBuffer)

        GLES20.glUniformMatrix4fv(uTexMatrix, 1, false, texMatrix, 0)
        GLES20.glUniform4fv(uCrop, 1, cropUniform(target.cropMode), 0)

        GLES20.glActiveTexture(GLES20.GL_TEXTURE0)
        GLES20.glBindTexture(GLES11Ext.GL_TEXTURE_EXTERNAL_OES, oesTextureId)

        GLES20.glDrawArrays(GLES20.GL_TRIANGLE_STRIP, 0, 4)
    }

    private fun cropUniform(mode: Int): FloatArray {
        return when (mode) {
            CROP_VERTICAL_9_16 -> {
                val w = sensorHeight * 9f / 16f
                val scale = w / sensorWidth
                floatArrayOf(scale, 1f, (1f - scale) * 0.5f, 0f)
            }
            CROP_HORIZONTAL_16_9 -> {
                val h = sensorWidth * 9f / 16f
                val scale = h / sensorHeight
                floatArrayOf(1f, scale, 0f, (1f - scale) * 0.5f)
            }
            else -> floatArrayOf(1f, 1f, 0f, 0f)
        }
    }

    fun release() {
        handler.post {
            val snapshot = targets.toList()
            targets.clear()
            for (t in snapshot) {
                try {
                    t.surface.release()
                } catch (_: Throwable) {
                }
            }
            if (oesTextureId != 0) {
                GLES20.glDeleteTextures(1, intArrayOf(oesTextureId), 0)
                oesTextureId = 0
            }
            if (program != 0) {
                GLES20.glDeleteProgram(program)
                program = 0
            }
            if (this::inputSurface.isInitialized) inputSurface.release()
            if (this::inputSurfaceTexture.isInitialized) inputSurfaceTexture.release()
        }
        thread.quitSafely()
    }

    companion object {
        const val CROP_FULL = 0
        const val CROP_HORIZONTAL_16_9 = 1
        const val CROP_VERTICAL_9_16 = 2

        private val QUAD = floatArrayOf(
            -1f, -1f, 0f, 0f,
             1f, -1f, 1f, 0f,
            -1f,  1f, 0f, 1f,
             1f,  1f, 1f, 1f,
        )

        private const val VERTEX_SHADER = """
            attribute vec2 aPosition;
            attribute vec2 aTexCoord;
            uniform mat4 uTexMatrix;
            uniform vec4 uCrop;
            varying vec2 vTexCoord;
            void main() {
                vec2 uv = aTexCoord * uCrop.xy + uCrop.zw;
                vTexCoord = (uTexMatrix * vec4(uv, 0.0, 1.0)).xy;
                gl_Position = vec4(aPosition, 0.0, 1.0);
            }
        """

        private const val FRAGMENT_SHADER = """
            #extension GL_OES_EGL_image_external : require
            precision mediump float;
            uniform samplerExternalOES sTexture;
            varying vec2 vTexCoord;
            void main() {
                gl_FragColor = texture2D(sTexture, vTexCoord);
            }
        """
    }
}
