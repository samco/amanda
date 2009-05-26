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

#include "amanda.h"
#include "vfs-device.h"

/*
 * Type checking and casting macros
 */
#define TYPE_DVDRW_DEVICE	(dvdrw_device_get_type())
#define DVDRW_DEVICE(obj)	G_TYPE_CHECK_INSTANCE_CAST((obj), TYPE_DVDRW_DEVICE, DvdRwDevice)
#define DVDRW_DEVICE_CONST(obj)	G_TYPE_CHECK_INSTANCE_CAST((obj), TYPE_DVDRW_DEVICE, DvdRwDevice const)
#define DVDRW_DEVICE_CLASS(klass)	G_TYPE_CHECK_CLASS_CAST((klass), TYPE_DVDRW_DEVICE, DvdRwDeviceClass)
#define IS_DVDRW_DEVICE(obj)	G_TYPE_CHECK_INSTANCE_TYPE((obj), TYPE_DVDRW_DEVICE)
#define DVDRW_DEVICE_GET_CLASS(obj)	G_TYPE_INSTANCE_GET_CLASS((obj), TYPE_DVDRW_DEVICE, DvdRwDeviceClass)

/* Forward declaration */
static GType dvdrw_device_get_type(void);

/*
 * Main object structure
 */
typedef struct _DvdRwDevice DvdRwDevice;
struct _DvdRwDevice {
	VfsDevice __parent__;

	gchar *dvdrw_device;
	gchar *mount_point;
};

/*
 * Class definition
 */
typedef struct _DvdRwDeviceClass DvdRwDeviceClass;
struct _DvdRwDeviceClass {
	VfsDeviceClass __parent__;
};

G_DEFINE_TYPE(DvdRwDevice, dvdrw_device, TYPE_VFS_DEVICE)

/* Where the DVD-RW can be mounted */
static DevicePropertyBase device_property_dvdrw_mount_point;
#define PROPERTY_DVDRW_MOUNT_POINT (device_property_dvdrw_mount_point.ID)

void
dvdrw_device_register(void);

static Device*
dvdrw_device_factory(char *device_name, char *device_type, char *device_node);

static void
dvdrw_device_class_init (DvdRwDeviceClass *c);

static void
dvdrw_device_init (DvdRwDevice *self);

static gboolean
dvdrw_device_set_mount_point_fn(Device *self,
	DevicePropertyBase *base, GValue *val, PropertySurety surety, PropertySource source);

static void
dvdrw_device_open_device(Device *dself, char *device_name, char *device_type, char *device_node);

static DeviceStatusFlags
dvdrw_device_read_label(Device *dself);

static gboolean
dvdrw_device_start(Device *dself, DeviceAccessMode mode, char *label, char *timestamp);

static gboolean
dvdrw_device_finish(Device *dself);

static void
dvdrw_device_finalize(GObject *gself);

static gboolean
check_access_mode(Device *dself, DeviceAccessMode mode);

static gboolean
check_readable(Device *dself);

static DeviceStatusFlags
mount_disc(Device *dself);

static DeviceStatusFlags
unmount_disc(Device *dself);

static DeviceStatusFlags
execute_command(Device *dself, gchar **argv, gint *status);

void
dvdrw_device_register(void)
{
	const char *device_prefix_list[] = { "dvdrw", NULL };

	device_property_fill_and_register(&device_property_dvdrw_mount_point,
		G_TYPE_STRING, "dvdrw_mount_point",
		"Directory to mount DVD-RW for reading");

	register_device(dvdrw_device_factory, device_prefix_list);
}

static Device *
dvdrw_device_factory(char *device_name, char *device_type, char *device_node)
{
	Device *device;

	g_assert(0 == strncmp(device_type, "dvdrw", strlen("dvdrw")));

	device = DEVICE(g_object_new(TYPE_DVDRW_DEVICE, NULL));
	device_open_device(device, device_name, device_type, device_node);

	return device;
}

static void
dvdrw_device_class_init (DvdRwDeviceClass *c)
{
	DeviceClass *device_class = DEVICE_CLASS(c);
	GObjectClass *g_object_class = G_OBJECT_CLASS(c);

	device_class->open_device = dvdrw_device_open_device;
	device_class->read_label = dvdrw_device_read_label;
	device_class->start = dvdrw_device_start;
	device_class->finish = dvdrw_device_finish;

	g_object_class->finalize = dvdrw_device_finalize;

	device_class_register_property(device_class, PROPERTY_DVDRW_MOUNT_POINT,
		PROPERTY_ACCESS_GET_MASK | PROPERTY_ACCESS_SET_BEFORE_START,
		device_simple_property_get_fn,
		dvdrw_device_set_mount_point_fn);
}

static void
dvdrw_device_init (DvdRwDevice *self)
{
	Device *dself = DEVICE(self);
	GValue val;

	self->dvdrw_device = NULL;
	self->mount_point = NULL;

	bzero(&val, sizeof(val));

	g_value_init(&val, G_TYPE_BOOLEAN);
	g_value_set_boolean(&val, FALSE);
	device_set_simple_property(dself, PROPERTY_APPENDABLE,
		&val, PROPERTY_SURETY_GOOD, PROPERTY_SOURCE_DETECTED);
	g_value_unset(&val);

	g_value_init(&val, G_TYPE_BOOLEAN);
	g_value_set_boolean(&val, FALSE);
	device_set_simple_property(dself, PROPERTY_PARTIAL_DELETION,
		&val, PROPERTY_SURETY_GOOD, PROPERTY_SOURCE_DETECTED);
	g_value_unset(&val);

	g_value_init(&val, G_TYPE_BOOLEAN);
	g_value_set_boolean(&val, FALSE);
	device_set_simple_property(dself, PROPERTY_FULL_DELETION,
		&val, PROPERTY_SURETY_GOOD, PROPERTY_SOURCE_DETECTED);
	g_value_unset(&val);
}

static gboolean
dvdrw_device_set_mount_point_fn(Device *dself, DevicePropertyBase *base,
	GValue *val, PropertySurety surety, PropertySource source)
{
	DvdRwDevice *self = DVDRW_DEVICE(dself);

	g_free(self->mount_point);
	self->mount_point = g_value_dup_string(val);
	device_clear_volume_details(dself);

	return device_simple_property_set_fn(dself, base, val, surety, source);
}

static void
dvdrw_device_open_device(Device *dself, char *device_name, char *device_type, char *device_node)
{
	DvdRwDevice *self = DVDRW_DEVICE(dself);
	DeviceClass *parent_class = DEVICE_CLASS(g_type_class_peek_parent(DVDRW_DEVICE_GET_CLASS(dself)));
	GValue val;
	char *colon;
	char *cache_dir_parent;

	bzero(&val, sizeof(val));

	colon = index(device_node, ':');
	if (!colon)
	{
		device_set_error(dself,
			stralloc(_("DVDRW device requires cache directory and DVD-RW device separated by a colon (:) in tapedev")),
			DEVICE_STATUS_DEVICE_ERROR);
		return;
	}

	self->dvdrw_device = g_strdup(colon + 1);
	cache_dir_parent = g_strndup(device_node, colon - device_node);

	if (parent_class->open_device)
	{
		parent_class->open_device(dself, device_name, device_type, cache_dir_parent);
	}

	g_free(cache_dir_parent);
}

static DeviceStatusFlags
dvdrw_device_read_label(Device *dself)
{
	VfsDevice *vself = VFS_DEVICE(dself);
	DvdRwDevice *self = DVDRW_DEVICE(dself);
	DeviceClass *parent_class = DEVICE_CLASS(g_type_class_peek_parent(DVDRW_DEVICE_GET_CLASS(dself)));
	DeviceStatusFlags status;
	gchar *old_dir_name;

	if (device_in_error(dself)) return DEVICE_STATUS_DEVICE_ERROR;
	if (!check_readable(dself)) return DEVICE_STATUS_DEVICE_ERROR;

	status = mount_disc(dself);
	if (status != DEVICE_STATUS_SUCCESS)
	{
		return status;
	}

	old_dir_name = vself->dir_name;
	vself->dir_name = self->mount_point;
	status = parent_class->read_label(dself);
	vfs_release_file(vself);
	vself->dir_name = old_dir_name;

	if (status == DEVICE_STATUS_SUCCESS)
	{
		status = unmount_disc(dself);
	}
	else
	{
		/* Ignore further errors */
		unmount_disc(dself);
	}

	return status;
}

static gboolean
dvdrw_device_start(Device *dself, DeviceAccessMode mode, char *label, char *timestamp)
{
	DeviceClass *parent_class = DEVICE_CLASS(g_type_class_peek_parent(DVDRW_DEVICE_GET_CLASS(dself)));

	if (device_in_error(dself)) return FALSE;
	if (!check_access_mode(dself, mode)) return FALSE;

	dself->access_mode = mode;

	if (mode == ACCESS_READ)
	{
		if (device_read_label(dself) != DEVICE_STATUS_SUCCESS)
		{
			return FALSE;
		}

		return TRUE;
	}
	else if (mode == ACCESS_WRITE)
	{
		return parent_class->start(dself, mode, label, timestamp);
	}
	else
	{
		return FALSE;
	}
}

static gboolean
dvdrw_device_finish(Device *dself)
{
	VfsDevice *vself = VFS_DEVICE(dself);
	DvdRwDevice *self = DVDRW_DEVICE(dself);
	DeviceClass *parent_class = DEVICE_CLASS(g_type_class_peek_parent(DVDRW_DEVICE_GET_CLASS(dself)));
	gint status;
	char *burn_argv[] = {GROWISOFS, "-use-the-force-luke",
		"-Z", self->dvdrw_device,
		"-J", "-R", "-pad", "-quiet",
		vself->dir_name, NULL};

	if (device_in_error(dself)) return FALSE;

	parent_class->finish(dself);

	if (execute_command(dself, burn_argv, &status) != DEVICE_STATUS_SUCCESS)
	{
		return FALSE;
	}

	return TRUE;
}

static void
dvdrw_device_finalize(GObject *gself)
{
	GObjectClass *parent_class = G_OBJECT_CLASS(g_type_class_peek_parent(DVDRW_DEVICE_GET_CLASS(gself)));
	DvdRwDevice *self = DVDRW_DEVICE(gself);

	if (parent_class->finalize)
	{
		parent_class->finalize(gself);
	}

	g_free(self->dvdrw_device);
	g_free(self->mount_point);
}

static gboolean
check_access_mode(Device *dself, DeviceAccessMode mode)
{
	if (mode == ACCESS_READ)
	{
		return check_readable(dself);
	}
	else if (mode == ACCESS_WRITE)
	{
		return TRUE;
	}

	device_set_error(dself,
		stralloc(_("DVDRW device can only be opened in READ or WRITE mode")),
		DEVICE_STATUS_DEVICE_ERROR);

	return FALSE;
}

static gboolean
check_readable(Device *dself)
{
	GValue value;
	bzero(&value, sizeof(value));

	if (! device_get_simple_property(dself, PROPERTY_DVDRW_MOUNT_POINT, &value, NULL, NULL))
	{
		device_set_error(dself,
			stralloc(_("DVDRW device requires DVDRW_MOUNT_POINT to open device for reading")),
			DEVICE_STATUS_DEVICE_ERROR);

		return FALSE;
	}

	return TRUE;
}

static DeviceStatusFlags
mount_disc(Device *dself)
{
	gchar *argv[] = { "mount", DVDRW_DEVICE(dself)->dvdrw_device, NULL };
	gint status;

	return execute_command(dself, argv, &status);
}

static DeviceStatusFlags
unmount_disc(Device *dself)
{
	gchar *argv[] = { "umount", DVDRW_DEVICE(dself)->dvdrw_device, NULL };
	gint result;

	return execute_command(dself, argv, &result);
}

static DeviceStatusFlags
execute_command(Device *dself, gchar **argv, gint *result)
{
	GError *error = NULL;

	g_spawn_sync(NULL, argv, NULL, G_SPAWN_STDOUT_TO_DEV_NULL | G_SPAWN_SEARCH_PATH,
		NULL, NULL, NULL, NULL, result, &error);
	if (error || (*result != 0))
	{
		gchar *error_message = vstrallocf(_("DVDRW device cannot execute '%s': %s (status %d)"),
			argv[0], error ? error->message : _("Unknown error"), *result);

		device_set_error(dself, error_message, DEVICE_STATUS_DEVICE_ERROR);

		if (error)
		{
			g_error_free(error);
		}

		return DEVICE_STATUS_DEVICE_ERROR;
	}

	return DEVICE_STATUS_SUCCESS;
}
