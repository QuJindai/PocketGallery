package com.qujindai.localvideo;

import org.junit.Test;

import static org.junit.Assert.assertEquals;

public class GenerationPlanTest {
    @Test
    public void validPlanKeepsRequestedValues() {
        GenerationPlan plan = new GenerationPlan(512, 512, 17, 16);
        assertEquals(512, plan.getWidth());
        assertEquals(512, plan.getHeight());
        assertEquals(17, plan.getFrames());
        assertEquals(16, plan.getFps());
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsEvenFrameCount() {
        new GenerationPlan(512, 512, 16, 16);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsInvalidFps() {
        new GenerationPlan(512, 512, 17, 2);
    }

    @Test(expected = IllegalArgumentException.class)
    public void rejectsResolutionNotAlignedTo16() {
        new GenerationPlan(510, 512, 17, 16);
    }
}
