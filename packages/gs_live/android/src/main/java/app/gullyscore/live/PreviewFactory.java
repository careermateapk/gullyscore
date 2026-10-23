package app.gullyscore.live;

import android.content.Context;
import android.view.TextureView;
import android.view.View;

import androidx.annotation.NonNull;
import androidx.annotation.Nullable;

import io.flutter.plugin.common.StandardMessageCodec;
import io.flutter.plugin.platform.PlatformView;
import io.flutter.plugin.platform.PlatformViewFactory;

/** The camera picture shown in the app (the same picture that goes live). */
class PreviewFactory extends PlatformViewFactory {
    private final GsLivePlugin plugin;

    PreviewFactory(GsLivePlugin plugin) {
        super(StandardMessageCodec.INSTANCE);
        this.plugin = plugin;
    }

    @NonNull
    @Override
    public PlatformView create(Context context, int viewId, @Nullable Object args) {
        final TextureView view = new TextureView(context);
        plugin.onPreviewCreated(view);
        return new PlatformView() {
            @Override
            public View getView() {
                return view;
            }

            @Override
            public void dispose() {
                plugin.onPreviewDisposed(view);
            }
        };
    }
}
