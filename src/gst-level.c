/* GStreamer
 * Copyright (C) <1999> Erik Walthinsen <omega@cse.ogi.edu>
 * Copyright (C) 2000,2001,2002,2003,2005
 *           Thomas Vander Stichele <thomas at apestaart dot org>
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
 * SECTION:element-level
 * @title: level
 *
 * Level analyses incoming audio buffers and, if the #GstLevel:message property
 * is %TRUE, generates an element message named
 * `level`: after each interval of time given by the #GstLevel:interval property.
 * The message's structure contains these fields:
 *
 * * #GstClockTime `timestamp`: the timestamp of the buffer that triggered the message.
 * * #GstClockTime `stream-time`: the stream time of the buffer.
 * * #GstClockTime `running-time`: the running_time of the buffer.
 * * #GstClockTime `duration`: the duration of the buffer.
 * * #GstClockTime `endtime`: the end time of the buffer that triggered the message as
 *   stream time (this is deprecated, as it can be calculated from stream-time + duration)
 * * #GValueArray of #gdouble `peak`: the peak power level in dB for each channel
 * * #GValueArray of #gdouble `decay`: the decaying peak power level in dB for each channel
 *   The decaying peak level follows the peak level, but starts dropping if no
 *   new peak is reached after the time given by the #GstLevel:peak-ttl.
 *   When the decaying peak level drops, it does so at the decay rate as
 *   specified by the #GstLevel:peak-falloff.
 * * #GValueArray of #gdouble `rms`: the Root Mean Square (or average power) level in dB
 *   for each channel
 *
 * ## Example application
 *
 * {{ tests/examples/level/level-example.c }}
 *
 */

#ifdef HAVE_CONFIG_H
#include "config.h"
#endif

#include <gst/gst.h>

#include <string.h>
#include <math.h>

#define EPSILON 1e-35f

/* process one (interleaved) channel of incoming samples
 * calculate square sum of samples
 * normalize and average over number of samples
 * returns a normalized cumulative square value, which can be averaged
 * to return the average power as a double between 0 and 1
 * also returns the normalized peak power (square of the highest amplitude)
 *
 * caller must assure num is a multiple of channels
 * samples for multiple channels are interleaved
 * input sample data enters in *in_data and is not modified
 * this filter only accepts signed audio data, so mid level is always 0
 *
 * for integers, this code considers the non-existent positive max value to be
 * full-scale; so max-1 will not map to 1.0
 */

#define DEFINE_INT_LEVEL_CALCULATOR(TYPE, RESOLUTION)                         \
void                                                                          \
gst_level_calculate_##TYPE (gpointer data, guint num, guint channels,         \
                            gdouble *NCS, gdouble *NPS)                       \
{                                                                             \
  TYPE * in = (TYPE *)data;                                                   \
  register guint j;                                                           \
  gdouble squaresum = 0.0;           /* square sum of the input samples */    \
  register gdouble square = 0.0;     /* Square */                             \
  register gdouble peaksquare = 0.0; /* Peak Square Sample */                 \
  gdouble normalizer;                /* divisor to get a [-1.0, 1.0] range */ \
                                                                              \
  /* *NCS = 0.0; Normalized Cumulative Square */                              \
  /* *NPS = 0.0; Normalized Peak Square */                                    \
                                                                              \
  for (j = 0; j < num; j += channels) {                                       \
    square = ((gdouble) in[j]) * in[j];                                       \
    if (square > peaksquare) peaksquare = square;                             \
    squaresum += square;                                                      \
  }                                                                           \
                                                                              \
  normalizer = (gdouble) (G_GINT64_CONSTANT(1) << (RESOLUTION * 2));          \
  *NCS = squaresum / normalizer;                                              \
  *NPS = peaksquare / normalizer;                                             \
}

DEFINE_INT_LEVEL_CALCULATOR (gint32, 31);
DEFINE_INT_LEVEL_CALCULATOR (gint16, 15);
DEFINE_INT_LEVEL_CALCULATOR (gint8, 7);

/* FIXME: use orc to calculate squaresums? */
#define DEFINE_FLOAT_LEVEL_CALCULATOR(TYPE)                                   \
void                                                                          \
gst_level_calculate_##TYPE (gpointer data, guint num, guint channels,         \
                            gdouble *NCS, gdouble *NPS)                       \
{                                                                             \
  TYPE * in = (TYPE *)data;                                                   \
  register guint j;                                                           \
  gdouble squaresum = 0.0;           /* square sum of the input samples */    \
  register gdouble square = 0.0;     /* Square */                             \
  register gdouble peaksquare = 0.0; /* Peak Square Sample */                 \
                                                                              \
  /* *NCS = 0.0; Normalized Cumulative Square */                              \
  /* *NPS = 0.0; Normalized Peak Square */                                    \
                                                                              \
  /* orc_level_squaresum_f64(&squaresum,in,num); */                           \
  for (j = 0; j < num; j += channels) {                                       \
    square = ((gdouble) in[j]) * in[j];                                       \
    if (square > peaksquare) peaksquare = square;                             \
    squaresum += square;                                                      \
  }                                                                           \
                                                                              \
  *NCS = squaresum;                                                           \
  *NPS = peaksquare;                                                          \
}

DEFINE_FLOAT_LEVEL_CALCULATOR (gfloat);
DEFINE_FLOAT_LEVEL_CALCULATOR (gdouble);

/* we would need stride to deinterleave also
static void inline
gst_level_calculate_gdouble (gpointer data, guint num, guint channels,
                            gdouble *NCS, gdouble *NPS)
{
  orc_level_squaresum_f64(NCS,(gdouble *)data,num);
  *NPS = 0.0;
}
*/
