import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;

import 'import_service.dart';

class YoutubeResult {
  const YoutubeResult({required this.id, required this.title,
    required this.channel, required this.durationMs});
  final String id;
  final String title;
  final String channel;
  final int durationMs;
  Uri get url => Uri.https('www.youtube.com', '/watch', {'v': id});

  ImportCandidate forTrack(ImportCandidate original) => ImportCandidate(
    id: original.id, title: original.title, artist: original.artist,
    durationMs: original.durationMs, url: url, provider: 'youtube',
    license: 'Izin unduh dikonfirmasi pengguna',
    source: '${original.source}\nYouTube: $title — $channel\n$url',
  );
}

/// Public embed metadata only. This is an experimental HTML contract, not OAuth.
ImportPreview parseSpotifyEmbed(String html, ImportLink link) {
  if (utf8.encode(html).length > 4 * 1024 * 1024) {
    throw const ImportException('Halaman metadata Spotify terlalu besar.');
  }
  final script = RegExp(r'<script\b[^>]*\bid\s*=\s*["\x27]__NEXT_DATA__["\x27][^>]*>([\s\S]*?)</script>',
    caseSensitive: false).firstMatch(html);
  if (script == null) {
    throw const ImportException(
      'Spotify tidak menyediakan daftar lagu yang dapat dibaca. Playlist privat/radio personal atau perubahan halaman dapat menyebabkan ini.');
  }
  dynamic value;
  try { value = jsonDecode(script.group(1)!); }
  on FormatException { throw const ImportException('Metadata Spotify tidak valid.'); }
  for (final key in ['props', 'pageProps', 'state', 'data', 'entity']) {
    if (value is! Map) throw const ImportException('Format metadata Spotify berubah atau playlist tidak tersedia.');
    value = value[key];
  }
  if (value is! Map) throw const ImportException('Lagu/playlist Spotify tidak tersedia melalui halaman publik.');
  final entity = Map<String, dynamic>.from(value);
  String text(Object? raw) => raw is String ? raw.trim() : '';
  final isPlaylist = link.kind == ImportLinkKind.spotifyPlaylist;
  final rawTracks = isPlaylist ? entity['trackList'] : [entity];
  if (rawTracks is! List || rawTracks.isEmpty || rawTracks.length > maxImportTracks) {
    throw const ImportException('Daftar Spotify tidak tersedia atau melebihi 100 lagu. Tidak ada playlist kosong yang disimpan.');
  }
  final candidates = <ImportCandidate>[];
  final occurrences = <String, int>{};
  for (final raw in rawTracks) {
    if (raw is! Map) throw const ImportException('Metadata lagu Spotify tidak lengkap.');
    final title = text(raw['title']).isNotEmpty ? text(raw['title']) : text(raw['name']);
    var artist = text(raw['subtitle']);
    final artists = raw['artists'];
    if (artist.isEmpty && artists is List) {
      artist = artists.whereType<Map>().map((a) => text(a['name'])).where((a) => a.isNotEmpty).join(', ');
    }
    if (title.isEmpty || artist.isEmpty) throw const ImportException('Judul/artis Spotify tidak lengkap; audio tidak dicocokkan otomatis.');
    final spotifyUri = text(raw['uri']);
    final id = spotifyUri.split(':').last;
    if (!RegExp(r'^[A-Za-z0-9]{22}$').hasMatch(id)) throw const ImportException('Identitas lagu Spotify tidak tersedia.');
    final occurrence = occurrences.update(id, (count) => count + 1, ifAbsent: () => 0);
    final duration = raw['duration'] ?? raw['durationMs'];
    candidates.add(ImportCandidate(id: 'spotify:$id:$occurrence', title: title, artist: artist,
      durationMs: duration is num ? duration.toInt() : 0,
      url: Uri.https('open.spotify.com', '/track/$id'), provider: 'spotify',
      license: 'Pilih sumber YouTube dan konfirmasikan izin unduh',
      source: Uri.https('open.spotify.com', '/${isPlaylist ? 'playlist' : 'track'}/${link.resourceId}').toString()));
  }
  final name = text(entity['name']).isNotEmpty ? text(entity['name']) : text(entity['title']);
  return ImportPreview(sourceUrl: link.uri.toString(), name: name.isEmpty ? candidates.first.title : name,
    tracks: candidates, isPlaylist: isPlaylist);
}

/// Resolves metadata/search and fresh streams only when the user requests them.
/// No YouTube credentials, external server, Python, or FFmpeg are bundled.
class YoutubeSource {
  Future<List<YoutubeResult>> search(String query) async {
    if (query.trim().isEmpty || query.length > 500) throw const ImportException('Masukkan judul dan artis untuk pencarian YouTube.');
    final client = yt.YoutubeExplode();
    try {
      final results = await client.search.search(query.trim()).timeout(const Duration(seconds: 30));
      return results.where((video) => video.isLive != true && video.duration != null)
          .take(10).map(_result).toList();
    } on SocketException { rethrow; }
    on TimeoutException { rethrow; }
    catch (_) { throw const ImportException('Pencarian YouTube gagal. Layanan mungkin membatasi akses; coba lagi nanti.'); }
    finally { client.close(); }
  }

  YoutubeResult _result(yt.Video video) => YoutubeResult(id: video.id.value,
    title: video.title, channel: video.author, durationMs: video.duration?.inMilliseconds ?? 0);

  Future<ImportPreview> preview(ImportLink link) async {
    if (link.kind == ImportLinkKind.spotifyTrack || link.kind == ImportLinkKind.spotifyPlaylist) {
      final transport = HttpImportTransport();
      ImportResponse? response;
      try {
        response = await transport.get(Uri.https('open.spotify.com',
          '/embed/${link.kind == ImportLinkKind.spotifyTrack ? 'track' : 'playlist'}/${link.resourceId}'));
        if (response.statusCode != 200) throw ImportException('Spotify menolak metadata (HTTP ${response.statusCode}). Playlist mungkin tidak tersedia untuk publik.');
        if (response.contentLength != null && response.contentLength! > 4 * 1024 * 1024) throw const ImportException('Metadata Spotify terlalu besar.');
        final bytes = <int>[];
        await for (final chunk in response.body) {
          if (bytes.length + chunk.length > 4 * 1024 * 1024) throw const ImportException('Metadata Spotify terlalu besar.');
          bytes.addAll(chunk);
        }
        return parseSpotifyEmbed(utf8.decode(bytes), link);
      } finally { response?.abort?.call(); transport.close(); }
    }
    final client = yt.YoutubeExplode();
    try {
      final videos = <yt.Video>[];
      String name;
      if (link.kind == ImportLinkKind.youtubePlaylist) {
        final playlist = await client.playlists.get(link.resourceId).timeout(const Duration(seconds: 30));
        name = playlist.title;
        videos.addAll(await client.playlists.getVideos(link.resourceId).take(101)
          .timeout(const Duration(seconds: 30)).toList());
      } else {
        final video = await client.videos.get(link.resourceId).timeout(const Duration(seconds: 30));
        name = video.title;
        videos.add(video);
      }
      if (videos.isEmpty || videos.length > maxImportTracks) throw const ImportException('Playlist YouTube harus berisi 1 sampai 100 video.');
      if (videos.any((video) => video.isLive == true)) throw const ImportException('Siaran langsung tidak didukung untuk unduhan offline.');
      return ImportPreview(sourceUrl: link.uri.toString(), name: name,
        isPlaylist: link.kind == ImportLinkKind.youtubePlaylist,
        tracks: videos.asMap().entries.map((entry) {
          final video = _result(entry.value);
          return ImportCandidate(id: 'youtube:${video.id}:${entry.key}', title: video.title,
            artist: video.channel, durationMs: video.durationMs, url: video.url,
            provider: 'youtube', license: 'Izin unduh dikonfirmasi pengguna', source: video.url.toString());
        }).toList());
    } on ImportException { rethrow; }
    on SocketException { rethrow; }
    on TimeoutException { rethrow; }
    catch (_) { throw const ImportException('Metadata YouTube tidak tersedia. Video/playlist privat atau dibatasi belum didukung.'); }
    finally { client.close(); }
  }

  Future<ResolvedImportAudio> resolve(ImportCandidate candidate) async {
    final link = parseImportLink(candidate.url.toString());
    if (link.kind != ImportLinkKind.youtubeVideo) throw const ImportException('Sumber YouTube tidak valid.');
    final client = yt.YoutubeExplode();
    try {
      final manifest = await client.videos.streams.getManifest(link.resourceId)
          .timeout(const Duration(seconds: 45));
      final supported = manifest.audioOnly.where((stream) =>
        {'mp4', 'webm'}.contains(stream.container.name) && stream.size.totalBytes > 0
          && stream.size.totalBytes <= maxAudioBytes).toList();
      if (supported.isEmpty) throw const ImportException('YouTube tidak menyediakan audio yang didukung dalam batas 256 MiB.');
      final m4a = supported.where((stream) => stream.container.name == 'mp4').toList();
      final selected = (m4a.isNotEmpty ? m4a : supported).withHighestBitrate();
      validateImportUri(selected.url);
      if (!selected.url.host.endsWith('.googlevideo.com')) throw const ImportException('Host audio YouTube tidak dikenali.');
      final extension = selected.container.name == 'mp4' ? 'm4a' : 'webm';
      final body = client.videos.streams.get(selected).timeout(const Duration(seconds: 30))
        .handleError((Object error) {
          if (error is SocketException || error is TimeoutException) throw error;
          throw const ImportException('Transfer YouTube ditolak atau URL kedaluwarsa. Coba lagi untuk mengambil URL baru.');
        });
      return ResolvedImportAudio(extension: extension, response: ImportResponse(
        statusCode: 200, body: body, finalUri: selected.url,
        contentType: extension == 'm4a' ? 'audio/mp4' : 'audio/webm',
        contentLength: selected.size.totalBytes, abort: client.close));
    } on ImportException { client.close(); rethrow; }
    on SocketException { client.close(); rethrow; }
    on TimeoutException { client.close(); rethrow; }
    catch (_) { client.close(); throw const ImportException('Audio YouTube belum dapat diekstrak. Pembatasan layanan atau perubahan YouTube dapat menyebabkan ini.'); }
  }
}
