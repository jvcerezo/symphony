import 'dart:io';

/// The contents of the `file://` [uri].
Stream<List<int>> readLocalFile(Uri uri) => File.fromUri(uri).openRead();
