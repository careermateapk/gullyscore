package app.gullyscore.live;

import android.Manifest;
import android.app.Activity;
import android.content.Context;
import android.content.pm.PackageManager;
import android.graphics.Bitmap;
import android.graphics.BitmapFactory;
import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.view.TextureView;
import android.view.WindowManager;

import androidx.annotation.NonNull;

import com.pedro.common.ConnectChecker;
import com.pedro.encoder.input.gl.render.filters.object.ImageObjectFilterRender;
import com.pedro.encoder.input.sources.audio.MicrophoneSource;
import com.pedro.encoder.input.sources.video.Camera2Source;
import com.pedro.encoder.input.sources.video.VideoFileSource;
import com.pedro.encoder.input.sources.video.VideoSource;
import com.pedro.encoder.input.video.CameraHelper;
import com.pedro.library.base.recording.RecordController;
import com.pedro.library.generic.GenericStream;

import java.io.File;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;

import io.flutter.embedding.engine.plugins.FlutterPlugin;
import io.flutter.embedding.engine.plugins.activity.ActivityAware;
import io.flutter.embedding.engine.plugins.activity.ActivityPluginBinding;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import io.flutter.plugin.common.PluginRegistry;
import kotlin.Unit;

/**
 * GullyScore live: camera preview, streaming to YouTube (RTMP), the score
 * picture drawn on the video, recording in short pieces for replays and
 * highlight clips, and cutting/joining those clips.
 */
public class GsLivePlugin implements FlutterPlugin, MethodChannel.MethodCallHandler, ActivityAware,
        PluginRegistry.RequestPermissionsResultListener, ConnectChecker {

    private static final int PERMISSION_CODE = 4711;

    private MethodChannel channel;
    private Context context;
    private Activity activity;
    private ActivityPluginBinding activityBinding;
    private final Handler main = new Handler(Looper.getMainLooper());
    private final ExecutorService io = Executors.newSingleThreadExecutor();

    private GenericStream stream;
    private ImageObjectFilterRender overlay;
    private TextureView previewView;
    private MethodChannel.Result pendingPermission;
    private boolean replaying = false;

    // ------------------------------------------------------------ plugin plumbing

    @Override
    public void onAttachedToEngine(@NonNull FlutterPluginBinding binding) {
        context = binding.getApplicationContext();
        channel = new MethodChannel(binding.getBinaryMessenger(), "gs_live");
        channel.setMethodCallHandler(this);
        binding.getPlatformViewRegistry().registerViewFactory("gs_live/preview", new PreviewFactory(this));
    }

    @Override
    public void onDetachedFromEngine(@NonNull FlutterPluginBinding binding) {
        channel.setMethodCallHandler(null);
        releaseAll();
    }

    @Override
    public void onAttachedToActivity(@NonNull ActivityPluginBinding binding) {
        activityBinding = binding;
        activity = binding.getActivity();
        binding.addRequestPermissionsResultListener(this);
    }

    @Override
    public void onDetachedFromActivityForConfigChanges() {
        detachActivity();
    }

    @Override
    public void onReattachedToActivityForConfigChanges(@NonNull ActivityPluginBinding binding) {
        onAttachedToActivity(binding);
    }

    @Override
    public void onDetachedFromActivity() {
        detachActivity();
    }

    private void detachActivity() {
        if (activityBinding != null) activityBinding.removeRequestPermissionsResultListener(this);
        activityBinding = null;
        activity = null;
    }

    // ------------------------------------------------------------ calls from Dart

    @Override
    public void onMethodCall(@NonNull MethodCall call, @NonNull MethodChannel.Result result) {
        try {
            switch (call.method) {
                case "permissions":
                    askPermissions(result);
                    break;
                case "prepare":
                    prepare(intArg(call, "width", 1280), intArg(call, "height", 720), intArg(call, "bitrate", 2500 * 1024),
                            intArg(call, "fps", 30));
                    result.success(true);
                    break;
                case "start": {
                    String url = call.argument("url");
                    if (stream == null || url == null) throw new IllegalStateException("not prepared");
                    stream.getStreamClient().setReTries(30);
                    stream.startStream(url);
                    result.success(true);
                    break;
                }
                case "stop":
                    if (stream != null && stream.isStreaming()) stream.stopStream();
                    result.success(true);
                    break;
                case "release":
                    releaseAll();
                    result.success(true);
                    break;
                case "overlay":
                    setOverlay(call.argument("png"));
                    result.success(true);
                    break;
                case "startSegment": {
                    String path = call.argument("path");
                    startSegment(path);
                    result.success(true);
                    break;
                }
                case "cutSegment": {
                    // Close the piece being recorded (so it can be read) and start the next one.
                    String next = call.argument("next");
                    if (stream != null && stream.isRecording()) stream.stopRecord();
                    if (next != null) startSegment(next);
                    result.success(true);
                    break;
                }
                case "stopSegment":
                    if (stream != null && stream.isRecording()) stream.stopRecord();
                    result.success(true);
                    break;
                case "duration": {
                    final String path = call.argument("path");
                    background(result, () -> Clips.durationMs(path));
                    break;
                }
                case "trim": {
                    final String src = call.argument("src");
                    final String dst = call.argument("dst");
                    final long from = longArg(call, "fromMs");
                    final long to = longArg(call, "toMs");
                    background(result, () -> Clips.trim(src, dst, from * 1000, to * 1000));
                    break;
                }
                case "concat": {
                    final List<String> srcs = call.argument("srcs");
                    final String dst = call.argument("dst");
                    background(result, () -> Clips.concat(srcs == null ? new ArrayList<>() : srcs, dst));
                    break;
                }
                case "replay": {
                    String path = call.argument("path");
                    replay(path);
                    result.success(true);
                    break;
                }
                case "switchCamera": {
                    if (stream != null && stream.getVideoSource() instanceof Camera2Source) {
                        ((Camera2Source) stream.getVideoSource()).switchCamera();
                    }
                    result.success(true);
                    break;
                }
                case "mute": {
                    Boolean on = call.argument("on");
                    if (stream != null && stream.getAudioSource() instanceof MicrophoneSource) {
                        MicrophoneSource mic = (MicrophoneSource) stream.getAudioSource();
                        if (on != null && on) mic.mute(); else mic.unMute();
                    }
                    result.success(true);
                    break;
                }
                case "zoom": {
                    Double level = call.argument("level");
                    if (stream != null && level != null && stream.getVideoSource() instanceof Camera2Source) {
                        Camera2Source cam = (Camera2Source) stream.getVideoSource();
                        android.util.Range<Float> r = cam.getZoomRange();
                        float z = (float) (r.getLower() + (r.getUpper() - r.getLower()) * Math.max(0, Math.min(1, level)));
                        cam.setZoom(z);
                    }
                    result.success(true);
                    break;
                }
                default:
                    result.notImplemented();
            }
        } catch (Throwable e) {
            result.error("live", String.valueOf(e.getMessage()), null);
        }
    }

    private static int intArg(MethodCall call, String key, int def) {
        Object v = call.argument(key);
        return v instanceof Number ? ((Number) v).intValue() : def;
    }

    private static long longArg(MethodCall call, String key) {
        Object v = call.argument(key);
        return v instanceof Number ? ((Number) v).longValue() : 0L;
    }

    private interface Job {
        Object run() throws Exception;
    }

    private void background(final MethodChannel.Result result, final Job job) {
        io.execute(() -> {
            Object value;
            try {
                value = job.run();
            } catch (Throwable e) {
                final String msg = String.valueOf(e.getMessage());
                main.post(() -> result.error("live", msg, null));
                return;
            }
            final Object v = value;
            main.post(() -> result.success(v));
        });
    }

    private void send(String type, Map<String, Object> extra) {
        final Map<String, Object> m = new HashMap<>();
        m.put("type", type);
        if (extra != null) m.putAll(extra);
        main.post(() -> {
            if (channel != null) channel.invokeMethod("event", m);
        });
    }

    // ------------------------------------------------------------ permissions

    private void askPermissions(MethodChannel.Result result) {
        if (activity == null) {
            result.success(false);
            return;
        }
        boolean cam = activity.checkSelfPermission(Manifest.permission.CAMERA) == PackageManager.PERMISSION_GRANTED;
        boolean mic = activity.checkSelfPermission(Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED;
        if (cam && mic) {
            result.success(true);
            return;
        }
        pendingPermission = result;
        activity.requestPermissions(new String[]{Manifest.permission.CAMERA, Manifest.permission.RECORD_AUDIO}, PERMISSION_CODE);
    }

    @Override
    public boolean onRequestPermissionsResult(int requestCode, @NonNull String[] permissions, @NonNull int[] grantResults) {
        if (requestCode != PERMISSION_CODE || pendingPermission == null) return false;
        boolean ok = grantResults.length > 0;
        for (int g : grantResults) ok = ok && g == PackageManager.PERMISSION_GRANTED;
        pendingPermission.success(ok);
        pendingPermission = null;
        return true;
    }

    // ------------------------------------------------------------ camera and stream

    private void prepare(int width, int height, int bitrate, int fps) {
        if (stream == null) {
            stream = new GenericStream(context, this);
        }
        if (!stream.isStreaming() && !stream.isRecording() && !stream.isOnPreview()) {
            int rotation = CameraHelper.getCameraOrientation(activity != null ? activity : context);
            boolean video = stream.prepareVideo(width, height, bitrate, fps, 1, rotation);
            boolean audio = stream.prepareAudio(44100, true, 128 * 1024);
            if (!video || !audio) throw new IllegalStateException("This phone cannot record this video size");
        }
        if (overlay == null) {
            overlay = new ImageObjectFilterRender();
            stream.getGlInterface().addFilter(overlay);
            overlay.setScale(100f, 100f);
            overlay.setPosition(0f, 0f);
        }
        if (activity != null) activity.getWindow().addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
        startPreviewIfReady();
    }

    void onPreviewCreated(TextureView view) {
        previewView = view;
        startPreviewIfReady();
    }

    void onPreviewDisposed(TextureView view) {
        if (previewView == view) previewView = null;
        if (stream != null && stream.isOnPreview()) {
            try {
                stream.stopPreview();
            } catch (Throwable ignored) {
            }
        }
    }

    private void startPreviewIfReady() {
        if (stream == null || previewView == null) return;
        if (!stream.isOnPreview()) stream.startPreview(previewView, true);
    }

    private void setOverlay(byte[] png) {
        if (overlay == null) return;
        if (png == null || png.length == 0) {
            overlay.setAlpha(0f);
            return;
        }
        Bitmap bmp = BitmapFactory.decodeByteArray(png, 0, png.length);
        if (bmp == null) return;
        overlay.setImage(bmp);
        overlay.setScale(100f, 100f);
        overlay.setPosition(0f, 0f);
        overlay.setAlpha(1f);
    }

    private void startSegment(String path) {
        if (stream == null || path == null || stream.isRecording()) return;
        File f = new File(path);
        File dir = f.getParentFile();
        if (dir != null && !dir.exists()) //noinspection ResultOfMethodCallIgnored
            dir.mkdirs();
        stream.startRecord(path, (RecordController.Listener) status -> { });
    }

    private void replay(String path) {
        if (stream == null || path == null || replaying) return;
        replaying = true;
        VideoSource clip = new VideoFileSource(context, Uri.fromFile(new File(path)), false, isLoop -> {
            main.post(this::backToCamera);
            return Unit.INSTANCE;
        });
        try {
            stream.changeVideoSource(clip);
            send("replayStarted", null);
        } catch (Throwable e) {
            replaying = false;
            Map<String, Object> m = new HashMap<>();
            m.put("reason", String.valueOf(e.getMessage()));
            send("replayDone", m);
        }
    }

    private void backToCamera() {
        if (!replaying) return;
        replaying = false;
        try {
            if (stream != null) stream.changeVideoSource(new Camera2Source(context));
        } catch (Throwable ignored) {
        }
        send("replayDone", null);
    }

    private void releaseAll() {
        try {
            if (stream != null) {
                if (stream.isRecording()) stream.stopRecord();
                if (stream.isStreaming()) stream.stopStream();
                if (stream.isOnPreview()) stream.stopPreview();
                stream.release();
            }
        } catch (Throwable ignored) {
        }
        stream = null;
        overlay = null;
        replaying = false;
        if (activity != null) activity.getWindow().clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON);
    }

    // ------------------------------------------------------------ connection events

    @Override
    public void onConnectionStarted(@NonNull String url) {
        send("connecting", null);
    }

    @Override
    public void onConnectionSuccess() {
        send("live", null);
    }

    @Override
    public void onConnectionFailed(@NonNull String reason) {
        final String why = reason;
        main.post(() -> {
            if (stream != null && stream.getStreamClient().reTry(5000, why, null)) {
                Map<String, Object> m = new HashMap<>();
                m.put("reason", why);
                send("reconnecting", m);
            } else {
                if (stream != null && stream.isStreaming()) stream.stopStream();
                Map<String, Object> m = new HashMap<>();
                m.put("reason", why);
                send("failed", m);
            }
        });
    }

    @Override
    public void onDisconnect() {
        send("stopped", null);
    }

    @Override
    public void onAuthError() {
        Map<String, Object> m = new HashMap<>();
        m.put("reason", "auth");
        send("failed", m);
    }

    @Override
    public void onAuthSuccess() {
    }

    @Override
    public void onNewBitrate(long bitrate) {
        Map<String, Object> m = new HashMap<>();
        m.put("bitrate", bitrate);
        send("bitrate", m);
    }
}
