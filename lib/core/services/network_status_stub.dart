/// Web plays through the Symphony server, so it is always treated as online.
Future<bool> canReachInternet() async => true;

/// The browser decides what it downloads.
Future<bool> isMeteredConnection() async => false;
