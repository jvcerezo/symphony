/// No files on web.
Stream<List<int>> readLocalFile(Uri uri) => Stream.error(UnsupportedError('No local files on this platform'));
