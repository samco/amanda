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

#ifndef DIRECTTCP_H
#define DIRECTTCP_H

#include <glib.h>

/* A combination of IP address (expressed as an integer) and port.  These are
 * commonly seen in arrays terminated by a {0,0}.  Note that, right now, only
 * IPv4 addresses are supported (since this is all that NDMP supports). */
typedef struct DirectTCPAddr_ {
    guint32 ipv4;
    guint16 port;
} DirectTCPAddr;

#endif /* DIRECTTCP_H */
