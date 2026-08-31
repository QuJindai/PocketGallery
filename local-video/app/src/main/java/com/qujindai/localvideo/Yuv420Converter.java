package com.qujindai.localvideo;

public final class Yuv420Converter {
    private Yuv420Converter() {
    }

    public static byte[] toI420(int[] argb, int width, int height) {
        validate(argb, width, height);
        int frameSize = width * height;
        byte[] out = new byte[frameSize * 3 / 2];
        int uOffset = frameSize;
        int vOffset = frameSize + frameSize / 4;
        writeY(argb, width, height, out);
        int uvIndex = 0;
        for (int y = 0; y < height; y += 2) {
            for (int x = 0; x < width; x += 2) {
                int[] uv = averageUv(argb, width, x, y);
                out[uOffset + uvIndex] = (byte) uv[0];
                out[vOffset + uvIndex] = (byte) uv[1];
                uvIndex++;
            }
        }
        return out;
    }

    public static byte[] toNv12(int[] argb, int width, int height) {
        validate(argb, width, height);
        int frameSize = width * height;
        byte[] out = new byte[frameSize * 3 / 2];
        writeY(argb, width, height, out);
        int uvIndex = frameSize;
        for (int y = 0; y < height; y += 2) {
            for (int x = 0; x < width; x += 2) {
                int[] uv = averageUv(argb, width, x, y);
                out[uvIndex++] = (byte) uv[0];
                out[uvIndex++] = (byte) uv[1];
            }
        }
        return out;
    }

    private static void validate(int[] argb, int width, int height) {
        if (width <= 0 || height <= 0 || (width & 1) != 0 || (height & 1) != 0) {
            throw new IllegalArgumentException("YUV420 requires positive even dimensions");
        }
        if (argb == null || argb.length < width * height) {
            throw new IllegalArgumentException("ARGB buffer is too small");
        }
    }

    private static void writeY(int[] argb, int width, int height, byte[] out) {
        int index = 0;
        for (int y = 0; y < height; y++) {
            for (int x = 0; x < width; x++) {
                int pixel = argb[y * width + x];
                int r = (pixel >> 16) & 0xff;
                int g = (pixel >> 8) & 0xff;
                int b = pixel & 0xff;
                int yy = ((66 * r + 129 * g + 25 * b + 128) >> 8) + 16;
                out[index++] = (byte) clamp(yy);
            }
        }
    }

    private static int[] averageUv(int[] argb, int width, int x, int y) {
        int uSum = 0;
        int vSum = 0;
        for (int dy = 0; dy < 2; dy++) {
            for (int dx = 0; dx < 2; dx++) {
                int pixel = argb[(y + dy) * width + (x + dx)];
                int r = (pixel >> 16) & 0xff;
                int g = (pixel >> 8) & 0xff;
                int b = pixel & 0xff;
                int u = ((-38 * r - 74 * g + 112 * b + 128) >> 8) + 128;
                int v = ((112 * r - 94 * g - 18 * b + 128) >> 8) + 128;
                uSum += clamp(u);
                vSum += clamp(v);
            }
        }
        return new int[]{(uSum + 2) / 4, (vSum + 2) / 4};
    }

    private static int clamp(int value) {
        return Math.max(0, Math.min(255, value));
    }
}
