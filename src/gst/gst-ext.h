#ifndef __GST_EXT_H__
#define __GST_EXT_H__

#include <gst/gst.h>

G_BEGIN_DECLS

GstTagList * ape_demux_parse_tags (const guint8 * data, gint size);

void gst_level_calculate_gint8   (gpointer data, guint num, guint channels, gdouble *NCS, gdouble *NPS);
void gst_level_calculate_gint16  (gpointer data, guint num, guint channels, gdouble *NCS, gdouble *NPS);
void gst_level_calculate_gint32  (gpointer data, guint num, guint channels, gdouble *NCS, gdouble *NPS);
void gst_level_calculate_gfloat  (gpointer data, guint num, guint channels, gdouble *NCS, gdouble *NPS);
void gst_level_calculate_gdouble (gpointer data, guint num, guint channels, gdouble *NCS, gdouble *NPS);

G_END_DECLS

#endif /* __GST_EXT_H__ */
