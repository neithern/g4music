namespace G4 {

    public class Album : Object {
        private Music? _cover_music = null;
        public string name;
        public HashTable<unowned string, Music> musics = new HashTable<unowned string, Music> (str_hash, str_equal);

        public Album (string name) {
            this.name = name;
        }

        public Music cover_music {
            get {
                return _cover_music ?? musics.find ((name, music) => true);
            }
        }

        public void @foreach (HFunc<unowned string, Music> func) {
            musics.foreach (func);
        }

        public void add_music (Music music) {
            unowned string key;
            Music music0;
            if (!musics.lookup_extended (music.album, out key, out music0)) {
                musics[music.uri] = music;
            }
            if (_cover_music == null && music.has_cover) {
                _cover_music = music;
            }
        }

        public bool remove_music (Music music) {
            return musics.steal (music.uri);
        }
    }

    public class Artist : Object {
        private Music? _cover_music = null;
        public HashTable<unowned string, Album> albums = new HashTable<unowned string, Album> (str_hash, str_equal);
        public string name = "";

        public Artist (string name) {
            this.name = name;
        }

        public Music cover_music {
            get {
                return _cover_music ?? (!)albums.find ((name, album) => true).cover_music;
            }
        }

        public void @foreach (HFunc<unowned string, Album> func) {
            albums.foreach (func);
        }

        public void add_music (Music music) {
            unowned string key;
            Album album;
            if (!albums.lookup_extended (music.album, out key, out album)) {
                album = new Album (music.album);
                albums[album.name] = album;
            }
            album.add_music (music);
            if (_cover_music == null && music.has_cover) {
                _cover_music = music;
            }
        }

        public bool remove_music (Music music) {
            var list = new GenericArray<Album> (16);
            albums.foreach ((name, album) => {
                if (album.remove_music (music))
                list.add (album);
            });
            foreach (var album in list) {
                albums.steal (album.name);
            }
            return albums.length > 0;
        }
    }

    public class MusicLibrary : Object {
        private HashTable<unowned string, Album> _albums = new HashTable<unowned string, Album> (str_hash, str_equal);        
        private HashTable<unowned string, Artist> _artists = new HashTable<unowned string, Artist> (str_hash, str_equal);        

        public HashTable<unowned string, Album> albums {
            get {
                return _albums;
            }
        }

        public HashTable<unowned string, Artist> artists {
            get {
                return _artists;
            }
        }

        public void add_music (Music music) {
            unowned string key;

            Album album;
            if (!_albums.lookup_extended (music.album, out key, out album)) {
                album = new Album (music.album);
                _albums[album.name] = album;
            }
            album.add_music (music);

            Artist artist;
            if (!_artists.lookup_extended (music.artist, out key, out artist)) {
                artist = new Artist (music.artist);
                _artists[artist.name] = artist;
            }
            artist.add_music (music);
        }

        public bool remove_music (Music music) {
            var albums = new GenericArray<Album> (16);
            _albums.foreach ((name, album) => {
                if (album.remove_music (music))
                    albums.add (album);
            });
            foreach (var album in albums) {
                _albums.steal (album.name);
            }

            var artists = new GenericArray<Artist> (16);
            _artists.foreach ((name, artist) => {
                if (artist.remove_music (music))
                    artists.add (artist);
            });
            foreach (var artist in artists) {
                _artists.steal (artist.name);
            }

            return artists.length > 0 || albums.length > 0;
        }

        public void remove_all () {
            _albums.remove_all ();
            _artists.remove_all ();
        }
    }
}
