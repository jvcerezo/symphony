/// Where a playlist comes from.
enum PlaylistSource {
  spotify('Spotify'),
  appleMusic('Apple Music'),
  youtube('YouTube');

  final String label;
  const PlaylistSource(this.label);
}

/// A playlist found by browsing or search: enough to show a card. Its
/// songs are loaded (imported) only when it's opened.
class PlaylistSummary {
  final PlaylistSource source;
  final String id;
  final String title;

  /// Curator or channel, e.g. "Apple Music Chill".
  final String? subtitle;
  final String? coverUrl;

  /// What the importer takes to load it (a link or id).
  final String link;
  final int? trackCount;

  const PlaylistSummary({
    required this.source,
    required this.id,
    required this.title,
    required this.link,
    this.subtitle,
    this.coverUrl,
    this.trackCount,
  });

  @override
  bool operator ==(Object other) => other is PlaylistSummary && other.source == source && other.id == id;

  @override
  int get hashCode => Object.hash(source, id);

  @override
  String toString() => 'PlaylistSummary(${source.name}, $id, "$title")';
}
