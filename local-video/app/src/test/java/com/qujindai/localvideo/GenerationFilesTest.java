package com.qujindai.localvideo;

import org.junit.Test;

import static org.junit.Assert.assertEquals;

public class GenerationFilesTest {
    @Test
    public void outputNameIsStableAndMp4() {
        assertEquals("local-video-1700000000123.mp4", GenerationFiles.outputName(1700000000123L));
    }

    @Test
    public void frameNamesMatchRifePattern() {
        assertEquals("00000000.png", GenerationFiles.frameName(0));
        assertEquals("00000016.png", GenerationFiles.frameName(16));
    }
}
