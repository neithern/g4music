/* GStreamer APEv1/2 tag reader
 * Copyright (C) 2004 Ronald Bultje <rbultje@ronald.bitfreak.net>
 * Copyright (C) 2006 Tim-Philipp Müller <tim centricular net>
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Library General Public
 * License as published by the Free Software Foundation; either
 * version 2 of the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Library General Public License for more details.
 *
 * You should have received a copy of the GNU Library General Public
 * License along with this library; if not, write to the
 * Free Software Foundation, Inc., 51 Franklin St, Fifth Floor,
 * Boston, MA 02110-1301, USA.
 */

/**
 * SECTION:element-apedemux
 * @title: apedemux
 *
 * apedemux accepts data streams with APE tags at the start or at the end
 * (or both). The mime type of the data between the tag blocks is detected
 * using typefind functions, and the appropriate output mime type set on
 * outgoing buffers.
 *
 * The element is only able to read APE tags at the end of a stream from
 * a seekable stream, ie. when get_range mode is supported by the upstream
 * elements. If get_range operation is available, apedemux makes it available
 * downstream. This means that elements which require get_range mode, such as
 * wavparse or musepackdec, can operate on files containing APE tag
 * information.
 *
 * ## Example launch line
 * |[
 * gst-launch-1.0 -t filesrc location=file.mpc ! apedemux ! fakesink
 * ]| This pipeline should read any available APE tag information and output it.
 * The contents of the file inside the APE tag regions should be detected, and
 * the appropriate mime type set on buffers produced from apedemux.
 *
 */
#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <gst/gst.h>

#include <stdio.h>
#include <string.h>

static const struct _GstApeDemuxTagTableEntry
{
  const gchar *ape_tag;
  const gchar *gst_tag;
} tag_table[] = {
  {
  "replaygain_track_gain", GST_TAG_TRACK_GAIN}, {
  "replaygain_track_peak", GST_TAG_TRACK_PEAK}, {
  "replaygain_album_gain", GST_TAG_ALBUM_GAIN}, {
  "replaygain_album_peak", GST_TAG_ALBUM_PEAK}, {
  "title", GST_TAG_TITLE}, {
  "artist", GST_TAG_ARTIST}, {
  "album", GST_TAG_ALBUM}, {
  "composer", GST_TAG_COMPOSER}, {
  "comment", GST_TAG_COMMENT}, {
  "comments", GST_TAG_COMMENT}, {
  "copyright", GST_TAG_COPYRIGHT}, {
  "genre", GST_TAG_GENRE}, {
  "isrc", GST_TAG_ISRC}, {
  "disc", GST_TAG_ALBUM_VOLUME_NUMBER}, {
  "disk", GST_TAG_ALBUM_VOLUME_NUMBER}, {
  "discnumber", GST_TAG_ALBUM_VOLUME_NUMBER}, {
  "disknumber", GST_TAG_ALBUM_VOLUME_NUMBER}, {
  "track", GST_TAG_TRACK_NUMBER}, {
  "tracknumber", GST_TAG_TRACK_NUMBER}, {
  "year", GST_TAG_DATE}, {
  "file", GST_TAG_LOCATION}
};

static gboolean
ape_demux_get_gst_tag_from_tag (const gchar * ape_tag,
    const gchar ** gst_tag, GType * gst_tag_type)
{
  gint i;

  for (i = 0; i < G_N_ELEMENTS (tag_table); ++i) {
    if (g_ascii_strcasecmp (tag_table[i].ape_tag, ape_tag) == 0) {
      *gst_tag = tag_table[i].gst_tag;
      *gst_tag_type = gst_tag_get_type (tag_table[i].gst_tag);
      GST_LOG ("Mapped APE tag '%s' to GStreamer tag '%s'", ape_tag, *gst_tag);
      return TRUE;
    }
  }

  GST_WARNING ("Could not map APE tag '%s' to a GStreamer tag", ape_tag);
  return FALSE;
}

GstTagList *
ape_demux_parse_tags (const guint8 * data, gint size)
{
  GstTagList *taglist = gst_tag_list_new_empty ();

  GST_LOG ("Reading tags from chunk of size %u bytes", size);

  /* get rid of header/footer */
  if (size >= 32 && memcmp (data, "APETAGEX", 8) == 0) {
    data += 32;
    size -= 32;
  }
  if (size > 32 && memcmp (data + size - 32, "APETAGEX", 8) == 0) {
    size -= 32;
  }

  /* read actual tags - at least 10 bytes for tag header */
  while (size >= 10) {
    guint len, n = 8;
    gchar *tag, *val;
    const gchar *gst_tag;
    GType gst_tag_type;

    /* find tag type and size */
    len = GST_READ_UINT32_LE (data);
    while (n < size && data[n] != 0x0)
      n++;
    if (n == size)
      break;
    g_assert (data[n] == 0x0);
    n++;
    if (size - n < len)
      break;

    /* If the tag is empty, skip to the next one */
    if (len == 0)
      goto next_tag;

    /* read */
    tag = g_strndup ((gchar *) data + 8, n - 9);
    val = g_strndup ((gchar *) data + n, len);

    GST_LOG ("tag [%s], val[%s]", tag, val);

    /* special-case 'media' tag, could be e.g. "CD 1/2" */
    if (g_ascii_strcasecmp (tag, "media") == 0) {
      gchar *sp, *sp2;

      g_free (tag);
      tag = g_strdup ("discnumber");
      /* get rid of the medium in front */
      sp = strchr (val, ' ');
      while (sp != NULL && (sp2 = strchr (sp + 1, ' ')) != NULL)
        sp = sp2;
      if (sp) {
        memmove (val, sp + 1, strlen (sp + 1) + 1);
      }
    }

    if (ape_demux_get_gst_tag_from_tag (tag, &gst_tag, &gst_tag_type)) {
      GValue v = { 0, };

      switch (gst_tag_type) {
        case G_TYPE_INT:{
          gint v_int;

          if (sscanf (val, "%d", &v_int) == 1) {
            g_value_init (&v, G_TYPE_INT);
            g_value_set_int (&v, v_int);
          }
          break;
        }
        case G_TYPE_UINT:{
          guint v_uint, count;

          if (strcmp (gst_tag, GST_TAG_TRACK_NUMBER) == 0) {
            gint dummy;

            if (sscanf (val, "%u", &v_uint) == 1 && v_uint > 0) {
              g_value_init (&v, G_TYPE_UINT);
              g_value_set_uint (&v, v_uint);
            }
            GST_LOG ("checking for track count: %s", val);
            /* might be 0/N or -1/N to specify that there is only a count */
            if (sscanf (val, "%d/%u", &dummy, &count) == 2 && count > 0) {
              gst_tag_list_add (taglist, GST_TAG_MERGE_APPEND,
                  GST_TAG_TRACK_COUNT, count, NULL);
            }
          } else if (strcmp (gst_tag, GST_TAG_ALBUM_VOLUME_NUMBER) == 0) {
            gint dummy;

            if (sscanf (val, "%u", &v_uint) == 1 && v_uint > 0) {
              g_value_init (&v, G_TYPE_UINT);
              g_value_set_uint (&v, v_uint);
            }
            GST_LOG ("checking for volume count: %s", val);
            /* might be 0/N or -1/N to specify that there is only a count */
            if (sscanf (val, "%d/%u", &dummy, &count) == 2 && count > 0) {
              gst_tag_list_add (taglist, GST_TAG_MERGE_APPEND,
                  GST_TAG_ALBUM_VOLUME_COUNT, count, NULL);
            }
          } else if (sscanf (val, "%u", &v_uint) == 1) {
            g_value_init (&v, G_TYPE_UINT);
            g_value_set_uint (&v, v_uint);
          }
          break;
        }
        case G_TYPE_STRING:{
          g_value_init (&v, G_TYPE_STRING);
          g_value_set_string (&v, val);
          break;
        }
        case G_TYPE_DOUBLE:{
          gdouble v_double;
          gchar *endptr;

          /* floating point strings can be "4,123" or "4.123" depending on
           * the locale. We need to be able to parse and read either version
           * no matter what our current locale is */
          g_strdelimit (val, ",", '.');
          v_double = g_ascii_strtod (val, &endptr);
          if (endptr != val) {
            g_value_init (&v, G_TYPE_DOUBLE);
            g_value_set_double (&v, v_double);
          }

          break;
        }
        default:{
          if (gst_tag_type == G_TYPE_DATE) {
            gint v_int;

            if (sscanf (val, "%d", &v_int) == 1) {
              GDate *date = g_date_new_dmy (1, 1, v_int);

              g_value_init (&v, G_TYPE_DATE);
              g_value_take_boxed (&v, date);
            }
          } else {
            GST_WARNING ("Unhandled tag type '%s' for tag '%s'",
                g_type_name (gst_tag_type), gst_tag);
          }
          break;
        }
      }
      if (G_VALUE_TYPE (&v) != 0) {
        gst_tag_list_add_values (taglist, GST_TAG_MERGE_APPEND,
            gst_tag, &v, NULL);
        g_value_unset (&v);
      }
    }
    GST_DEBUG ("Read tag %s: %s", tag, val);
    g_free (tag);
    g_free (val);

    /* move data pointer */
  next_tag:
    size -= len + n;
    data += len + n;
  }

  GST_DEBUG ("Taglist: %" GST_PTR_FORMAT, taglist);
  return taglist;
}
