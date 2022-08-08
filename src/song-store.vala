namespace Music {

    public enum SortMode {
        ALBUM,
        ARTIST,
        TITLE,
        RECENT,
        SHUFFLE,
    }

    public class SongStore : Object {
        private SortMode _sort_mode = SortMode.TITLE;
        private CompareDataFunc<Object> _compare = Song.compare_by_title;
        private ListStore _store = new ListStore (typeof (Song));
        private TagCache _tag_cache = new TagCache ();

        public signal void parse_progress (int percent);

        public ListStore store {
            get {
                return _store;
            }
        }

        public uint size {
            get {
                return _store.get_n_items ();
            }
        }

        public SortMode sort_mode {
            get {
                return _sort_mode;
            }
            set {
                _sort_mode = value;
                switch (value) {
                    case SortMode.ALBUM:
                        _compare = Song.compare_by_album;
                        break;
                    case SortMode.ARTIST:
                        _compare = Song.compare_by_artist;
                        break;
                    case SortMode.RECENT:
                        _compare = Song.compare_by_date_ascending;
                        break;
                    case SortMode.SHUFFLE:
                        _compare = Song.compare_by_order;
                        break;
                    default:
                        _compare = Song.compare_by_title;
                        break;
                }
                if (_sort_mode == SortMode.SHUFFLE) {
                    var count = _store.get_n_items ();
                    var arr = new GenericArray<Object> (count);
                    for (var i = 0; i < count; i++) {
                        arr.add ((!)_store.get_item (i));
                    }
                    Song.shuffle_order (arr);
                }
                _store.sort (_compare);
            }
        }

        public void add_to_cache (Song song) {
            _tag_cache.add (song);
        }

        public void clear () {
            _store.remove_all ();
        }

        public Song? get_song (uint position) {
            return _store.get_item (position) as Song;
        }

        public async void load_tag_cache_async () {
            yield run_async<void> (_tag_cache.load);
        }

        public async void save_tag_cache_async () {
            if (_tag_cache.modified) {
                yield run_async<void> (_tag_cache.save);
            }
        }

        public async void add_files_async (File[] files) {
            var arr = new GenericArray<Object> (4096);
            yield run_async<void> (() => {
                var begin_time = get_monotonic_time ();
                foreach (var file in files) {
                    add_file (file, arr);
                }

                var queue = new AsyncQueue<Song?> ();
                for (var i = 0; i < arr.length; i++) {
                    var song = (Song) arr[i];
                    var cached_song = _tag_cache[song.uri];
                    if (cached_song != null && ((!)cached_song).modified_time == song.modified_time)
                        arr[i] = (!)cached_song;
                    else
                        queue.push (song);
                }
                var queue_count = queue.length ();
                if (queue_count > 0) {
                    var num_thread = uint.min (queue_count, get_num_processors ());
                    var threads = new Thread<void>[num_thread];
                    int percent = -1;
                    uint progress = 0;
                    for (var i = 0; i < num_thread; i++) {
                        threads[i] = new Thread<void> (@"thread$(i)", () => {
                            Song? s;
                            while ((s = queue.try_pop ()) != null) {
                                var song = (!)s;
                                parse_song_tags (song);
                                _tag_cache.add (song);
                                var per = (int) AtomicUint.add (ref progress, 1) * 100 / queue_count;
                                if (percent != per) {
                                    percent = per;
                                    Idle.add (() => {
                                        parse_progress (per);
                                        return false;
                                    });
                                }
                            }
                        });
                    }
                    foreach (var thread in threads) {
                        thread.join ();
                    }
                }

                if (_sort_mode == SortMode.SHUFFLE) {
                    Song.shuffle_order (arr);
                }
                arr.sort ((CompareFunc<Object>) _compare);
                print ("Found %u songs in %g seconds\n", arr.length,
                        (get_monotonic_time () - begin_time) / 1e6);
            });
            _store.splice (_store.get_n_items (), 0, arr.data);

            if (_tag_cache.modified) {
                save_tag_cache_async.begin ((obj, res) => {
                    save_tag_cache_async.end (res);
                });
            }
        }

        private static void add_file (File file, GenericArray<Object> arr) {
            try {
                var info = file.query_info ("standard::*,time::modified", FileQueryInfoFlags.NONE);
                if (info.get_file_type () == FileType.DIRECTORY) {
                    var stack = new Queue<File> ();
                    stack.push_tail (file);
                    while (stack.length > 0) {
                        add_directory (stack, arr);
                    }
                } else {
                    var parent = file.get_parent ();
                    var base_uri = parent != null ? get_uri_with_end_sep ((!)parent) : "";
                    var song = new_song_from_info (base_uri, info);
                    if (song != null)
                        arr.add ((!)song);
                }
            } catch (Error e) {
                warning ("Query %s: %s\n", file.get_parse_name (), e.message);
            }
        }

        private static void add_directory (Queue<File> stack, GenericArray<Object> arr) {
            var dir = stack.pop_tail ();
            try {
                var base_uri = get_uri_with_end_sep (dir);
                FileInfo? info = null;
                var enumerator = dir.enumerate_children ("standard::*,time::modified", FileQueryInfoFlags.NONE);
                while ((info = enumerator.next_file ()) != null) {
                    var pi = (!)info;
                    if (pi.get_is_hidden ()) {
                        continue;
                    } else if (pi.get_file_type () == FileType.DIRECTORY) {
                        var sub_dir = dir.resolve_relative_path (pi.get_name ());
                        stack.push_tail (sub_dir);
                    } else {
                        var song = new_song_from_info (base_uri, pi);
                        if (song != null)
                            arr.add ((!)song);
                    }
                }
            } catch (Error e) {
                warning ("Enumerate %s: %s\n", dir.get_parse_name (), e.message);
            }
        }

        private static Song? new_song_from_info (string base_uri, FileInfo info) {
            unowned var type = info.get_content_type ();
            if (type != null && ContentType.is_mime_type ((!)type, "audio/*") && !((!)type).has_suffix ("url")) {
                unowned var name = info.get_name ();
                var song = new Song ();
                // build same file uri as tracker sparql
                song.uri = base_uri + Uri.escape_string (name, null, false);
                song.title = name;
                song.modified_time = info.get_modification_date_time ()?.to_unix () ?? 0;
                return song;
            }
            return null;
        }

        private static void parse_song_tags (Song song) {
            var file = File.new_for_uri (song.uri);
            var name = song.title;
            song.title = "";

            if (file.is_native ()) {
                var tags = parse_gst_tags (file);
                if (tags != null)
                    song.from_gst_tags ((!)tags);
            }

            if (song.title.length == 0 || song.artist.length == 0) {
                //  guess tags from the file name
                var end = name.last_index_of_char ('.');
                if (end > 0) {
                    name = name.substring (0, end);
                }

                int track = 0;
                var pos = name.index_of_char ('.');
                if (pos > 0) {
                    // assume prefix number as track index
                    int.try_parse (name.substring (0, pos), out track, null, 10);
                    name = name.substring (pos + 1);
                }

                //  split the file name by '-'
                var sa = split_string (name, "-");
                var len = sa.length;
                if (song.title.length == 0) {
                    song.title = len >= 1 ? sa[len - 1] : name;
                    song.update_title_key ();
                }
                if (song.artist.length == 0) {
                    song.artist = len >= 2 ? sa[len - 2] : UNKOWN_ARTIST;
                    song.update_artist_key ();
                }
                if (song.track == UNKOWN_TRACK) {
                    if (track == 0 && len >= 3)
                        int.try_parse (sa[0], out track, null, 10);
                    if (track > 0)
                        song.track = track;
                }
            }
            if (song.album.length == 0) {
                //  assume folder name as the album
                song.album = file.get_parent ()?.get_basename () ?? UNKOWN_ALBUM;
                song.update_album_key ();
            }
        }

        private static GenericArray<string> split_string (string text, string delimiter) {
            var ar = text.split ("-");
            var sa = new GenericArray<string> (ar.length);
            foreach (var str in ar) {
                var s = str.strip ();
                if (s.length > 0)
                    sa.add (s);
            }
            return sa;
        }
    }
}
