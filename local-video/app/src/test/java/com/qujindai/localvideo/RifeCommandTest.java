package com.qujindai.localvideo;

import org.junit.Test;

import java.util.Arrays;
import java.util.List;

import static org.junit.Assert.assertEquals;

public class RifeCommandTest {
    @Test
    public void buildsExactNativeArguments() {
        List<String> command = RifeCommand.build(
                "/native/librife_exec.so",
                "/work/input",
                "/work/frames",
                17,
                "/models/rife-v4.6",
                0);

        assertEquals(Arrays.asList(
                "/native/librife_exec.so",
                "-i", "/work/input",
                "-o", "/work/frames",
                "-n", "17",
                "-m", "/models/rife-v4.6",
                "-g", "0",
                "-j", "1:2:2",
                "-f", "%08d.png"), command);
    }
}
