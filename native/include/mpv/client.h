/* Minimal mpv client.h stub for embedding */
#ifndef MPV_CLIENT_H_
#define MPV_CLIENT_H_

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct mpv_handle mpv_handle;
typedef struct mpv_event mpv_event;

/* Create a new mpv instance */
mpv_handle *mpv_create(void);

/* Initialize the mpv instance */
int mpv_initialize(mpv_handle *ctx);

/* Load a file/stream */
int mpv_command(mpv_handle *ctx, const char **args);

/* Wait for events with timeout (ms). Returns event or NULL if timeout. */
mpv_event *mpv_wait_event(mpv_handle *ctx, double timeout);

/* Get a property value */
int mpv_get_property(mpv_handle *ctx, const char *name, int format, void *data);

/* Set a property value */
int mpv_set_property(mpv_handle *ctx, const char *name, int format, void *data);

/* Destroy mpv instance */
void mpv_terminate_destroy(mpv_handle *ctx);

/* Format constants */
#define MPV_FORMAT_NONE 0
#define MPV_FORMAT_STRING 1
#define MPV_FORMAT_OSD_STRING 2
#define MPV_FORMAT_FLAG 3
#define MPV_FORMAT_INT64 4
#define MPV_FORMAT_DOUBLE 5
#define MPV_FORMAT_NODE 6
#define MPV_FORMAT_NODE_ARRAY 7
#define MPV_FORMAT_NODE_MAP 8
#define MPV_FORMAT_BYTE_ARRAY 9

#ifdef __cplusplus
}
#endif

#endif
