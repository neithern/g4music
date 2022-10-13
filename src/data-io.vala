namespace Music {

    public size_t read_size (DataInputStream dis) throws IOError {
        var value = dis.read_byte ();
        switch (value) {
        case 254:
            return dis.read_uint16 ();
        case 255:
            return dis.read_uint32 ();
        default:
            return value;
        }
    }

    public void write_size (DataOutputStream dos, size_t value) throws IOError {
        if (value < 254) {
            dos.put_byte ((uint8) value);
        } else if (value <= 0xffff) {
            dos.put_byte (254);
            dos.put_uint16 ((uint16) value);
        } else {
            dos.put_byte (255);
            dos.put_uint32 ((uint32) value);
        }
    }

    public string read_string (DataInputStream dis) throws IOError {
        var size = read_size (dis);
        if ((int) size < 0 || size > 0xfffffff) { // 28 bits
            throw new IOError.INVALID_ARGUMENT (@"Size=$size");
        } else if (size > 0) {
            var buffer = new uint8[size + 1];
            if (dis.read_all (buffer[0:size], out size)) {
                buffer[size] = '\0';
                return (string) buffer;
            }
        }
        return "";
    }

    public void write_string (DataOutputStream dos, string value) throws IOError {
        size_t size = value.length;
        write_size (dos, size);
        if (size > 0) {
            unowned uint8[] data = (uint8[])value;
            dos.write_all (data[0:size], out size);
        }
    }
}