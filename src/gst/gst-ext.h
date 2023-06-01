#ifndef __GST_EXT_H__
#define __GST_EXT_H__

#include <gst/gst.h>

G_BEGIN_DECLS

GstTagList * ape_demux_parse_tags (const guint8 * data, gint size);

G_END_DECLS

#endif /* __GST_EXT_H__ */
