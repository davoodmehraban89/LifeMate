/// The provider receives a public video hash only, never an application URL,
/// token, account identifier or caller-supplied iframe markup.
Uri? aparatEmbedUri(String videoHash) {
  if (!RegExp(r'^[A-Za-z0-9]{5,64}$').hasMatch(videoHash) ||
      videoHash.contains('\n') ||
      videoHash.contains('\r')) {
    return null;
  }
  return Uri.https(
      'www.aparat.com', '/video/video/embed/videohash/$videoHash/vt/frame');
}

bool isAllowedAparatNavigation(String address, String videoHash) {
  // Uri normalizes percent-encoded unreserved characters; reject encodings
  // before parsing so only the literal provider path can pass this boundary.
  if (address.contains('%') ||
      address.contains('\\') ||
      address.trim() != address) {
    return false;
  }
  final expected = aparatEmbedUri(videoHash);
  final candidate = Uri.tryParse(address);
  return expected != null &&
      candidate != null &&
      candidate.scheme == 'https' &&
      (candidate.host == 'www.aparat.com' || candidate.host == 'aparat.com') &&
      candidate.port == 443 &&
      candidate.userInfo.isEmpty &&
      !candidate.hasQuery &&
      !candidate.hasFragment &&
      candidate.path == expected.path;
}
