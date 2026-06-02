#include "roma_miniaudio_capture.h"

#include "miniaudio.h"

#include <stdlib.h>

struct roma_miniaudio_capture_device {
    ma_device device;
    roma_miniaudio_capture_callback callback;
    void *user_data;
    uint32_t channel_count;
};

static void roma_miniaudio_capture_data_callback(
    ma_device *device,
    void *output,
    const void *input,
    ma_uint32 frame_count
) {
    (void)output;

    if (device == NULL || input == NULL || frame_count == 0) {
        return;
    }

    roma_miniaudio_capture_device *capture =
        (roma_miniaudio_capture_device *)device->pUserData;
    if (capture == NULL || capture->callback == NULL || capture->channel_count == 0) {
        return;
    }

    capture->callback(
        (const int16_t *)input,
        frame_count * capture->channel_count,
        capture->user_data
    );
}

int roma_miniaudio_capture_create(
    uint32_t sample_rate,
    uint32_t channel_count,
    roma_miniaudio_capture_callback callback,
    void *user_data,
    roma_miniaudio_capture_device **out_device
) {
    if (sample_rate == 0 || channel_count == 0 || callback == NULL || out_device == NULL) {
        return MA_INVALID_ARGS;
    }

    roma_miniaudio_capture_device *capture =
        (roma_miniaudio_capture_device *)calloc(1, sizeof(*capture));
    if (capture == NULL) {
        return MA_OUT_OF_MEMORY;
    }

    capture->callback = callback;
    capture->user_data = user_data;
    capture->channel_count = channel_count;

    ma_device_config config = ma_device_config_init(ma_device_type_capture);
    config.capture.format = ma_format_s16;
    config.capture.channels = channel_count;
    config.sampleRate = sample_rate;
    config.dataCallback = roma_miniaudio_capture_data_callback;
    config.pUserData = capture;

    ma_result result = ma_device_init(NULL, &config, &capture->device);
    if (result != MA_SUCCESS) {
        free(capture);
        return result;
    }

    *out_device = capture;
    return MA_SUCCESS;
}

int roma_miniaudio_capture_start(roma_miniaudio_capture_device *device) {
    if (device == NULL) {
        return MA_INVALID_ARGS;
    }
    return ma_device_start(&device->device);
}

int roma_miniaudio_capture_stop(roma_miniaudio_capture_device *device) {
    if (device == NULL) {
        return MA_INVALID_ARGS;
    }
    return ma_device_stop(&device->device);
}

void roma_miniaudio_capture_destroy(roma_miniaudio_capture_device *device) {
    if (device == NULL) {
        return;
    }

    ma_device_uninit(&device->device);
    free(device);
}
