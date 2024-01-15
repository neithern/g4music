namespace G4 {

    namespace SortMode {
        public const uint ALBUM = 0;
        public const uint ARTIST = 1;
        public const uint ARTIST_ALBUM = 2;
        public const uint TITLE = 3;
        public const uint RECENT = 4;
        public const uint SHUFFLE = 5;
        public const uint MAX = 5;
    }

    public class Album : Music {
        protected HashTable<unowned string, Music> _musics = new HashTable<unowned string, Music> (str_hash, str_equal);

        public Album (Music music) {
            base.titled (music.title, music.uri);
            base.album = music.album;
            base.artist = music.artist;
            base._album_key = music._album_key;
            base._artist_key = music._artist_key;
            base.date = music.date;
            base.track = music.track;
            base.uri = music.uri;
        }

        public uint length {
            get {
                return _musics.length;
            }
        }

        public bool add_music (Music music) {
            if (music.has_cover && music.track < track) {
                // For cover
                uri = music.uri;
            }
            var count = _musics.length;
            _musics.insert (music.uri, music);
            return _musics.length > count;
        }

        public bool contains (string uri) {
            return _musics.contains (uri);
        }

        public void @foreach (HFunc<unowned string, Music> func) {
            _musics.foreach (func);
        }

        public uint foreach_remove (HRFunc<unowned string, Music> func) {
            return _musics.foreach_remove (func);
        }

        public void get_sorted_items (GenericArray<Music> arr) {
            _musics.foreach ((name, music) => arr.add (music));
            sort (arr);
        }

        public void insert_to_store (ListStore store, uint insert_pos = 0) {
            var arr = new GenericArray<Music> (_musics.length);
            get_sorted_items (arr);
            store.splice (insert_pos, 0, (Object[]) arr.data);
        }

        public bool remove_music (Music music) {
            return _musics.remove (music.uri);
        }

        protected virtual void sort (GenericArray<Music> arr) {
            arr.sort (Music.compare_by_album);
        }
    }

    public class Artist : Music {
        public string name;
        protected HashTable<unowned string, Album> _albums = new HashTable<unowned string, Album> (str_hash, str_equal);

        public Artist (Music music, string artist_name) {
            base.titled (music.title, music.uri);
            base.album = music.album;
            base.artist = music.artist;
            base.album_artist = music.album_artist;
            base._album_key = music._album_key;
            base._artist_key = artist_name.collate_key_for_filename ();
            base.date = music.date;
            base.uri = music.uri;
            name = artist_name;
        }

        public uint length {
            get {
                return _albums.length;
            }
        }

        public override string get_abbreviation () {
            return parse_abbreviation (name);
        }

        public bool add_music (Music music) {
            if (music.has_cover && compare_album (music, this) < 0) {
                // For cover
                uri = music.uri;
            }
            unowned string key;
            unowned var album_key = music.album_key;
            Album album;
            if (!_albums.lookup_extended (album_key, out key, out album)) {
                album = new Album (music);
                album.album_artist = name;
                _albums[album_key] = album;
            }
            return album.add_music (music);
        }

        public Album? find_by_partial_artist (string artist) {
            return _albums.find ((name, album) => artist.match_string (album.artist, true)) as Album;
        }

        public void @foreach (HFunc<unowned string, Album> func) {
            _albums.foreach (func);
        }

        public new Album? @get (string name) {
            return _albums[name];
        }

        public void get_sorted_albums (GenericArray<Album> items) {
            _albums.foreach ((name, album) => items.add (album));
            items.sort (compare_album);
        }

        public void replace_to_store (ListStore store) {
            var arr = new GenericArray<Album> (_albums.length);
            get_sorted_albums (arr);
            store.splice (0, store.get_n_items (), (Object[]) arr.data);
        }

        public bool remove_music (Music music) {
            unowned var album_key = music.album_key;
            var album = _albums[album_key];
            if (album is Album) {
                var ret = album.remove_music (music);
                if (album.length == 0)
                    _albums.remove (album_key);
                return ret;
            }
            return _albums.foreach_remove ((name, album) => album.remove_music (music) && album.length == 0) > 0;
        }

        public Playlist to_playlist () {
            var arr = new GenericArray<Album> (_albums.length);
            get_sorted_albums (arr);
            var items = new GenericArray<Music> (128);
            foreach (var album in arr) {
                var musics = new GenericArray<Music> (16);
                album.get_sorted_items (musics);
                items.extend (musics, (src) => src);
            }
            return new Playlist (name, "", items);
        }

        private static int compare_album (Music m1, Music m2) {
            return (m1.date > 0 && m2.date > 0) ? (int) (m1.date - m2.date) : strcmp (m1._album_key, m2._album_key);
        }
    }

    public class Playlist : Album {
        public GenericArray<Music> items;
        public string list_uri;

        public Playlist (string name, string uri, GenericArray<Music> items) {
            base (items.length > 0 ? items[0] : new Music.empty ());
            base.album = name;
            base.title = name;
            base._album_key = uri;
            this.items = items;
            this.list_uri = uri;
            Music.original_order (items);
            items.foreach ((music) => {
                _musics.insert (music.uri, music);
                if (!has_cover && music.has_cover) {
                    has_cover = true;
                    this.uri = music.uri;
                }
            });
        }

        protected override void sort (GenericArray<Music> arr) {
            Music.original_order (items);
            arr.sort (Music.compare_by_order);
        }
    }

    public class MusicLibrary : Object {
        private HashTable<unowned string, Album> _albums = new HashTable<unowned string, Album> (str_hash, str_equal);        
        private HashTable<unowned string, Artist> _artists = new HashTable<unowned string, Artist> (str_hash, str_equal);        
        private HashTable<unowned string, Playlist> _playlists = new HashTable<unowned string, Playlist> (str_hash, str_equal);        

        public unowned HashTable<unowned string, Album> albums {
            get {
                return _albums;
            }
        }

        public unowned HashTable<unowned string, Artist> artists {
            get {
                return _artists;
            }
        }

        public unowned HashTable<unowned string, Playlist> playlists {
            get {
                return _playlists;
            }
        }

        public bool add_music (Music music) {
            unowned string key;
            unowned var album_key = music.album_key;
            Album album;
            if (!_albums.lookup_extended (album_key, out key, out album)) {
                album = new Album (music);
                album.album_artist = "";
                _albums[album_key] = album;
            }
            var added = album.add_music (music);

            unowned var album_artist = music.album_artist;
            unowned var artist_name = album_artist.length > 0 ? album_artist : music.artist;
            Artist artist;
            if (!_artists.lookup_extended (artist_name, out key, out artist)) {
                artist = new Artist (music, artist_name);
                _artists[artist_name] = artist;
            }
            added |= artist.add_music (music);
            return added;
        }

        public void add_playlist (Playlist playlist) {
            _playlists.insert (playlist.list_uri, playlist);
        }

        public void get_sorted_albums (ListStore store) {
            var arr = new GenericArray<Music> (_albums.length);
            _albums.foreach ((name, album) => arr.add (album));
            arr.sort (Music.compare_by_album);
            store.splice (0, store.get_n_items (), (Object[]) arr.data);
        }

        public void get_sorted_artists (ListStore store) {
            var arr = new GenericArray<Music> (_artists.length);
            _artists.foreach ((name, artist) => arr.add (artist));
            arr.sort (Music.compare_by_artist);
            store.splice (0, store.get_n_items (), (Object[]) arr.data);
        }

        public void get_sorted_playlists (ListStore store) {
            var arr = new GenericArray<Music> (_playlists.length);
            _playlists.foreach ((uri, playlist) => arr.add (playlist));
            arr.sort (Music.compare_by_title);
            store.splice (0, store.get_n_items (), (Object[]) arr.data);
        }

        public void remove_music (Music music) {
            unowned var album_key = music.album_key;
            var album = _albums[album_key];
            if (album is Album) {
                album.remove_music (music);
                if (album.length == 0)
                    _albums.remove (album_key);
            } else {
                _albums.foreach_remove ((name, album) => album.remove_music (music) && album.length == 0);
            }

            unowned var album_artist = music.album_artist;
            unowned var artist_name = album_artist.length > 0 ? album_artist : music.artist;
            var artist = _artists[artist_name];
            if (artist is Artist) {
                artist.remove_music (music);
                if (artist.length == 0)
                    _artists.remove (artist_name);
            } else {
                _artists.foreach_remove ((name, artist) => artist.remove_music (music) && artist.length == 0);
            }
        }

        public void remove_uri (string uri, GenericSet<Music> removed) {
            var prefix = uri + "/";
            var n_removed = _albums.foreach_remove ((name, album) => {
                album.foreach_remove ((uri, music) => {
                    unowned var uri2 = music.uri;
                    if (uri2.has_prefix (prefix)/*|| uri2 == uri*/) {
                        removed.add (music);
                        return true;
                    }
                    return false;
                });
                return album.length == 0;
            });
            removed.foreach ((music) => {
                _artists.foreach_remove ((name, artist) => artist.remove_music (music) && artist.length == 0);
            });
            if (n_removed == 0) {
                _playlists.remove (uri);
            }
        }

        public void remove_all () {
            _albums.remove_all ();
            _artists.remove_all ();
            _playlists.remove_all ();
        }
    }

    public CompareFunc<Music> get_sort_compare (uint sort_mode) {
        switch (sort_mode) {
            case SortMode.ALBUM:
                return Music.compare_by_album;
            case SortMode.ARTIST:
                return Music.compare_by_artist;
            case SortMode.ARTIST_ALBUM:
                return Music.compare_by_artist_album;
            case SortMode.TITLE:
                return Music.compare_by_title;
            case SortMode.RECENT:
                return Music.compare_by_recent;
            default:
                return Music.compare_by_order;
        }
    }

    public void sort_music_array (GenericArray<Music> arr, uint sort_mode) {
        if (sort_mode == SortMode.SHUFFLE)
            Music.shuffle_order (arr);
        arr.sort (get_sort_compare (sort_mode));
    }

    public void sort_music_store (ListStore store, uint sort_mode) {
        var count = store.get_n_items ();
        var arr = new GenericArray<Music> (count);
        for (var pos = 0; pos < count; pos++) {
            arr.add ((Music) store.get_item (pos));
        }
        sort_music_array (arr, sort_mode);
        store.splice (0, count, (Object[]) arr.data);
    }
}
