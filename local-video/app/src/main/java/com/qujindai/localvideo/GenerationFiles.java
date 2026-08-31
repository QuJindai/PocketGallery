package com.qujindai.localvideo;

import java.util.Locale;

public final class GenerationFiles {
    private GenerationFiles() {
    }

    public static String outputName(long epochMillis) {
        return "local-video-" + epochMillis + ".mp4";
    }

    public static String frameName(int frameNumber) {
        if (frameNumber < 0) {
            throw new IllegalArgumentException("Frame number must be non-negative");
        }
        return String.format(Locale.US, "%08d.png", frameNumber);
    }
}
