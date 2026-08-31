package com.qujindai.localvideo;

import org.junit.Test;

import static org.junit.Assert.assertArrayEquals;

public class Yuv420ConverterTest {
    @Test
    public void black2x2ConvertsToLimitedRangeI420() {
        int[] argb = {
                0xff000000, 0xff000000,
                0xff000000, 0xff000000
        };
        byte[] yuv = Yuv420Converter.toI420(argb, 2, 2);
        assertArrayEquals(new byte[]{16, 16, 16, 16, (byte) 128, (byte) 128}, yuv);
    }

    @Test
    public void white2x2ConvertsToLimitedRangeNv12() {
        int[] argb = {
                0xffffffff, 0xffffffff,
                0xffffffff, 0xffffffff
        };
        byte[] yuv = Yuv420Converter.toNv12(argb, 2, 2);
        assertArrayEquals(new byte[]{(byte) 235, (byte) 235, (byte) 235, (byte) 235,
                (byte) 128, (byte) 128}, yuv);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsOddDimensions() {
        Yuv420Converter.toI420(new int[6], 3, 2);
    }
}
