namespace G4 {

    public class LevelCalculator {
        struct Peak {
            Gst.ClockTime time;
            double peak;
        }

        private int _audio_channels = 2;
        private int _audio_bps = 2;
        private int _sample_bps = 2;
        private unowned Gst.Caps? _last_caps = null;
        private unowned Gst.ClockTime _last_sample_time = Gst.CLOCK_TIME_NONE;
        private LevelCalculateFunc? _level_calculate = null;
        private Queue<Peak?> _peaks = new Queue<Peak?> ();

        public void clear () {
            _last_sample_time = Gst.CLOCK_TIME_NONE;
            _peaks.clear ();
        }

        public void calculate_sample (Gst.Sample sample, Gst.ClockTime position, ref double peak_value) {
            var peak = Peak ();
            peak.time = sample.get_segment ().position;
            if (_last_sample_time != peak.time
                    && calculate_peak_in_sample (sample, out peak.peak)) {
                _peaks.push_tail (peak);
                _last_sample_time = peak.time;
            }
            while (_peaks.length > 0) {
                unowned var p = (!)_peaks.peek_head ();
                if (p.time >= position) {
                    peak_value = p.peak;
                    _peaks.pop_head ();
                } else {
                    break;
                }
            }
        }

        private delegate void LevelCalculateFunc (uint8* data, uint num, uint channels, uint value_size, uint sample_size, out double nps);

        private bool calculate_peak_in_sample (Gst.Sample sample, out double peak) {
            peak = 0;

            unowned var caps = sample.get_caps ();
            if (_last_caps != caps || _level_calculate == null) {
                unowned var st = caps?.get_structure (0);
                st?.get_int ("channels", out _audio_channels);
                if (_audio_channels == 0)
                    return false;

                unowned var format = st?.get_string ("format") ?? "";
                switch (format) {
                    case "S8":
                        _audio_bps = _sample_bps = 1;
                        _level_calculate = level_calculate_int;
                        break;
                    case "S16LE":
                        _audio_bps = _sample_bps = 2;
                        _level_calculate = level_calculate_int16;
                        break;
                    case "S24LE":
                        _audio_bps = _sample_bps = 3;
                        _level_calculate = level_calculate_int;
                        break;
                    case "S24_32LE":
                        _audio_bps = 3;
                        _sample_bps = 4;
                        _level_calculate = level_calculate_int;
                        break;
                    case "S32LE":
                        _audio_bps = _sample_bps = 4;
                        _level_calculate = level_calculate_int;
                        break;
                    case "F32LE":
                        _audio_bps = _sample_bps = 4;
                        _level_calculate = level_calculate_float;
                        break;
                    case "F64LE":
                        _audio_bps = _sample_bps = 8;
                        _level_calculate = level_calculate_double;
                        break;
                    default:
                        print ("Unsupported sample format: %s\n", format);
                        return false;
                }
                _last_caps = caps;
            }

            var channels = _audio_channels;
            var bps = _audio_bps;
            var sample_size = _sample_bps;
            var block_size = channels * sample_size;
            var buffer = sample.get_buffer ();
            var size = buffer?.get_size () ?? 0;

            Gst.MapInfo? map_info = null;
            if (buffer?.map (out map_info, Gst.MapFlags.READ) ?? false) {
                unowned uint8* p = ((!)map_info).data;
                var num = (uint) (size / block_size);
                double total_nps = 0;
                for (var i = 0; i < channels; i++) {
                    double nps = 0;
                    _level_calculate (p + (sample_size * i), num, channels, bps, sample_size, out nps);
                    total_nps += nps;
                }
                peak = double.min (total_nps / channels, 1);
                buffer?.unmap ((!)map_info);
                return true;
            }
            return false;
        }
    }

    void level_calculate_double (uint8* data, uint num, uint channels, uint value_size, uint sample_size, out double nps) {
        double peak = 0;
        double* p = (double*)data;
        for (uint i = 0; i < num; i += channels) {
            double value = p[i] >= 0 ? p[i] : -p[i];
            if (peak < value)
                peak = value;
        }
        nps = peak * peak;
    }

    void level_calculate_float (uint8* data, uint num, uint channels, uint value_size, uint sample_size, out double nps) {
        float peak = 0f;
        float* p = (float*)data;
        for (uint i = 0; i < num; i += channels) {
            float value = p[i] >= 0 ? p[i] : -p[i];
            if (peak < value)
                peak = value;
        }
        nps = (double) peak * peak;
    }

    void level_calculate_int16 (uint8* data, uint num, uint channels, uint value_size, uint sample_size, out double nps) {
        int16 peak = 0;
        int16* p = (int16*)data;
        for (uint i = 0; i < num; i += channels) {
            int16 value = p[i] >= 0 ? p[i] : -p[i];
            if (peak < value)
                peak = value;
        }
        nps = (double) peak * peak / (((int64) 1) << (15 * 2));
    }

    void level_calculate_int (uint8* data, uint num, uint channels, uint value_size, uint sample_size, out double nps) {
        int32 peak = 0;
        uint block_size = channels * sample_size;
        for (uint i = 0; i < num; i += channels) {
            int32 value = 0;
            uint8* p = (uint8*)&value + (4 - value_size);
            for (uint j = 0; j < value_size; j++) {
                p[j] = data[j];
            }
            data += block_size;
            value = value >= 0 ? value : -value;
            if (peak < value)
                peak = value;
        }
        nps = (double) peak * peak / (((int64) 1) << (31 * 2));
    }
}