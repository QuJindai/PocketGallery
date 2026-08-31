package com.qujindai.localvideo;

import org.junit.Test;

import java.util.Arrays;

import static org.junit.Assert.assertEquals;

public class AssetManifestTest {
    @Test
    public void rife46RequiresBothModelFiles() {
        assertEquals(Arrays.asList(
                "models/rife-v4.6/flownet.bin",
                "models/rife-v4.6/flownet.param"), AssetManifest.rifeModelAssets());
    }
}
