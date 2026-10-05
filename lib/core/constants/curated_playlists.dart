import '../../features/audio_player/domain/entities/track.dart';
import '../../features/playlist_import/domain/entities/spotify_playlist.dart';

/// Pre-seeded, curated starter playlists available out-of-the-box for Symphony instances
class CuratedPlaylists {
  static final List<SpotifyPlaylist> all = [
    todaysTopHits,
    chillLofiBeats,
    rockClassics,
    nightGrooves,
  ];

  static final SpotifyPlaylist todaysTopHits = SpotifyPlaylist(
    id: '37i9dQZF1DXcBWIGoYBM5M',
    title: "Today's Top Hits",
    description: 'The hottest tracks right now • Feat. The Weeknd, Taylor Swift, Harry Styles',
    coverUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=1200&q=90',
    ownerName: 'Spotify',
    source: 'Spotify',
    tracks: [
      Track(
        id: 'tth_01',
        title: 'Blinding Lights',
        artist: 'The Weeknd',
        album: 'After Hours',
        expectedDuration: const Duration(minutes: 3, seconds: 20),
        artworkUri: Uri.parse(
          'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/2b/b9/fe/2bb9fef5-d7f3-8345-25a9-db0e79fde4e4/20UMGIM11048.rgb.jpg/600x600bb.jpg',
        ),
      ),
      Track(
        id: 'tth_02',
        title: 'Starboy',
        artist: 'The Weeknd ft. Daft Punk',
        album: 'Starboy',
        expectedDuration: const Duration(minutes: 3, seconds: 50),
        artworkUri: Uri.parse(
          'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/5a/08/94/5a089454-e0e9-b541-6547-06399b109e9e/16UMGIM56476.rgb.jpg/600x600bb.jpg',
        ),
      ),
      Track(
        id: 'tth_03',
        title: 'Cruel Summer',
        artist: 'Taylor Swift',
        album: 'Lover',
        expectedDuration: const Duration(minutes: 2, seconds: 58),
        artworkUri: Uri.parse(
          'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/49/3d/ab/493dab54-f920-9043-6181-809930f36894/19UMGIM68357.rgb.jpg/600x600bb.jpg',
        ),
      ),
      Track(
        id: 'tth_04',
        title: 'As It Was',
        artist: 'Harry Styles',
        album: "Harry's House",
        expectedDuration: const Duration(minutes: 2, seconds: 47),
        artworkUri: Uri.parse(
          'https://is1-ssl.mzstatic.com/image/thumb/Music112/v4/31/f0/24/31f02477-8025-a6fa-c146-5e58cfad1bc3/886449984711.jpg/600x600bb.jpg',
        ),
      ),
      Track(
        id: 'tth_05',
        title: 'Flowers',
        artist: 'Miley Cyrus',
        album: 'Endless Summer Vacation',
        expectedDuration: const Duration(minutes: 3, seconds: 20),
        artworkUri: Uri.parse(
          'https://is1-ssl.mzstatic.com/image/thumb/Music113/v4/2e/d0/09/2ed0092f-ef64-9665-27a3-aa04c8fca3cf/196589561726.jpg/600x600bb.jpg',
        ),
      ),
      Track(
        id: 'tth_06',
        title: 'Levitating',
        artist: 'Dua Lipa',
        album: 'Future Nostalgia',
        expectedDuration: const Duration(minutes: 3, seconds: 23),
        artworkUri: Uri.parse(
          'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/a4/09/a5/a409a5cb-2292-9337-b648-842cefc3f9e9/190295286101.jpg/600x600bb.jpg',
        ),
      ),
      Track(
        id: 'tth_07',
        title: 'Save Your Tears',
        artist: 'The Weeknd',
        album: 'After Hours',
        expectedDuration: const Duration(minutes: 3, seconds: 35),
        artworkUri: Uri.parse(
          'https://is1-ssl.mzstatic.com/image/thumb/Music115/v4/2b/b9/fe/2bb9fef5-d7f3-8345-25a9-db0e79fde4e4/20UMGIM11048.rgb.jpg/600x600bb.jpg',
        ),
      ),
      Track(
        id: 'tth_08',
        title: 'Shape of You',
        artist: 'Ed Sheeran',
        album: 'Divide',
        expectedDuration: const Duration(minutes: 3, seconds: 53),
        artworkUri: Uri.parse(
          'https://is1-ssl.mzstatic.com/image/thumb/Music125/v4/4a/c3/05/4ac30560-60b8-c309-faee-a10c2c31e9c5/190295851286.jpg/600x600bb.jpg',
        ),
      ),
    ],
  );

  static final SpotifyPlaylist chillLofiBeats = SpotifyPlaylist(
    id: '37i9dQZF1DXdLEN7aqioXM',
    title: 'Chill Lo-Fi & Study Beats',
    description: 'Peaceful instrumental lo-fi beats to relax, study, code, and chill.',
    coverUrl: 'https://images.unsplash.com/photo-1518495973542-4542c06a5843?w=1200&q=90',
    ownerName: 'Symphony Beats',
    source: 'Spotify',
    tracks: [
      Track(
        id: 'lofi_01',
        title: 'Affection',
        artist: 'Jinsang',
        album: 'Life',
        expectedDuration: const Duration(minutes: 2, seconds: 15),
        artworkUri: Uri.parse('https://images.unsplash.com/photo-1518495973542-4542c06a5843?w=600&q=80'),
      ),
      Track(
        id: 'lofi_02',
        title: 'Again',
        artist: 'Wun Two',
        album: 'Penthouse',
        expectedDuration: const Duration(minutes: 1, seconds: 48),
        artworkUri: Uri.parse('https://images.unsplash.com/photo-1509198397868-475647b2a1e5?w=600&q=80'),
      ),
      Track(
        id: 'lofi_03',
        title: 'Controlla',
        artist: 'Idealism',
        album: 'Rainy Evening',
        expectedDuration: const Duration(minutes: 2, seconds: 40),
        artworkUri: Uri.parse('https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&q=80'),
      ),
      Track(
        id: 'lofi_04',
        title: 'Snowman',
        artist: 'WYS',
        album: '1 Am. Study Session',
        expectedDuration: const Duration(minutes: 2, seconds: 32),
        artworkUri: Uri.parse('https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=600&q=80'),
      ),
    ],
  );

  static final SpotifyPlaylist rockClassics = SpotifyPlaylist(
    id: '37i9dQZF1DWXRqgorJj26U',
    title: 'Rock Classics & Anthems',
    description: 'Iconic guitar anthems, stadium classics, and timeless rock legends.',
    coverUrl: 'https://images.unsplash.com/photo-1498038432885-c6f3f1b912ee?w=1200&q=90',
    ownerName: 'Classic Rock',
    source: 'Spotify',
    tracks: [
      Track(
        id: 'rock_01',
        title: 'Bohemian Rhapsody',
        artist: 'Queen',
        album: 'A Night at the Opera',
        expectedDuration: const Duration(minutes: 5, seconds: 55),
        artworkUri: Uri.parse('https://images.unsplash.com/photo-1498038432885-c6f3f1b912ee?w=600&q=80'),
      ),
      Track(
        id: 'rock_02',
        title: 'Hotel California',
        artist: 'Eagles',
        album: 'Hotel California',
        expectedDuration: const Duration(minutes: 6, seconds: 30),
        artworkUri: Uri.parse('https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&q=80'),
      ),
      Track(
        id: 'rock_03',
        title: 'Back in Black',
        artist: 'AC/DC',
        album: 'Back in Black',
        expectedDuration: const Duration(minutes: 4, seconds: 15),
        artworkUri: Uri.parse('https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=600&q=80'),
      ),
      Track(
        id: 'rock_04',
        title: 'Smells Like Teen Spirit',
        artist: 'Nirvana',
        album: 'Nevermind',
        expectedDuration: const Duration(minutes: 5, seconds: 1),
        artworkUri: Uri.parse('https://images.unsplash.com/photo-1509198397868-475647b2a1e5?w=600&q=80'),
      ),
    ],
  );

  static final SpotifyPlaylist nightGrooves = SpotifyPlaylist(
    id: '37i9dQZF1DX4WYpdgoIcn6',
    title: 'Night Grooves & Pop',
    description: 'Electric nighttime vibes, disco pop, and neo-soul grooves.',
    coverUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=1200&q=90',
    ownerName: 'Symphony Grooves',
    source: 'Spotify',
    tracks: [
      Track(
        id: 'night_01',
        title: '24K Magic',
        artist: 'Bruno Mars',
        album: '24K Magic',
        expectedDuration: const Duration(minutes: 3, seconds: 46),
        artworkUri: Uri.parse('https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad?w=600&q=80'),
      ),
      Track(
        id: 'night_02',
        title: 'Get Lucky',
        artist: 'Daft Punk ft. Pharrell Williams',
        album: 'Random Access Memories',
        expectedDuration: const Duration(minutes: 4, seconds: 8),
        artworkUri: Uri.parse('https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=600&q=80'),
      ),
      Track(
        id: 'night_03',
        title: "Don't Start Now",
        artist: 'Dua Lipa',
        album: 'Future Nostalgia',
        expectedDuration: const Duration(minutes: 3, seconds: 3),
        artworkUri: Uri.parse('https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=600&q=80'),
      ),
    ],
  );
}
