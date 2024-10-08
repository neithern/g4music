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
            base.titled (music.album, music.uri);
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
            return insert_music (music);
        }

        protected bool insert_music (Music music) {
            var count = _musics.length;
            _musics.insert (music.uri, music);
            return _musics.length > count;
        }

        public bool contains (string uri) {
            return _musics.contains (uri);
        }

        public uint foreach_remove (HRFunc<unowned string, Music> func) {
            return _musics.foreach_remove (func);
        }

        public virtual void get_sorted_musics (GenericArray<Music> musics) {
            _musics.foreach ((name, music) => musics.add (music));
            sort (musics);
        }

        public void overwrite_to (ListStore store) {
            var musics = new GenericArray<Music> (_musics.length);
            get_sorted_musics (musics);
            store.splice (0, store.get_n_items (), (Object[]) musics.data);
        }

        public bool remove_music (Music music) {
            return _musics.remove (music.uri);
        }

        protected virtual void sort (GenericArray<Music> arr) {
            arr.sort (Music.compare_by_album);
        }
    }

    public class Artist : Music {
        protected HashTable<unowned string, Album> _albums = new HashTable<unowned string, Album> (str_hash, str_equal);

        public Artist (Music music, string artist_name) {
            base.titled (artist_name, music.uri);
            base.artist = artist_name;
            base.album_artist = music.album_artist;
            base._artist_key = artist_name.collate_key_for_filename ();
            base.date = music.date;
            base.uri = music.uri;
        }

        public uint length {
            get {
                return _albums.length;
            }
        }

        public override string get_abbreviation () {
            return parse_abbreviation (artist);
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
                album.album_artist = artist;
                _albums[album_key] = album;
            }
            return album.add_music (music);
        }

        public Album? find_by_partial_artist (string artist) {
            return _albums.find ((name, album) => artist.match_string (album.artist, true)) as Album;
        }

        public new Album? @get (string name) {
            return _albums[name];
        }

        public void get_sorted_albums (GenericArray<Album> albums) {
            _albums.foreach ((name, album) => albums.add (album));
            albums.sort (compare_album);
        }

        public void get_sorted_musics (GenericArray<Music> musics) {
            var arr = new GenericArray<Album> (_albums.length);
            get_sorted_albums (arr);
            arr.foreach ((album) => album.get_sorted_musics (musics));
        }

        public void overwrite_store (ListStore store) {
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
            var playlist = new Playlist (title);
            get_sorted_musics (playlist.items);
            playlist.set_cover_uri ();
            return playlist;
        }

        private static int compare_album (Music m1, Music m2) {
            return (m1.date > 0 && m2.date > 0) ? (int) (m1.date - m2.date) : strcmp (m1._album_key, m2._album_key);
        }
    }

    public class Playlist : Album {
        public GenericArray<Music> items = new GenericArray<Music> (128);
        public string list_uri;

        public Playlist (string name, string uri = "") {
            base.titled (name, "");
            base.album = name;
            base._album_key = uri;
            this.list_uri = uri;
        }

        public new uint length {
            get {
                return items.length;
            }
        }

        public new bool add_music (Music music) {
            if (insert_music (music)) {
                var count = items.length;
                items.add (music);
                items[count]._order = count;
                return true;
            }
            return false;
        }

        public void clear () {
            _musics.remove_all ();
            items.remove_range (0, items.length);
        }

        public void copy_from (Playlist playlist) {
            clear ();
            extend (playlist.items);
            set_cover_uri ();
            set_title (playlist.title);
        }

        public void extend (GenericArray<Music> musics) {
            items.extend (musics, (src) => src);
        }

        public new bool remove_music (Music music) {
            base.remove_music (music);
            return items.remove (music);
        }

        public override void get_sorted_musics (GenericArray<Music> musics) {
            musics.extend (items, (src) => src);
        }

        public void insert_to_store (ListStore store, uint position = uint.MAX) {
            var size = store.get_n_items ();
            store.splice (uint.min (position, size), 0, (Object[]) items.data);
        }

        public void reset_original_order () {
            Music.original_order (items);
        }

        public void set_cover_uri () {
            has_cover = false;
            foreach (var music in items) {
                if (music.has_cover) {
                    has_cover = true;
                    this.uri = music.uri;
                    break;
                }
            }
            if (!has_cover && items.length > 0) {
                this.uri = items[0].uri;
            }
        }

        public void set_title (string title) {
            this.album = title;
            this.title = title;
            _title_key = title.collate_key_for_filename ();
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

        public bool empty {
            get {
                return _albums.length == 0 && _artists.length == 0 && _playlists.length == 0;
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

        public Playlist add_playlist (Playlist playlist) {
            unowned string key;
            Playlist oldlist;
            if (_playlists.lookup_extended (playlist.list_uri, out key, out oldlist)) {
                if (oldlist != playlist)
                    oldlist.copy_from (playlist);
                return oldlist;
            } else {
                _playlists.insert (playlist.list_uri, playlist);
            }
            return playlist;
        }

        public void overwrite_albums_to (ListStore store) {
            var arr = new GenericArray<Music> (_albums.length);
            _albums.foreach ((name, album) => arr.add (album));
            arr.sort (Music.compare_by_album);
            store.splice (0, store.get_n_items (), (Object[]) arr.data);
        }

        public void overwrite_artists_to (ListStore store) {
            var arr = new GenericArray<Music> (_artists.length);
            _artists.foreach ((name, artist) => arr.add (artist));
            arr.sort (Music.compare_by_artist);
            store.splice (0, store.get_n_items (), (Object[]) arr.data);
        }

        public void overwrite_playlists_to (ListStore store) {
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

        public bool remove_uri (string uri, GenericSet<Music> removed) {
            string key;
            Playlist oldlist;
            if (_playlists.steal_extended (uri, out key, out oldlist)) {
                oldlist.clear ();
                return true;
            }

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
            return n_removed != 0;
        }

        public void remove_all () {
            _albums.remove_all ();
            _artists.remove_all ();
            _playlists.remove_all ();
        }
    }

    public int find_item_in_model (ListModel model, Object? obj, int start_pos = 0) {
        var count = model.get_n_items ();
        for (var i = start_pos; i < count; i++) {
            if (model.get_item (i) == obj)
                return (int) i;
        }
        for (var i = 0; i < start_pos; i++) {
            if (model.get_item (i) == obj)
                return (int) i;
        }
        return -1;
    }

    public bool merge_items_to_store (ListStore store, GenericArray<Music> arr, ref uint position) {
        var obj = store.get_item (position) as Music;
        var first_pos = -1;
        var removed = remove_items_from_store (store, arr, obj, out first_pos);
        if (removed != 0 && obj != null)
            store.find ((!)obj, out position);
        if (arr.length == 1 && arr[0] == store.get_item (position))
            return false;
        position = uint.min (position, store.get_n_items ());
        store.splice (position, 0, arr.data);
        return !(arr.length == 1 && arr[0] == store.get_item (first_pos));
    }

    public int remove_items_from_store (ListStore store, GenericArray<Music> arr, Music? exclude = null, out int first_pos = null) {
        var map = new GenericSet<Object?> (direct_hash, direct_equal);
        arr.foreach ((obj) => map.add (obj));
        var removed = 0;
        var first_removed = -1;
        var size = (int) store.get_n_items ();
        if (arr.length < size / 4) {
            for (var i = size - 1; i >= 0; i--) {
                var obj = store.get_item (i);
                if (obj != exclude && map.contains (obj)) {
                    store.remove (i);
                    removed++;
                    first_removed = i;
                }
            }
        } else {
            var remain = new GenericArray<Music> (size);
            for (var i = 0; i < size; i++) {
                var obj = store.get_item (i);
                if (obj == exclude || !map.contains (obj)) {
                    remain.add ((Music) obj);
                } else {
                    removed++;
                    if (first_removed == -1)
                        first_removed = i;
                }
            }
            store.splice (0, size, remain.data);
        }
        first_pos = first_removed;
        return removed;
    }

    public void sort_music_array (GenericArray<Music> arr, uint sort_mode) {
        if (sort_mode == SortMode.SHUFFLE)
            Music.shuffle_order (arr);

        CompareFunc<Music> compare = Music.compare_by_order;
        switch (sort_mode) {
            case SortMode.ALBUM:
                compare = Music.compare_by_album; break;
            case SortMode.ARTIST:
                compare = Music.compare_by_artist; break;
            case SortMode.ARTIST_ALBUM:
                compare = Music.compare_by_artist_album; break;
            case SortMode.TITLE:
                compare = Music.compare_by_title; break;
            case SortMode.RECENT:
                compare = Music.compare_by_recent; break;
        }
        arr.sort (compare);
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

    public Playlist to_playlist (Music[] musics, string? title = null) {
        var count = musics.length;
        var arr = new GenericArray<Music> (count);
        foreach (var music in musics) {
            if (music is Artist) {
                ((Artist) music).get_sorted_musics (arr);
            } else if (music is Album) {
                ((Album) music).get_sorted_musics (arr);
            } else {
                arr.add (music);
            }
        }
        if (title == null && count == 1) {
            title = musics[0].title;
        }
        var playlist = new Playlist (title ?? _("Untitled"));
        arr.foreach ((music) => playlist.add_music (music));
        return playlist;
    }
}
