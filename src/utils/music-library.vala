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

    public class Album : Object {
        private Music? _cover_music = null;
        public string name;
        public HashTable<unowned string, Music> musics = new HashTable<unowned string, Music> (str_hash, str_equal);

        public Album (string name) {
            this.name = name;
        }

        public unowned Music cover_music {
            get {
                return _cover_music ?? musics.find ((name, music) => true);
            }
        }

        public uint length {
            get {
                return musics.length;
            }
        }

        public bool add_music (Music music) {
            if (_cover_music == null && music.has_cover) {
                _cover_music = music;
            }
            var count = musics.length;
            musics.insert (music.uri, music);
            return musics.length > count;
        }

        public void @foreach (HFunc<unowned string, Music> func) {
            musics.foreach (func);
        }

        public void get_sorted_musics (ListStore store) {
            var arr = new GenericArray<Music> (musics.length);
            musics.foreach ((name, music) => arr.add (music));
            arr.sort (Music.compare_by_album);
            store.splice (0, store.get_n_items (), arr.data);
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

        public unowned Music cover_music {
            get {
                return _cover_music ?? (!)albums.find ((name, album) => true).cover_music;
            }
        }

        public uint length {
            get {
                return albums.length;
            }
        }

        public bool add_music (Music music) {
            unowned string key;
            Album album;
            if (!albums.lookup_extended (music.album, out key, out album)) {
                album = new Album (music.album);
                albums[album.name] = album;
            }
            if (_cover_music == null && music.has_cover) {
                _cover_music = music;
            }
            return album.add_music (music);
        }

        public void @foreach (HFunc<unowned string, Album> func) {
            albums.foreach (func);
        }

        public void get_sorted_albums (ListStore store) {
            var arr = new GenericArray<Music> (albums.length);
            albums.foreach ((name, album) => arr.add (album.cover_music));
            arr.sort (Music.compare_by_album);
            store.splice (0, store.get_n_items (), arr.data);
        }

        public bool remove_music (Music music) {
            return albums.foreach_steal ((name, album) => album.remove_music (music) && album.length == 0) > 0;
        }
    }

    public class MusicLibrary : Object {
        private HashTable<unowned string, Album> _albums = new HashTable<unowned string, Album> (str_hash, str_equal);        
        private HashTable<unowned string, Artist> _artists = new HashTable<unowned string, Artist> (str_hash, str_equal);        

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

        public bool add_music (Music music) {
            unowned string key;

            Album album;
            if (!_albums.lookup_extended (music.album, out key, out album)) {
                album = new Album (music.album);
                _albums[album.name] = album;
            }
            var r1 = album.add_music (music);

            Artist artist;
            if (!_artists.lookup_extended (music.artist, out key, out artist)) {
                artist = new Artist (music.artist);
                _artists[artist.name] = artist;
            }
            var r2 = artist.add_music (music);
            return r1 || r2;
        }

        public void get_sorted_albums_and_artists (ListStore album_store, ListStore artist_store) {
            var arr = new GenericArray<Music> (uint.max (albums.length, artists.length));
            _albums.foreach ((name, album) => arr.add (album.cover_music));
            arr.sort (Music.compare_by_album);
            album_store.splice (0, album_store.get_n_items (), arr.data);
            arr.length = 0; 
            _artists.foreach ((name, artist) => arr.add (artist.cover_music));
            arr.sort (Music.compare_by_artist);
            artist_store.splice (0, artist_store.get_n_items (), arr.data);
        }

        public void remove_music (Music music) {
            _albums.foreach_steal ((name, album) => album.remove_music (music) && album.length == 0);
            _artists.foreach_steal ((name, artist) => artist.remove_music (music) && artist.length == 0);
        }

        public void remove_uri (string uri, GenericSet<Music> removed) {
            var prefix = uri + "/";
            _albums.foreach_steal ((name, album) => {
                album.musics.foreach_steal ((uri, music) => {
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
                _artists.foreach_steal ((name, artist) => artist.remove_music (music) && artist.length == 0);
            });
        }

        public void remove_all () {
            _albums.remove_all ();
            _artists.remove_all ();
        }
    }

    private const CompareFunc<Music>[] COMPARE_FUNCS = {
        Music.compare_by_album,
        Music.compare_by_artist,
        Music.compare_by_artist_album,
        Music.compare_by_title,
        Music.compare_by_recent,
        Music.compare_by_order,
    };

    public CompareFunc<Music> get_sort_compare (uint sort_mode) {
        if (sort_mode <= COMPARE_FUNCS.length)
            return COMPARE_FUNCS[sort_mode];
        return Music.compare_by_order;
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
        store.splice (0, count, arr.data);
    }
}
