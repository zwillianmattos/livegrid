package br.com.wanmind.livegrid.camera

import android.opengl.EGL14
import android.opengl.EGLExt
import android.opengl.EGLSurface
import android.view.Surface

class WindowSurface(
    private val core: GlCore,
    private val surface: Surface,
    private val releaseSurface: Boolean = false,
) {

    private var eglSurface: EGLSurface = EGL14.EGL_NO_SURFACE

    init {
        eglSurface = EGL14.eglCreateWindowSurface(
            core.display,
            core.config,
            surface,
            intArrayOf(EGL14.EGL_NONE),
            0,
        )
        check(eglSurface != EGL14.EGL_NO_SURFACE) { "eglCreateWindowSurface falhou" }
    }

    fun makeCurrent() {
        check(EGL14.eglMakeCurrent(core.display, eglSurface, eglSurface, core.context)) {
            "eglMakeCurrent falhou"
        }
    }

    fun swapBuffers(timestampNanos: Long): Boolean {
        if (timestampNanos > 0) {
            EGLExt.eglPresentationTimeANDROID(core.display, eglSurface, timestampNanos)
        }
        return EGL14.eglSwapBuffers(core.display, eglSurface)
    }

    fun release() {
        if (eglSurface != EGL14.EGL_NO_SURFACE) {
            EGL14.eglDestroySurface(core.display, eglSurface)
            eglSurface = EGL14.EGL_NO_SURFACE
        }
        if (releaseSurface) {
            surface.release()
        }
    }
}
