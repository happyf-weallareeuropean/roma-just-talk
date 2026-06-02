#ifndef ROMA_MINIAUDIO_CAPTURE_H
#define ROMA_MINIAUDIO_CAPTURE_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef void (*roma_miniaudio_capture_callback)(
    const int16_t *samples,
    uint32_t sample_count,
    void *user_data
);

typedef struct roma_miniaudio_capture_device roma_miniaudio_capture_device;

int roma_miniaudio_capture_create(
    uint32_t sample_rate,
    uint32_t channel_count,
    roma_miniaudio_capture_callback callback,
    void *user_data,
    roma_miniaudio_capture_device **out_device
);

int roma_miniaudio_capture_start(roma_miniaudio_capture_device *device);
int roma_miniaudio_capture_stop(roma_miniaudio_capture_device *device);
void roma_miniaudio_capture_destroy(roma_miniaudio_capture_device *device);

#ifdef __cplusplus
}
#endif

#endif
