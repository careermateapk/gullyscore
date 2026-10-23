// YouTube links: which video (or channel) to show fans inside the app.

/// 'v:<id>' for a video link, 'c:<id>' for a channel link, null if not YouTube.
String? youtubeRef(String link) {
  final s = link.trim();
  if (s.isEmpty) return null;
  final uri = Uri.tryParse(s.startsWith('http') ? s : 'https://$s');
  if (uri == null) return null;
  final host = uri.host.toLowerCase().replaceFirst('www.', '').replaceFirst('m.', '');
  final seg = uri.pathSegments.where((x) => x.isNotEmpty).toList();
  final id = RegExp(r'^[A-Za-z0-9_-]{6,20}$');
  if (host == 'youtu.be' && seg.isNotEmpty && id.hasMatch(seg.first)) return 'v:${seg.first}';
  if (host != 'youtube.com' && host != 'studio.youtube.com') return null;
  final v = uri.queryParameters['v'];
  if (v != null && id.hasMatch(v)) return 'v:$v';
  if (seg.length >= 2 && ['live', 'embed', 'shorts', 'video'].contains(seg[0]) && id.hasMatch(seg[1])) return 'v:${seg[1]}';
  if (seg.length >= 2 && seg[0] == 'channel' && RegExp(r'^UC[A-Za-z0-9_-]{10,40}$').hasMatch(seg[1])) return 'c:${seg[1]}';
  return null;
}

/// The page that shows the video (on our server, so YouTube accepts it).
Uri youtubeEmbedUri(String base, String ref) {
  final kind = ref.startsWith('c:') ? 'c' : 'v';
  final value = ref.substring(2);
  if (base.isEmpty) {
    return Uri.parse(kind == 'v'
        ? 'https://www.youtube.com/embed/$value?autoplay=1&mute=1&playsinline=1'
        : 'https://www.youtube.com/embed/live_stream?channel=$value&autoplay=1&mute=1&playsinline=1');
  }
  return Uri.parse('$base/embed/yt?$kind=${Uri.encodeQueryComponent(value)}');
}

/// Opens the video in the YouTube app / browser.
Uri youtubeWatchUri(String ref) => ref.startsWith('c:')
    ? Uri.parse('https://www.youtube.com/channel/${ref.substring(2)}/live')
    : Uri.parse('https://www.youtube.com/watch?v=${ref.substring(2)}');
