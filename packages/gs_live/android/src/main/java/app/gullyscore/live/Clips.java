package app.gullyscore.live;

import android.media.MediaCodec;
import android.media.MediaExtractor;
import android.media.MediaFormat;
import android.media.MediaMuxer;

import java.io.File;
import java.nio.ByteBuffer;
import java.util.HashMap;
import java.util.List;
import java.util.Map;

/** Cuts and joins recorded mp4 pieces without re-encoding them. */
final class Clips {
    private Clips() {
    }

    static long durationMs(String path) throws Exception {
        MediaExtractor ex = new MediaExtractor();
        try {
            ex.setDataSource(path);
            long d = 0;
            for (int i = 0; i < ex.getTrackCount(); i++) {
                MediaFormat f = ex.getTrackFormat(i);
                if (f.containsKey(MediaFormat.KEY_DURATION)) d = Math.max(d, f.getLong(MediaFormat.KEY_DURATION));
            }
            return d / 1000;
        } finally {
            ex.release();
        }
    }

    /** Copies the part between fromUs and toUs (starting at the key frame before fromUs). */
    static boolean trim(String src, String dst, long fromUs, long toUs) throws Exception {
        MediaExtractor ex = new MediaExtractor();
        MediaMuxer mux = null;
        try {
            ex.setDataSource(src);
            mux = new MediaMuxer(dst, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
            Map<Integer, Integer> map = addTracks(ex, mux);
            if (map.isEmpty()) return false;
            mux.start();
            ex.seekTo(Math.max(0, fromUs), MediaExtractor.SEEK_TO_PREVIOUS_SYNC);
            copy(ex, mux, map, toUs, 0, new long[]{-1});
            return true;
        } finally {
            ex.release();
            if (mux != null) {
                try {
                    mux.stop();
                } catch (Throwable ignored) {
                }
                mux.release();
            }
        }
    }

    /** Joins clips one after another (all made by the same camera session). */
    static boolean concat(List<String> srcs, String dst) throws Exception {
        if (srcs.isEmpty()) return false;
        MediaMuxer mux = new MediaMuxer(dst, MediaMuxer.OutputFormat.MUXER_OUTPUT_MPEG_4);
        Map<String, Integer> byMime = new HashMap<>();
        boolean started = false;
        long offset = 0;
        try {
            for (String src : srcs) {
                if (!new File(src).exists()) continue;
                MediaExtractor ex = new MediaExtractor();
                try {
                    ex.setDataSource(src);
                    Map<Integer, Integer> map = new HashMap<>();
                    for (int i = 0; i < ex.getTrackCount(); i++) {
                        MediaFormat f = ex.getTrackFormat(i);
                        String mime = f.getString(MediaFormat.KEY_MIME);
                        if (mime == null || !(mime.startsWith("video/") || mime.startsWith("audio/"))) continue;
                        String kind = mime.startsWith("video/") ? "v" : "a";
                        if (!started && !byMime.containsKey(kind)) byMime.put(kind, mux.addTrack(f));
                        Integer out = byMime.get(kind);
                        if (out == null) continue;
                        ex.selectTrack(i);
                        map.put(i, out);
                    }
                    if (!started) {
                        if (byMime.isEmpty()) continue;
                        mux.start();
                        started = true;
                    }
                    long[] last = new long[]{-1};
                    copy(ex, mux, map, Long.MAX_VALUE, offset, last);
                    if (last[0] > 0) offset += last[0] + 40_000; // a frame of gap between clips
                } finally {
                    ex.release();
                }
            }
            return started;
        } finally {
            if (started) {
                try {
                    mux.stop();
                } catch (Throwable ignored) {
                }
            }
            mux.release();
        }
    }

    private static Map<Integer, Integer> addTracks(MediaExtractor ex, MediaMuxer mux) {
        Map<Integer, Integer> map = new HashMap<>();
        for (int i = 0; i < ex.getTrackCount(); i++) {
            MediaFormat f = ex.getTrackFormat(i);
            String mime = f.getString(MediaFormat.KEY_MIME);
            if (mime == null || !(mime.startsWith("video/") || mime.startsWith("audio/"))) continue;
            ex.selectTrack(i);
            map.put(i, mux.addTrack(f));
        }
        return map;
    }

    /** Writes samples until toUs. Times start at 0 (+ offset). last[0] gets the last time written. */
    private static void copy(MediaExtractor ex, MediaMuxer mux, Map<Integer, Integer> map, long toUs, long offset, long[] last) {
        ByteBuffer buf = ByteBuffer.allocate(4 * 1024 * 1024);
        MediaCodec.BufferInfo info = new MediaCodec.BufferInfo();
        Map<Integer, Long> lastPerTrack = new HashMap<>();
        long first = -1;
        while (true) {
            info.offset = 0;
            info.size = ex.readSampleData(buf, 0);
            if (info.size < 0) break;
            long t = ex.getSampleTime();
            int track = ex.getSampleTrackIndex();
            Integer out = map.get(track);
            if (out == null || t > toUs) {
                ex.advance();
                if (t > toUs + 2_000_000) break;
                continue;
            }
            if (first < 0) first = t;
            long pts = t - first;
            Long prev = lastPerTrack.get(out);
            if (pts < 0 || (prev != null && pts <= prev)) {
                ex.advance();
                continue;
            }
            lastPerTrack.put(out, pts);
            info.presentationTimeUs = pts + offset;
            info.flags = (ex.getSampleFlags() & MediaExtractor.SAMPLE_FLAG_SYNC) != 0 ? MediaCodec.BUFFER_FLAG_KEY_FRAME : 0;
            mux.writeSampleData(out, buf, info);
            if (pts > last[0]) last[0] = pts;
            ex.advance();
        }
    }
}
