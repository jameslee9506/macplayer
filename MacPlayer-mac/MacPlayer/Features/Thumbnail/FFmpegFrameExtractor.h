#ifndef FFmpegFrameExtractor_h
#define FFmpegFrameExtractor_h

#include <stdint.h>

/// Result of a frame extraction — caller must free `pixels` via `free()`.
typedef struct {
    uint8_t *pixels;   // RGBA pixel data (NULL on failure)
    int width;
    int height;
} MacPlayerFrameResult;

/// Extract a single video frame as RGBA pixels.
/// @param path    File path (UTF-8).
/// @param timeSec Seek target in seconds.
/// @param maxWidth  Desired width (height scales proportionally). Pass 0 for original size.
/// @return Pixel data in `MacPlayerFrameResult`. Caller must `free(result.pixels)`.
MacPlayerFrameResult macplayer_extract_frame(const char *path, double timeSec, int maxWidth);

#endif /* FFmpegFrameExtractor_h */
