package com.qujindai.localvideo;

public final class GenerationPlan {
    private final int width;
    private final int height;
    private final int frames;
    private final int fps;

    public GenerationPlan(int width, int height, int frames, int fps) {
        if (width < 256 || height < 256 || width > 1080 || height > 1080
                || width % 16 != 0 || height % 16 != 0) {
            throw new IllegalArgumentException("Resolution must be 256..1080 and aligned to 16");
        }
        if (frames < 3 || frames > 65 || (frames & 1) == 0) {
            throw new IllegalArgumentException("Frame count must be odd and between 3 and 65");
        }
        if (fps < 8 || fps > 60) {
            throw new IllegalArgumentException("FPS must be between 8 and 60");
        }
        this.width = width;
        this.height = height;
        this.frames = frames;
        this.fps = fps;
    }

    public int getWidth() {
        return width;
    }

    public int getHeight() {
        return height;
    }

    public int getFrames() {
        return frames;
    }

    public int getFps() {
        return fps;
    }
}
