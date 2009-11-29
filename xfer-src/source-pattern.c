/*
 * Amanda, The Advanced Maryland Automatic Network Disk Archiver
 * Copyright (c) 2008,2009 Zmanda, Inc.  All Rights Reserved.
 *
 * This program is free software; you can redistribute it and/or modify it
 * under the terms of the GNU General Public License version 2 as published
 * by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License
 * for more details.
 *
 * You should have received a copy of the GNU General Public License along
 * with this program; if not, write to the Free Software Foundation, Inc.,
 * 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA
 *
 * Contact information: Zmanda Inc., 465 S. Mathilda Ave., Suite 300
 * Sunnyvale, CA 94085, USA, or: http://www.zmanda.com
 */

#include "amxfer.h"
#include "amanda.h"
#include "simpleprng.h"

/*
 * Class declaration
 *
 * This declaration is entirely private; nothing but xfer_source_pattern() references
 * it directly.
 */

GType xfer_source_pattern_get_type(void);
#define XFER_SOURCE_PATTERN_TYPE (xfer_source_pattern_get_type())
#define XFER_SOURCE_PATTERN(obj) G_TYPE_CHECK_INSTANCE_CAST((obj), xfer_source_pattern_get_type(), XferSourcePattern)
#define XFER_SOURCE_PATTERN_CONST(obj) G_TYPE_CHECK_INSTANCE_CAST((obj), xfer_source_pattern_get_type(), XferSourcePattern const)
#define XFER_SOURCE_PATTERN_CLASS(klass) G_TYPE_CHECK_CLASS_CAST((klass), xfer_source_pattern_get_type(), XferSourcePatternClass)
#define IS_XFER_SOURCE_PATTERN(obj) G_TYPE_CHECK_INSTANCE_TYPE((obj), xfer_source_pattern_get_type ())
#define XFER_SOURCE_PATTERN_GET_CLASS(obj) G_TYPE_INSTANCE_GET_CLASS((obj), xfer_source_pattern_get_type(), XferSourcePatternClass)

static GObjectClass *parent_class = NULL;

/*
 * Main object structure
 */

typedef struct XferSourcePattern {
    XferElement __parent__;

    gboolean limited_length;
    guint64 length;
    size_t pattern_buffer_length;
    size_t current_offset;
    char * pattern;
} XferSourcePattern;

/*
 * Class definition
 */

typedef struct {
    XferElementClass __parent__;
} XferSourcePatternClass;

/*
 * Implementation
 */

static gpointer
pull_buffer_impl(
    XferElement *elt,
    size_t *size)
{
    XferSourcePattern *self = (XferSourcePattern *)elt;
    char *rval;
    char *s, *d;
    size_t l;
    size_t offset;

    /* indicate EOF on an cancel */
    if (elt->cancelled || (self->limited_length && self->length == 0)) {
	*size = 0;
	return NULL;
    }

    if (self->limited_length) {
        if (self->length == 0) {
            *size = 0;
            return NULL;
        }

        *size = MIN(10240, self->length);
        self->length -= *size;
    } else {
	*size = 10240;
    }

    rval = malloc(*size);

    /* fill the buffer "manually", instead of using fancy memcpy techniques, so
     * that this runs at about the same speed as the random source */
    l = *size;
    s = self->pattern;
    offset = self->current_offset;
    d = rval;
    while (l--) {
	*(d++) = *(s + offset++);
	if (offset >= self->pattern_buffer_length) offset = 0;
    }
    self->current_offset = offset;

    return rval;
}

static void
instance_init(
    XferElement *elt)
{
    elt->can_generate_eof = TRUE;
}

static void
class_init(
    XferSourcePatternClass * selfc)
{
    XferElementClass *klass = XFER_ELEMENT_CLASS(selfc);
    static xfer_element_mech_pair_t mech_pairs[] = {
	{ XFER_MECH_NONE, XFER_MECH_PULL_BUFFER, 1, 0},
	{ XFER_MECH_NONE, XFER_MECH_NONE, 0, 0},
    };

    klass->pull_buffer = pull_buffer_impl;

    klass->perl_class = "Amanda::Xfer::Source::Pattern";
    klass->mech_pairs = mech_pairs;

    parent_class = g_type_class_peek_parent(selfc);
}

GType
xfer_source_pattern_get_type (void)
{
    static GType type = 0;

    if G_UNLIKELY(type == 0) {
        static const GTypeInfo info = {
            sizeof (XferSourcePatternClass),
            (GBaseInitFunc) NULL,
            (GBaseFinalizeFunc) NULL,
            (GClassInitFunc) class_init,
            (GClassFinalizeFunc) NULL,
            NULL /* class_data */,
            sizeof (XferSourcePattern),
            0 /* n_preallocs */,
            (GInstanceInitFunc) instance_init,
            NULL
        };

        type = g_type_register_static (XFER_ELEMENT_TYPE, "XferSourcePattern", &info, 0);
    }

    return type;
}

/* create an element of this class; prototype is in xfer-element.h */
XferElement * xfer_source_pattern(guint64 length, void * pattern,
                                  size_t pattern_length) {
    XferSourcePattern *xsp =
        (XferSourcePattern *)g_object_new(XFER_SOURCE_PATTERN_TYPE, NULL);
    XferElement *elt = XFER_ELEMENT(xsp);

    xsp->length = length;
    xsp->limited_length = (length > 0);
    xsp->pattern = g_memdup(pattern, pattern_length);
    xsp->pattern_buffer_length = pattern_length;
    xsp->current_offset = 0;

    return elt;
}
