package com.qujindai.localvideo;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public final class RifeCommand {
    private RifeCommand() {
    }

    public static List<String> build(
            String executable,
            String inputDir,
            String outputDir,
            int frames,
            String modelDir,
            int gpuId) {
        if (executable == null || executable.isEmpty()) {
            throw new IllegalArgumentException("Executable is required");
        }
        if (inputDir == null || inputDir.isEmpty()) {
            throw new IllegalArgumentException("Input directory is required");
        }
        if (outputDir == null || outputDir.isEmpty()) {
            throw new IllegalArgumentException("Output directory is required");
        }
        if (modelDir == null || modelDir.isEmpty()) {
            throw new IllegalArgumentException("Model directory is required");
        }
        if (frames < 3) {
            throw new IllegalArgumentException("Frame count must be at least 3");
        }

        return Collections.unmodifiableList(Arrays.asList(
                executable,
                "-i", inputDir,
                "-o", outputDir,
                "-n", Integer.toString(frames),
                "-m", modelDir,
                "-g", Integer.toString(gpuId),
                "-j", "1:2:2",
                "-f", "%08d.png"));
    }
}
