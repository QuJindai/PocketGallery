typedef ReleaseVersion = ({int major, int minor, int patch, int build});

ReleaseVersion parseReleaseVersion(String pubspec) {
  final match = RegExp(
    r'^version:\s*(\d+)\.(\d+)\.(\d+)\+(\d+)\s*$',
    multiLine: true,
  ).firstMatch(pubspec);
  if (match == null) {
    throw const FormatException('pubspec version must use x.y.z+build');
  }
  return (
    major: int.parse(match.group(1)!),
    minor: int.parse(match.group(2)!),
    patch: int.parse(match.group(3)!),
    build: int.parse(match.group(4)!),
  );
}

bool isReleaseVersionAtLeast(
  ReleaseVersion actual, {
  required int major,
  required int minor,
  required int patch,
}) {
  final actualParts = <int>[actual.major, actual.minor, actual.patch];
  final minimumParts = <int>[major, minor, patch];
  for (var index = 0; index < actualParts.length; index++) {
    if (actualParts[index] != minimumParts[index]) {
      return actualParts[index] > minimumParts[index];
    }
  }
  return true;
}
