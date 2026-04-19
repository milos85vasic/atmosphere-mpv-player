package `is`.xyz.mpv

import android.app.Presentation
import android.content.Context
import android.os.Bundle
import android.view.Display
import android.view.Surface
import android.view.SurfaceHolder
import android.view.SurfaceView
import android.widget.FrameLayout

class VideoSecondaryPresentation(
    context: Context,
    display: Display,
    private val onReady: (Surface) -> Unit,
    private val onChanged: (Int, Int) -> Unit,
    private val onLost: () -> Unit,
) : Presentation(context, display), SurfaceHolder.Callback {

    private lateinit var surfaceView: SurfaceView

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        surfaceView = SurfaceView(context)
        val layout = FrameLayout(context)
        layout.addView(
            surfaceView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT,
            ),
        )
        setContentView(layout)
        surfaceView.holder.addCallback(this)
    }

    val videoSurface: Surface?
        get() = if (::surfaceView.isInitialized) surfaceView.holder.surface else null

    override fun surfaceCreated(holder: SurfaceHolder) {
        onReady(holder.surface)
    }

    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) {
        onChanged(width, height)
    }

    override fun surfaceDestroyed(holder: SurfaceHolder) {
        onLost()
    }
}
