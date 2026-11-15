#ifndef FFmpegFrameExtractor_h
#define FFmpegFrameExtractor_h

#include <stdint.h>

/// Result of a frame extraction — caller must free `pixels` via `free()`.
typedef struct {
    uint8_t *pixels;   // RGBA pixel data (NULL on failure)
    int width;
    int height;
} MacPlayerFrameResult;

/// One video file held open for frame extraction (demuxer + decoder).
/// Opening a container can be expensive, so open once and extract many frames.
/// Not thread-safe: use an extractor from one thread at a time.
typedef struct MacPlayerFrameExtractor MacPlayerFrameExtractor;

/// Open `path` (UTF-8) for frame extraction.
/// @return NULL if the file can't be opened or has no decodable video stream.
MacPlayerFrameExtractor *macplayer_frame_extractor_open(const char *path);

/// Extract the keyframe at or before `timeSec` as RGBA pixels.
/// @param timeSec   Seek target in seconds.
/// @param maxWidth  Desired width (height scales proportionally). Pass 0 for original size.
/// @return Pixel data in `MacPlayerFrameResult`. Caller must `free(result.pixels)`.
MacPlayerFrameResult macplayer_frame_extractor_extract(MacPlayerFrameExtractor *extractor,
                                                       double timeSec, int maxWidth);

/// Close the file and free the extractor. Accepts NULL.
void macplayer_frame_extractor_close(MacPlayerFrameExtractor *extractor);

#endif /* FFmpegFrameExtractor_h */
