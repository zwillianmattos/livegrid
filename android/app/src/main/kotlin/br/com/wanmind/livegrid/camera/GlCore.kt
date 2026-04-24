package br.com.wanmind.livegrid.camera

import android.opengl.EGL14
import android.opengl.EGLConfig
import android.opengl.EGLContext
import android.opengl.EGLDisplay
import android.opengl.EGLSurface

class GlCore {

    val display: EGLDisplay
    val config: EGLConfig
    val context: EGLContext
    private val pbufferSurface: EGLSurface

    init {
        display = EGL14.eglGetDisplay(EGL14.EGL_DEFAULT_DISPLAY)
        check(display != EGL14.EGL_NO_DISPLAY) { "eglGetDisplay falhou" }
        val version = IntArray(2)
        check(EGL14.eglInitialize(display, version, 0, version, 1)) { "eglInitialize falhou" }

        val configs = arrayOfNulls<EGLConfig>(1)
        val numConfigs = IntArray(1)
        check(
            EGL14.eglChooseConfig(display, CONFIG_ATTRIBS, 0, configs, 0, 1, numConfigs, 0)
        ) { "eglChooseConfig falhou" }
        config = configs[0]!!

        context = EGL14.eglCreateContext(display, config, EGL14.EGL_NO_CONTEXT, CTX_ATTRIBS, 0)
        check(context != EGL14.EGL_NO_CONTEXT) { "eglCreateContext falhou" }

        pbufferSurface = EGL14.eglCreatePbufferSurface(display, config, PBUFFER_ATTRIBS, 0)
        check(pbufferSurface != EGL14.EGL_NO_SURFACE) { "eglCreatePbufferSurface falhou" }
    }

    fun makeCurrentNothing() {
        check(EGL14.eglMakeCurrent(display, pbufferSurface, pbufferSurface, context)) {
            "makeCurrentNothing falhou"
        }
    }

    fun release() {
        EGL14.eglMakeCurrent(
            display,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_SURFACE,
            EGL14.EGL_NO_CONTEXT,
        )
        EGL14.eglDestroySurface(display, pbufferSurface)
        EGL14.eglDestroyContext(display, context)
        EGL14.eglReleaseThread()
        EGL14.eglTerminate(display)
    }

    companion object {
        private val CONFIG_ATTRIBS = intArrayOf(
            EGL14.EGL_RED_SIZE, 8,
            EGL14.EGL_GREEN_SIZE, 8,
            EGL14.EGL_BLUE_SIZE, 8,
            EGL14.EGL_ALPHA_SIZE, 8,
            EGL14.EGL_RENDERABLE_TYPE, EGL14.EGL_OPENGL_ES2_BIT,
            EGL14.EGL_SURFACE_TYPE, EGL14.EGL_WINDOW_BIT or EGL14.EGL_PBUFFER_BIT,
            EGL14.EGL_NONE,
        )

        private val CTX_ATTRIBS = intArrayOf(EGL14.EGL_CONTEXT_CLIENT_VERSION, 2, EGL14.EGL_NONE)

        private val PBUFFER_ATTRIBS = intArrayOf(
            EGL14.EGL_WIDTH, 1,
            EGL14.EGL_HEIGHT, 1,
            EGL14.EGL_NONE,
        )
    }
}
