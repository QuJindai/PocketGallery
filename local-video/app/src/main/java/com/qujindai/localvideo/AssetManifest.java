package com.qujindai.localvideo;

import java.util.Arrays;
import java.util.Collections;
import java.util.List;

public final class AssetManifest {
    private static final List<String> RIFE_MODEL_ASSETS = Collections.unmodifiableList(Arrays.asList(
            "models/rife-v4.6/flownet.bin",
            "models/rife-v4.6/flownet.param"));

    private AssetManifest() {
    }

    public static List<String> rifeModelAssets() {
        return RIFE_MODEL_ASSETS;
    }
}
