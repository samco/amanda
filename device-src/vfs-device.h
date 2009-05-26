/*
 * Copyright (c) 2005-2008 Zmanda Inc.  All Rights Reserved.
 *
 * This library is free software; you can redistribute it and/or modify it
 * under the terms of the GNU Lesser General Public License version 2.1 as
 * published by the Free Software Foundation.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
 * License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public License
 * along with this library; if not, write to the Free Software Foundation,
 * Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307 USA.
 *
 * Contact information: Zmanda Inc., 465 S Mathlida Ave, Suite 300
 * Sunnyvale, CA 94086, USA, or: http://www.zmanda.com
 */

#include "device.h"

/*
 * Type checking and casting macros
 */
#define TYPE_VFS_DEVICE	(vfs_device_get_type())
#define VFS_DEVICE(obj)	G_TYPE_CHECK_INSTANCE_CAST((obj), vfs_device_get_type(), VfsDevice)
#define VFS_DEVICE_CONST(obj)	G_TYPE_CHECK_INSTANCE_CAST((obj), vfs_device_get_type(), VfsDevice const)
#define VFS_DEVICE_CLASS(klass)	G_TYPE_CHECK_CLASS_CAST((klass), vfs_device_get_type(), VfsDeviceClass)
#define IS_VFS_DEVICE(obj)	G_TYPE_CHECK_INSTANCE_TYPE((obj), vfs_device_get_type ())

#define VFS_DEVICE_GET_CLASS(obj)	G_TYPE_INSTANCE_GET_CLASS((obj), vfs_device_get_type(), VfsDeviceClass)

GType	vfs_device_get_type	(void);

/*
 * Main object structure
 */
typedef struct {
    Device __parent__;

    /*< private >*/
    char * dir_name;
    char * file_name;
    int open_file_fd;

    /* Properties */
    guint64 volume_bytes;
    guint64 volume_limit;
} VfsDevice;

/*
 * Class definition
 */
typedef struct {
    DeviceClass __parent__;
} VfsDeviceClass;


/* Possible (abstracted) results from a system I/O operation. */
typedef enum {
    RESULT_SUCCESS,
    RESULT_ERROR,        /* Undefined error. */
    RESULT_NO_DATA,      /* End of File, while reading */
    RESULT_NO_SPACE,     /* Out of space. Sometimes we don't know if
                            it was this or I/O error, but this is the
                            preferred explanation. */
    RESULT_MAX
} IoResult;

void vfs_release_file(VfsDevice * self);
