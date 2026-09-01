abstract final class PocketGalleryBuildIdentity {
  static const String packageName =
      'com.qujindai.pocketgallery_phone_pilot.r3';

  static const String canonicalSignerSha256 =
      '81af4a5ef94c236774f0e193b2a4b248805b36c14cc36e2a56df8e451a712541';

  static const String sourceCommit =
      String.fromEnvironment('POCKETGALLERY_SOURCE_COMMIT');

  static bool isValidSourceCommit(String value) {
    return RegExp(r'^[0-9a-fA-F]{40}$').hasMatch(value);
  }
}
