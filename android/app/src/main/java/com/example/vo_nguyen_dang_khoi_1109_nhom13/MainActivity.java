package com.example.vo_nguyen_dang_khoi_1109_nhom13;

import android.Manifest;
import android.content.pm.PackageManager;
import android.media.AudioFormat;
import android.media.AudioRecord;
import android.media.MediaRecorder;
import androidx.annotation.NonNull;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;
import io.flutter.embedding.android.FlutterFragmentActivity;
import io.flutter.embedding.engine.FlutterEngine;
import io.flutter.plugin.common.MethodChannel;

public class MainActivity extends FlutterFragmentActivity {
    private static final String CHANNEL = "nhom13/audio_meter";
    private static final int SAMPLE_RATE = 44100;
    private static final int REQ_RECORD_AUDIO = 9113;

    private AudioRecord audioRecord;
    private boolean isRecording = false;
    private double lastRmsDb = 35.0;
    private double lastPeakDb = 38.0;

    @Override
    public void configureFlutterEngine(@NonNull FlutterEngine flutterEngine) {
        super.configureFlutterEngine(flutterEngine);

        new MethodChannel(flutterEngine.getDartExecutor().getBinaryMessenger(), CHANNEL)
                .setMethodCallHandler((call, result) -> {
                    switch (call.method) {
                        case "start":
                            result.success(startMeter());
                            break;
                        case "read":
                            java.util.HashMap<String, Double> map = new java.util.HashMap<>();
                            map.put("decibel", lastRmsDb);
                            map.put("peakDecibel", lastPeakDb);
                            result.success(map);
                            break;
                        case "stop":
                            stopMeter();
                            result.success(true);
                            break;
                        default:
                            result.notImplemented();
                            break;
                    }
                });
    }

    private boolean startMeter() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO)
                != PackageManager.PERMISSION_GRANTED) {
            ActivityCompat.requestPermissions(
                    this,
                    new String[]{Manifest.permission.RECORD_AUDIO},
                    REQ_RECORD_AUDIO
            );
            return false;
        }
        if (isRecording && audioRecord != null) {
            return true;
        }
        try {
            int minBuf = AudioRecord.getMinBufferSize(
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT
            );
            if (minBuf <= 0) return false;

            audioRecord = new AudioRecord(
                    MediaRecorder.AudioSource.MIC,
                    SAMPLE_RATE,
                    AudioFormat.CHANNEL_IN_MONO,
                    AudioFormat.ENCODING_PCM_16BIT,
                    minBuf * 2
            );
            if (audioRecord.getState() != AudioRecord.STATE_INITIALIZED) {
                return false;
            }
            audioRecord.startRecording();
            isRecording = true;

            final int bufferSize = minBuf;
            Thread reader = new Thread(() -> {
                short[] buffer = new short[bufferSize];
                while (isRecording && audioRecord != null) {
                    int read = audioRecord.read(buffer, 0, buffer.length);
                    if (read > 0) {
                        double sumSq = 0;
                        int peak = 0;
                        for (int i = 0; i < read; i++) {
                            int s = Math.abs((int) buffer[i]);
                            sumSq += (double) s * s;
                            if (s > peak) peak = s;
                        }
                        double rms = Math.sqrt(sumSq / read);
                        // Chuyển biên độ PCM 16-bit sang thang dB SPL xấp xỉ (30 dB - 115 dB)
                        double db = rms > 1.0 ? 20.0 * Math.log10(rms) + 5.0 : 30.0;
                        double peakDb = peak > 1 ? 20.0 * Math.log10(peak) + 5.0 : db;
                        lastRmsDb = Math.max(25.0, Math.min(120.0, db));
                        lastPeakDb = Math.max(lastRmsDb, Math.min(125.0, peakDb));
                    }
                    try {
                        Thread.sleep(120);
                    } catch (InterruptedException ignored) {
                        break;
                    }
                }
            });
            reader.setDaemon(true);
            reader.start();
            return true;
        } catch (Exception e) {
            isRecording = false;
            return false;
        }
    }

    private void stopMeter() {
        isRecording = false;
        if (audioRecord != null) {
            try {
                audioRecord.stop();
            } catch (Exception ignored) {
            }
            try {
                audioRecord.release();
            } catch (Exception ignored) {
            }
            audioRecord = null;
        }
    }

    @Override
    protected void onDestroy() {
        stopMeter();
        super.onDestroy();
    }
}
