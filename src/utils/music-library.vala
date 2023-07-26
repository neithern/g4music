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

        public uint length {
            get {
                return musics.length;
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

        public uint length {
            get {
                return albums.length;
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
            return albums.foreach_steal ((name, album) => album.remove_music (music) && album.length == 0) > 0;
        }
    }

    public class MusicLibrary : Object {
        private HashTable<unowned string, Album> _albums = new HashTable<unowned string, Album> (str_hash, str_equal);        
        private HashTable<unowned string, Artist> _artists = new HashTable<unowned string, Artist> (str_hash, str_equal);        
        private ListStore _store = new ListStore (typeof (Music));

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

        public uint size {
            get {
                return _store.get_n_items ();
            }
        }

        public ListStore store {
            get {
                return _store;
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

        public void remove_music (Music music) {
            remove_from_albums_and_artists (music);
            for (var pos = (int) _store.get_n_items () - 1; pos >= 0; pos--) {
                if (_store.get_item (pos) == music) {
                    _store.remove (pos);
                }
            }
        }

        public void remove_uri (string uri, HFunc<unowned string, Music> func) {
            var prefix = uri + "/";
            for (var pos = (int) _store.get_n_items () - 1; pos >= 0; pos--) {
                var music = (Music) _store.get_item (pos);
                unowned var uri2 = music.uri;
                if (uri2.has_prefix (prefix) || uri2 == uri) {
                    _store.remove (pos);
                    remove_from_albums_and_artists (music);
                    func (uri2, music);
                }
            }
        }

        public void remove_all () {
            _albums.remove_all ();
            _artists.remove_all ();
            _store.remove_all ();
        }

        private void remove_from_albums_and_artists (Music music) {
            _albums.foreach_steal ((name, album) => album.remove_music (music) && album.length == 0);
            _artists.foreach_steal ((name, artist) => artist.remove_music (music) && artist.length == 0);
        }
    }
}
