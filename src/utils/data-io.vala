namespace G4 {

    //  Use BIG_ENDIAN, same as DataInputStream's default byte order
    public class DataInputBytes : Object {
        private Bytes _bytes;
        private unowned uint8[] _data;
        private int _pos = 0;
        private int _length;

        public DataInputBytes (Bytes bytes) {
            _bytes = bytes;
            _data = bytes.get_data ();
            _length = bytes.length;
        }

        public inline uint8 read_byte () throws IOError {
            if (_pos + 1 > _length)
                throw new IOError.INVALID_ARGUMENT (@"Pos:$_pos+1>$_length");
            return _data[_pos++];
        }

        public inline uint16 read_uint16 () throws IOError {
            if (_pos + 2 > _length)
                throw new IOError.INVALID_ARGUMENT (@"Pos:$_pos+2>$_length");
            return ((uint16) (_data[_pos++]) << 8) | _data[_pos++];
        }

        public inline uint32 read_uint32 () throws IOError {
            if (_pos + 4 > _length)
                throw new IOError.INVALID_ARGUMENT (@"Pos:$_pos+4>$_length");
            return ((uint32) (_data[_pos++]) << 24)
                | ((uint32) (_data[_pos++]) << 16)
                | ((uint32) (_data[_pos++]) << 8)
                | _data[_pos++];
        }

        public inline uint64 read_uint64 () throws IOError {
            uint64 hi = read_uint32 ();
            uint64 lo = read_uint32 ();
            return (hi << 32) | lo;
        }

        public size_t read_size () throws IOError {
            var n = read_byte ();
            switch (n) {
            case 254:
                return read_uint16 ();
            case 255:
                return read_uint32 ();
            default:
                return n;
            }
        }

        public string read_string () throws IOError {
            var size = (int) read_size ();
            if (size < 0 || _pos + size < 0 || _pos + size > _length) {
                throw new IOError.INVALID_ARGUMENT (@"Size:$_pos+$size>$_length");
            } else if (size > 0) {
                var value = strndup ((char*) _data + _pos, size);
                _pos += size;
                return value;
            }
            return "";
        }

        public void reset () {
            _pos = 0;
        }
    }

    //  Use BIG_ENDIAN, same as DataOutputStream's default byte order
    public class DataOutputBytes : Object {
        private ByteArray _bytes;
        private uint8[] _data = new uint8[4];

        public DataOutputBytes (uint reserved_size = 4096) {
            _bytes = new ByteArray.sized (reserved_size);
        }

        public inline void write_byte (uint8 n) {
            _data[0] = n;
            _bytes.append (_data[0:1]);
        }

        public inline void write_uint16 (uint16 n) {
            _data[0] = (uint8) (n >> 8);
            _data[1] = (uint8) (n);
            _bytes.append (_data[0:2]);
        }

        public inline void write_uint32 (uint32 n) {
            _data[0] = (uint8) (n >> 24);
            _data[1] = (uint8) (n >> 16);
            _data[2] = (uint8) (n >> 8);
            _data[3] = (uint8) (n);
            _bytes.append (_data[0:4]);
        }

        public inline void write_uint64 (uint64 n) {
            var hi = (uint32) (n >> 32);
            var lo = (uint32) (n);
            write_uint32 (hi);
            write_uint32 (lo);
        }

        public void write_size (size_t n) {
            if (n < 254) {
                write_byte ((uint8) n);
            } else if (n <= 0xffff) {
                write_byte (254);
                write_uint16 ((uint16) n);
            } else {
                write_byte (255);
                write_uint32 ((uint32) n);
            }
        }

        public void write_string (string str) {
            size_t size = str.length;
            write_size (size);
            if (size > 0) {
                unowned uint8[] data = (uint8[])str;
                _bytes.append (data[0:size]);
            }
        }

        public bool write_to (OutputStream stream) throws IOError {
            size_t bytes_written = 0;
            return stream.write_all (_bytes.data, out bytes_written);
        }
    }
}
