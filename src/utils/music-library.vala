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

    public class MusicNode : Object {
        protected Music? _cover_music = null;
        public string name;

        public MusicNode (string name) {
            this.name = name;
        }

        public Music cover_music {
            get {
                if (_cover_music == null)
                    _cover_music = get_first_cover_music ();
                return (!)_cover_music;
            }
            set {
                _cover_music = value;
            }
        }

        public virtual void get_sorted (ListStore store) {
        }

        protected virtual Music get_first_cover_music () {
            return new Music.empty ();
        }
    }

    public class Album : MusicNode {
        public HashTable<unowned string, Music> musics = new HashTable<unowned string, Music> (str_hash, str_equal);

        public Album (string name) {
            base (name);
        }

        public uint length {
            get {
                return musics.length;
            }
        }

        public bool add_music (Music music) {
            var count = musics.length;
            musics.insert (music.uri, music);
            return musics.length > count;
        }

        public void @foreach (HFunc<unowned string, Music> func) {
            musics.foreach (func);
        }

        public override void get_sorted (ListStore store) {
            get_sorted_musics (store);
        }

        public void get_sorted_musics (ListStore store, uint insert_pos = 0) {
            var arr = new GenericArray<Music> (musics.length);
            musics.foreach ((name, music) => arr.add (music));
            sort (arr);
            store.splice (insert_pos, 0, arr.data);
        }

        public bool remove_music (Music music) {
            return musics.steal (music.uri);
        }

        protected override Music get_first_cover_music () {
            var arr = new Music?[] { null };
            musics.foreach ((name, music) => {
                var m0 = arr[0];
                if (m0 == null) {
                    arr[0] = music;
                } else if (music.has_cover && music.track < ((!)m0).track) {
                    arr[0] = music;
                }
            });
            return (!)arr[0];
        }

        protected virtual void sort (GenericArray<Music> arr) {
            arr.sort (Music.compare_by_album);
        }
    }

    public class Artist : MusicNode {
        public HashTable<unowned string, Album> albums = new HashTable<unowned string, Album> (str_hash, str_equal);

        public Artist (string name) {
            base (name);
        }

        public uint length {
            get {
                return albums.length;
            }
        }

        public void add_cover_music (Music music) {
            if (_cover_music == null || Music.compare_by_album (music, (!)_cover_music) < 0) {
                _cover_music = music;
            }
        }

        public bool add_music (Music music) {
            unowned string key;
            Album album;
            unowned var album_key = music.album_key;
            if (!albums.lookup_extended (album_key, out key, out album)) {
                album = new Album (music.get_album_and_year ());
                albums[album_key] = album;
            }
            return album.add_music (music);
        }

        public void @foreach (HFunc<unowned string, Album> func) {
            albums.foreach (func);
        }

        public override void get_sorted (ListStore store) {
            var arr = new GenericArray<Music> (albums.length);
            albums.foreach ((name, album) => arr.add (album.cover_music));
            arr.sort (Music.compare_by_album);
            store.splice (0, store.get_n_items (), arr.data);
        }

        public bool remove_music (Music music) {
            return albums.foreach_steal ((name, album) => album.remove_music (music) && album.length == 0) > 0;
        }

        protected override Music get_first_cover_music () {
            return albums.find ((name, album) => true).cover_music;
        }
    }

    public class Playlist : Album {
        public GenericArray<Music> items;
        public string uri;

        public Playlist (string name, string uri, GenericArray<Music> arr) {
            base (name);
            this.uri = uri;
            this.items = arr;

            Music.original_order (arr);
            arr.foreach ((music) => add_music (music));

            var music = cover_music;
            _cover_music = new Music.titled (name, music.uri);
            ((!)_cover_music).cover_key = music.cover_key;
            ((!)_cover_music).album_key = uri;
        }

        protected override Music get_first_cover_music () {
            foreach (var music in items) {
                if (music.has_cover)
                    return music;
            }
            return items[0];
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
                album = new Album (music.get_album_and_year ());
                _albums[album_key] = album;
            }
            var added = album.add_music (music);

            unowned var artist_name = music.artist;
            Artist artist;
            if (!_artists.lookup_extended (artist_name, out key, out artist)) {
                artist = new Artist (artist_name);
                _artists[artist_name] = artist;
            }
            added |= artist.add_music (music);

            unowned var artist_name2 = music.album_artist;
            if (artist_name2.length > 0 && artist_name2 != artist_name) {
                Artist artist2;
                if (!_artists.lookup_extended (artist_name2, out key, out artist2)) {
                    artist2 = new Artist (artist_name2);
                    _artists[artist_name2] = artist2;
                }
                added |= artist2.add_music (music);
                // Clone a new music only for sort and cover
                artist2.add_cover_music (new Music.with_album_artist (music));
            }
            return added;
        }

        public void add_playlist (Playlist playlist) {
            _playlists.insert (playlist.uri, playlist);
        }

        public void get_sorted (ListStore album_store, ListStore artist_store, ListStore playlist_store) {
            var arr = new GenericArray<Music> (uint.max (albums.length, artists.length));
            _albums.foreach ((name, album) => arr.add (album.cover_music));
            arr.sort (Music.compare_by_album);
            album_store.splice (0, album_store.get_n_items (), arr.data);

            arr.remove_range (0, arr.length);
            _artists.foreach ((name, artist) => arr.add (artist.cover_music));
            arr.sort (Music.compare_by_artist);
            artist_store.splice (0, artist_store.get_n_items (), arr.data);

            arr.remove_range (0, arr.length);
            _playlists.foreach ((uri, playlist) => arr.add (playlist.cover_music));
            arr.sort (Music.compare_by_title);
            playlist_store.splice (0, playlist_store.get_n_items (), arr.data);
        }

        public void remove_music (Music music) {
            _albums.foreach_steal ((name, album) => album.remove_music (music) && album.length == 0);
            _artists.foreach_steal ((name, artist) => artist.remove_music (music) && artist.length == 0);
        }

        public void remove_uri (string uri, GenericSet<Music> removed) {
            var prefix = uri + "/";
            var n_removed = _albums.foreach_steal ((name, album) => {
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
