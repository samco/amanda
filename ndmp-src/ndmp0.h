/*
 * Please do not edit this file.
 * It was generated using rpcgen.
 */

#ifndef _NDMP0_H_RPCGEN
#define _NDMP0_H_RPCGEN

#include <rpc/rpc.h>


#ifdef __cplusplus
extern "C" {
#endif

#define NDMPPORT 10000

enum ndmp0_error {
	NDMP0_NO_ERR = 0,
	NDMP0_NOT_SUPPORTED_ERR = 1,
	NDMP0_DEVICE_BUSY_ERR = 2,
	NDMP0_DEVICE_OPENED_ERR = 3,
	NDMP0_NOT_AUTHORIZED_ERR = 4,
	NDMP0_PERMISSION_ERR = 5,
	NDMP0_DEV_NOT_OPEN_ERR = 6,
	NDMP0_IO_ERR = 7,
	NDMP0_TIMEOUT_ERR = 8,
	NDMP0_ILLEGAL_ARGS_ERR = 9,
	NDMP0_NO_TAPE_LOADED_ERR = 10,
	NDMP0_WRITE_PROTECT_ERR = 11,
	NDMP0_EOF_ERR = 12,
	NDMP0_EOM_ERR = 13,
	NDMP0_FILE_NOT_FOUND_ERR = 14,
	NDMP0_BAD_FILE_ERR = 15,
	NDMP0_NO_DEVICE_ERR = 16,
	NDMP0_NO_BUS_ERR = 17,
	NDMP0_XDR_DECODE_ERR = 18,
	NDMP0_ILLEGAL_STATE_ERR = 19,
	NDMP0_UNDEFINED_ERR = 20,
	NDMP0_XDR_ENCODE_ERR = 21,
	NDMP0_NO_MEM_ERR = 22,
};
typedef enum ndmp0_error ndmp0_error;

enum ndmp0_header_message_type {
	NDMP0_MESSAGE_REQUEST = 0,
	NDMP0_MESSAGE_REPLY = 1,
};
typedef enum ndmp0_header_message_type ndmp0_header_message_type;

enum ndmp0_message {
	NDMP0_CONNECT_OPEN = 0x900,
	NDMP0_CONNECT_CLOSE = 0x902,
	NDMP0_NOTIFY_CONNECTED = 0x502,
};
typedef enum ndmp0_message ndmp0_message;

struct ndmp0_header {
	u_long sequence;
	u_long time_stamp;
	ndmp0_header_message_type message_type;
	ndmp0_message message;
	u_long reply_sequence;
	ndmp0_error error;
};
typedef struct ndmp0_header ndmp0_header;

struct ndmp0_connect_open_request {
	u_short protocol_version;
};
typedef struct ndmp0_connect_open_request ndmp0_connect_open_request;

struct ndmp0_connect_open_reply {
	ndmp0_error error;
};
typedef struct ndmp0_connect_open_reply ndmp0_connect_open_reply;

enum ndmp0_connect_reason {
	NDMP0_CONNECTED = 0,
	NDMP0_SHUTDOWN = 1,
	NDMP0_REFUSED = 2,
};
typedef enum ndmp0_connect_reason ndmp0_connect_reason;

struct ndmp0_notify_connected_request {
	ndmp0_connect_reason reason;
	u_short protocol_version;
	char *text_reason;
};
typedef struct ndmp0_notify_connected_request ndmp0_notify_connected_request;

/* the xdr functions */

#if defined(__STDC__) || defined(__cplusplus)
extern  bool_t xdr_ndmp0_error (XDR *, ndmp0_error*);
extern  bool_t xdr_ndmp0_header_message_type (XDR *, ndmp0_header_message_type*);
extern  bool_t xdr_ndmp0_message (XDR *, ndmp0_message*);
extern  bool_t xdr_ndmp0_header (XDR *, ndmp0_header*);
extern  bool_t xdr_ndmp0_connect_open_request (XDR *, ndmp0_connect_open_request*);
extern  bool_t xdr_ndmp0_connect_open_reply (XDR *, ndmp0_connect_open_reply*);
extern  bool_t xdr_ndmp0_connect_reason (XDR *, ndmp0_connect_reason*);
extern  bool_t xdr_ndmp0_notify_connected_request (XDR *, ndmp0_notify_connected_request*);

#else /* K&R C */
extern bool_t xdr_ndmp0_error ();
extern bool_t xdr_ndmp0_header_message_type ();
extern bool_t xdr_ndmp0_message ();
extern bool_t xdr_ndmp0_header ();
extern bool_t xdr_ndmp0_connect_open_request ();
extern bool_t xdr_ndmp0_connect_open_reply ();
extern bool_t xdr_ndmp0_connect_reason ();
extern bool_t xdr_ndmp0_notify_connected_request ();

#endif /* K&R C */

#ifdef __cplusplus
}
#endif

#endif /* !_NDMP0_H_RPCGEN */
