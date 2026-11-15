#ifndef FFmpegFrameExtractor_h
#define FFmpegFrameExtractor_h

#include <stdint.h>

/// Result of a frame extraction — caller must free `pixels` via `free()`.
typedef struct {
    uint8_t *pixels;    // RGBA pixel data (NULL on failure, and when `unchanged` is set)
    int width;
    int height;
    int64_t keyframe;   // byte offset of the extracted keyframe in the file; -1 if unknown
    int unchanged;      // 1 if that keyframe is `knownKeyframe`: nothing was decoded
} MacPlayerFrameResult;

/// One video file held open for frame extraction (demuxer + decoder).
/// Opening a container can be expensive, so open once and extract many frames.
/// Not thread-safe: use an extractor from one thread at a time.
typedef struct MacPlayerFrameExtractor MacPlayerFrameExtractor;

/// Open `path` (UTF-8) for frame extraction.
/// @return NULL if the file can't be opened or has no decodable video stream.
MacPlayerFrameExtractor *macplayer_frame_extractor_open(const char *path);

/// Extract the keyframe at or before `timeSec` as RGBA pixels. In a container without a
/// keyframe index (MPEG-TS) it is the first keyframe after the seek point instead.
/// @param timeSec        Seek target in seconds.
/// @param maxWidth       Desired width (height scales proportionally). Pass 0 for original size.
/// @param knownKeyframe  `keyframe` of a result the caller still holds, or -1. Times a few
///                       seconds apart often share a keyframe: when the seek lands on this one
///                       again, the result has `unchanged` set and the decode is skipped.
/// @return Pixel data in `MacPlayerFrameResult`. Caller must `free(result.pixels)`.
MacPlayerFrameResult macplayer_frame_extractor_extract(MacPlayerFrameExtractor *extractor,
                                                       double timeSec, int maxWidth,
                                                       int64_t knownKeyframe);

/// Close the file and free the extractor. Accepts NULL.
void macplayer_frame_extractor_close(MacPlayerFrameExtractor *extractor);

#endif /* FFmpegFrameExtractor_h */
