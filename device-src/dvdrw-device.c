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
	gchar *cache_dir;
	gchar *mount_point;
	gchar *data_dir;
	gboolean keep_cache;
	gchar *growisofs_command;
	gchar *mount_command;
	gchar *umount_command;
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

/* Should the on-disk version be kept after the optical disc has been written? */
static DevicePropertyBase device_property_dvdrw_keep_cache;
#define PROPERTY_DVDRW_KEEP_CACHE (device_property_dvdrw_keep_cache.ID)

/* Where to find the growisofs command */
static DevicePropertyBase device_property_dvdrw_growisofs_command;
#define PROPERTY_DVDRW_GROWISOFS_COMMAND (device_property_dvdrw_growisofs_command.ID)

/* Where to find the filesystem mount command */
static DevicePropertyBase device_property_dvdrw_mount_command;
#define PROPERTY_DVDRW_MOUNT_COMMAND (device_property_dvdrw_mount_command.ID)

/* Where to find the filesystem unmount command */
static DevicePropertyBase device_property_dvdrw_umount_command;
#define PROPERTY_DVDRW_UMOUNT_COMMAND (device_property_dvdrw_umount_command.ID)

/* GObject housekeeping */
void
dvdrw_device_register(void);

static Device*
dvdrw_device_factory(char *device_name, char *device_type, char *device_node);

static void
dvdrw_device_class_init (DvdRwDeviceClass *c);

static void
dvdrw_device_init (DvdRwDevice *self);

/* Properties */
static gboolean
dvdrw_device_set_mount_point_fn(Device *self,
	DevicePropertyBase *base, GValue *val, PropertySurety surety, PropertySource source);

static gboolean
dvdrw_device_set_keep_cache_fn(Device *self,
	DevicePropertyBase *base, GValue *val, PropertySurety surety, PropertySource source);

static gboolean
dvdrw_device_set_growisofs_command_fn(Device *self,
	DevicePropertyBase *base, GValue *val, PropertySurety surety, PropertySource source);

static gboolean
dvdrw_device_set_mount_command_fn(Device *self,
	DevicePropertyBase *base, GValue *val, PropertySurety surety, PropertySource source);

static gboolean
dvdrw_device_set_umount_command_fn(Device *self,
	DevicePropertyBase *base, GValue *val, PropertySurety surety, PropertySource source);

/* Methods */
static void
dvdrw_device_open_device(Device *dself, char *device_name, char *device_type, char *device_node);

static DeviceStatusFlags
dvdrw_device_read_label(Device *dself);

static gboolean
dvdrw_device_start(Device *dself, DeviceAccessMode mode, char *label, char *timestamp);

static gboolean
dvdrw_device_start_file(Device *dself, dumpfile_t * ji);

static dumpfile_t *
dvdrw_device_seek_file(Device * dself, guint requested_file);

static gboolean
dvdrw_device_erase(Device * dself);

static gboolean
dvdrw_device_finish(Device *dself);

static void
dvdrw_device_finalize(GObject *gself);

/* Helper functions */
static gboolean
check_access_mode(DvdRwDevice *self, DeviceAccessMode mode);

static gboolean
check_readable(DvdRwDevice *self);

static DeviceStatusFlags
mount_disc(DvdRwDevice *self);

static void
unmount_disc(DvdRwDevice *self);

static gboolean
burn_disc(DvdRwDevice *self);

static DeviceStatusFlags
execute_command(DvdRwDevice *self, gchar **argv, gint *status);

void
dvdrw_device_register(void)
{
	const char *device_prefix_list[] = { "dvdrw", NULL };

	device_property_fill_and_register(&device_property_dvdrw_mount_point,
		G_TYPE_STRING, "dvdrw_mount_point",
		"Directory to mount DVD-RW for reading");

	device_property_fill_and_register(&device_property_dvdrw_keep_cache,
		G_TYPE_BOOLEAN, "dvdrw_keep_cache",
		"Keep on-disk cache after DVD-RW has been written");

	device_property_fill_and_register(&device_property_dvdrw_growisofs_command,
		G_TYPE_BOOLEAN, "dvdrw_growisofs_command",
		"The location of the growisofs command used to write the DVD-RW");

	device_property_fill_and_register(&device_property_dvdrw_mount_command,
		G_TYPE_BOOLEAN, "dvdrw_mount_command",
		"The location of the mount command used to mount the DVD-RW filesystem for reading");

	device_property_fill_and_register(&device_property_dvdrw_umount_command,
		G_TYPE_BOOLEAN, "dvdrw_umount_command",
		"The location of the umount command used to unmount the DVD-RW filesystem after reading");

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
	device_class->start_file = dvdrw_device_start_file;
	device_class->seek_file = dvdrw_device_seek_file;
	device_class->erase = dvdrw_device_erase;
	device_class->finish = dvdrw_device_finish;

	g_object_class->finalize = dvdrw_device_finalize;

	device_class_register_property(device_class, PROPERTY_DVDRW_MOUNT_POINT,
		PROPERTY_ACCESS_GET_MASK | PROPERTY_ACCESS_SET_BEFORE_START,
		device_simple_property_get_fn,
		dvdrw_device_set_mount_point_fn);

	device_class_register_property(device_class, PROPERTY_DVDRW_KEEP_CACHE,
		PROPERTY_ACCESS_GET_MASK | PROPERTY_ACCESS_SET_BEFORE_START,
		device_simple_property_get_fn,
		dvdrw_device_set_keep_cache_fn);

	device_class_register_property(device_class, PROPERTY_DVDRW_GROWISOFS_COMMAND,
		PROPERTY_ACCESS_GET_MASK | PROPERTY_ACCESS_SET_BEFORE_START,
		device_simple_property_get_fn,
		dvdrw_device_set_growisofs_command_fn);

	device_class_register_property(device_class, PROPERTY_DVDRW_MOUNT_COMMAND,
		PROPERTY_ACCESS_GET_MASK | PROPERTY_ACCESS_SET_BEFORE_START,
		device_simple_property_get_fn,
		dvdrw_device_set_mount_command_fn);

	device_class_register_property(device_class, PROPERTY_DVDRW_UMOUNT_COMMAND,
		PROPERTY_ACCESS_GET_MASK | PROPERTY_ACCESS_SET_BEFORE_START,
		device_simple_property_get_fn,
		dvdrw_device_set_umount_command_fn);
}

static void
dvdrw_device_init (DvdRwDevice *self)
{
	Device *dself = DEVICE(self);
	GValue val;

	self->dvdrw_device = NULL;
	self->cache_dir = NULL;
	self->mount_point = NULL;
	self->data_dir = NULL;
	self->keep_cache = FALSE;
	self->growisofs_command = NULL;
	self->mount_command = NULL;
	self->umount_command = NULL;

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

	amfree(self->mount_point);
	amfree(self->data_dir);

	self->mount_point = g_value_dup_string(val);
	self->data_dir = g_strconcat(self->mount_point, "/data/", NULL);

	device_clear_volume_details(dself);

	return device_simple_property_set_fn(dself, base, val, surety, source);
}

static gboolean
dvdrw_device_set_keep_cache_fn(Device *dself, DevicePropertyBase *base,
	GValue *val, PropertySurety surety, PropertySource source)
{
	DvdRwDevice *self = DVDRW_DEVICE(dself);

	self->keep_cache = g_value_get_boolean(val);

	return device_simple_property_set_fn(dself, base, val, surety, source);
}

static gboolean
dvdrw_device_set_growisofs_command_fn(Device *dself, DevicePropertyBase *base,
	GValue *val, PropertySurety surety, PropertySource source)
{
	DvdRwDevice *self = DVDRW_DEVICE(dself);

	self->growisofs_command = g_value_dup_string(val);

	return device_simple_property_set_fn(dself, base, val, surety, source);
}

static gboolean
dvdrw_device_set_mount_command_fn(Device *dself, DevicePropertyBase *base,
	GValue *val, PropertySurety surety, PropertySource source)
{
	DvdRwDevice *self = DVDRW_DEVICE(dself);

	self->mount_command = g_value_dup_string(val);

	return device_simple_property_set_fn(dself, base, val, surety, source);
}

static gboolean
dvdrw_device_set_umount_command_fn(Device *dself, DevicePropertyBase *base,
	GValue *val, PropertySurety surety, PropertySource source)
{
	DvdRwDevice *self = DVDRW_DEVICE(dself);

	self->umount_command = g_value_dup_string(val);

	return device_simple_property_set_fn(dself, base, val, surety, source);
}

static void
dvdrw_device_open_device(Device *dself, char *device_name, char *device_type, char *device_node)
{
	DvdRwDevice *self = DVDRW_DEVICE(dself);
	DeviceClass *parent_class = DEVICE_CLASS(g_type_class_peek_parent(DVDRW_DEVICE_GET_CLASS(dself)));
	GValue val;
	char *colon;

	g_debug("Opening device %s", device_node);

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
	self->cache_dir = g_strndup(device_node, colon - device_node);

	if (parent_class->open_device)
	{
		parent_class->open_device(dself, device_name, device_type, self->cache_dir);
	}
}

static DeviceStatusFlags
dvdrw_device_read_label(Device *dself)
{
	DvdRwDevice *self = DVDRW_DEVICE(dself);
	VfsDevice *vself = VFS_DEVICE(dself);
	DeviceStatusFlags status;
	struct stat dir_status;

	g_debug("Reading label from media at %s", self->mount_point);

	if (device_in_error(dself)) return DEVICE_STATUS_DEVICE_ERROR;
	if (!check_readable(self)) return DEVICE_STATUS_DEVICE_ERROR;

	status = mount_disc(self);
	if (status != DEVICE_STATUS_SUCCESS)
	{
		return status;
	}

	if ((stat(self->data_dir, &dir_status) < 0) && (errno == ENOENT))
	{
		/* No data directory, consider the DVD unlabelled */
		g_debug("Media contains no data directory and therefore no label");
		unmount_disc(self);

		return DEVICE_STATUS_VOLUME_UNLABELED;
	}

	status = vfs_device_read_label_dir(vself, self->data_dir);

	unmount_disc(self);

	return status;
}

static gboolean
dvdrw_device_start(Device *dself, DeviceAccessMode mode, char *label, char *timestamp)
{
	DvdRwDevice *self = DVDRW_DEVICE(dself);
	VfsDevice *vself = VFS_DEVICE(dself);
	DeviceClass *parent_class = DEVICE_CLASS(g_type_class_peek_parent(DVDRW_DEVICE_GET_CLASS(dself)));

	g_debug("Start DVDRW device");

	if (device_in_error(dself)) return FALSE;
	if (!check_access_mode(self, mode)) return FALSE;

	dself->access_mode = mode;

	if (mode == ACCESS_READ)
	{
		if (mount_disc(self) != DEVICE_STATUS_SUCCESS)
		{
			return FALSE;
		}

		return vfs_device_start_dir(vself, self->data_dir, mode, label, timestamp);
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
dvdrw_device_start_file(Device *dself, dumpfile_t * ji)
{
	VfsDevice *vself = VFS_DEVICE(dself);
	DvdRwDevice *self = DVDRW_DEVICE(dself);
	DeviceClass *parent_class = DEVICE_CLASS(g_type_class_peek_parent(DVDRW_DEVICE_GET_CLASS(dself)));

	if (dself->access_mode == ACCESS_READ)
	{
		return vfs_device_start_file_dir(vself, self->data_dir, ji);
	}
	else
	{
		return parent_class->start_file(dself, ji);
	}

	return FALSE;
}

static dumpfile_t *
dvdrw_device_seek_file(Device * dself, guint requested_file)
{
	VfsDevice *vself = VFS_DEVICE(dself);
	DvdRwDevice *self = DVDRW_DEVICE(dself);
	DeviceClass *parent_class = DEVICE_CLASS(g_type_class_peek_parent(DVDRW_DEVICE_GET_CLASS(dself)));

	if (dself->access_mode == ACCESS_READ)
	{
		return vfs_device_seek_file_dir(vself, self->data_dir, requested_file);
	}
	else
	{
		return parent_class->seek_file(dself, requested_file);
	}

	return NULL;
}

static gboolean
dvdrw_device_erase(Device * dself)
{
/*
	VfsDevice *vself = VFS_DEVICE(dself);
	DvdRwDevice *self = DVDRW_DEVICE(dself);
 */
	DeviceClass *parent_class = DEVICE_CLASS(g_type_class_peek_parent(DVDRW_DEVICE_GET_CLASS(dself)));

/* Not valid for DVD-RW?
	if (dself->access_mode == ACCESS_READ)
	{
		return vfs_device_erase_dir(vself, self->data_dir);
	}
	else
	{
 */
		return parent_class->erase(dself);
/*
	}
 */

	return FALSE;
}

static gboolean
dvdrw_device_finish(Device *dself)
{
	DvdRwDevice *self = DVDRW_DEVICE(dself);
	VfsDevice *vself = VFS_DEVICE(dself);
	gboolean result;
	DeviceClass *parent_class = DEVICE_CLASS(g_type_class_peek_parent(DVDRW_DEVICE_GET_CLASS(dself)));
	DeviceAccessMode mode;

	g_debug("Finish device");

	/* Save access mode before parent class messes with it */
	mode = dself->access_mode;

	if (device_in_error(dself))
	{
		if (mode == ACCESS_READ)
		{
			/* Still need to do this, don't care if it works or not */
			unmount_disc(self);
		}

		return FALSE;
	}

	result = parent_class->finish(dself);

	if (mode == ACCESS_READ)
	{
		unmount_disc(self);
	}

	if (! result)
	{
		return FALSE;
	}

	if (mode == ACCESS_WRITE)
	{
		result = burn_disc(self);

		if (result && !self->keep_cache)
		{
			delete_vfs_files(vself, self->cache_dir);
		}

		return result;
	}

	return TRUE;
}

static gboolean
burn_disc(DvdRwDevice *self)
{
	gint status;

	char *burn_argv[] = {NULL, "-use-the-force-luke",
		"-Z", self->dvdrw_device,
		"-J", "-R", "-pad", "-quiet",
		self->cache_dir, NULL};

	if (self->growisofs_command == NULL)
	{
		burn_argv[0] = "growisofs";
	}
	else
	{
		burn_argv[0] = self->growisofs_command;
	}

	g_debug("Burning media in %s", self->dvdrw_device);
	if (execute_command(self, burn_argv, &status) != DEVICE_STATUS_SUCCESS)
	{
		return FALSE;
	}
	g_debug("Burn completed successfully");

	return TRUE;
}

static void
dvdrw_device_finalize(GObject *gself)
{
	DvdRwDevice *self = DVDRW_DEVICE(gself);
	GObjectClass *parent_class = G_OBJECT_CLASS(g_type_class_peek_parent(DVDRW_DEVICE_GET_CLASS(gself)));

	if (parent_class->finalize)
	{
		parent_class->finalize(gself);
	}

	amfree(self->dvdrw_device);
	amfree(self->cache_dir);
	amfree(self->mount_point);
	amfree(self->data_dir);
	amfree(self->growisofs_command);
	amfree(self->mount_command);
	amfree(self->umount_command);
}

static gboolean
check_access_mode(DvdRwDevice *self, DeviceAccessMode mode)
{
	Device *dself = DEVICE(self);

	if (mode == ACCESS_READ)
	{
		return check_readable(self);
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
check_readable(DvdRwDevice *self)
{
	Device *dself = DEVICE(self);
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
mount_disc(DvdRwDevice *self)
{
	gchar *mount_argv[] = { NULL, self->mount_point, NULL };
	gint status;

	if (self->mount_command == NULL)
	{
		mount_argv[0] = "mount";
	}
	else
	{
		mount_argv[0] = self->mount_command;
	}

	g_debug("Mounting media at %s", self->mount_point);
	return execute_command(self, mount_argv, &status);
}

static void
unmount_disc(DvdRwDevice *self)
{
	gchar *unmount_argv[] = { NULL, self->mount_point, NULL };

	if (self->umount_command == NULL)
	{
		unmount_argv[0] = "umount";
	}
	else
	{
		unmount_argv[0] = self->umount_command;
	}

	g_debug("Unmounting DVD at %s", self->mount_point);
	execute_command(NULL, unmount_argv, NULL);
}

static DeviceStatusFlags
execute_command(DvdRwDevice *self, gchar **argv, gint *result)
{
	Device *dself = DEVICE(self);
	GError *error = NULL;
	gint errnum;

	g_spawn_sync(NULL, argv, NULL, G_SPAWN_STDOUT_TO_DEV_NULL | G_SPAWN_SEARCH_PATH,
		NULL, NULL, NULL, NULL, &errnum, &error);
	if (error || (errnum != 0))
	{
		gchar *error_message = vstrallocf(_("DVDRW device cannot execute '%s': %s (status %d)"),
			argv[0], error ? error->message : _("Unknown error"), errnum);

		if (dself != NULL)
		{
			device_set_error(dself, error_message, DEVICE_STATUS_DEVICE_ERROR);
		}

		if (error)
		{
			g_error_free(error);
		}

		if (result != NULL)
		{
			*result = errnum;
		}

		return DEVICE_STATUS_DEVICE_ERROR;
	}

	return DEVICE_STATUS_SUCCESS;
}
