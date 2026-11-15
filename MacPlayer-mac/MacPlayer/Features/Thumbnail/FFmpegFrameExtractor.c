#include "FFmpegFrameExtractor.h"

#include "../../Core/Engine/MP4LayoutProbe.h"

#include <stdlib.h>

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>

enum {
    // How many video packets decodeKeyframeAt() reads past the seek point looking for a
    // keyframe. Only a container without a keyframe index gets anywhere near it.
    kMaxPacketsToKeyframe = 1000,
    // How many times in a row decodeKeyframeAt() may come up empty where plain decoding
    // gets a frame before the stream is taken to need plain decoding throughout.
    kMaxKeyframeMisses = 3,
};

typedef enum { kFrameNone, kFrameDecoded, kFrameUnchanged } FrameOutcome;

struct MacPlayerFrameExtractor {
    AVFormatContext *fmtCtx;
    AVCodecContext *codecCtx;
    struct SwsContext *swsCtx;   // cached across frames; rebuilt if the frame geometry changes
    AVFrame *frame;
    AVPacket *pkt;
    int videoIdx;
    int keyframeMisses;          // see kMaxKeyframeMisses
};

MacPlayerFrameExtractor *macplayer_frame_extractor_open(const char *path) {
    MacPlayerFrameExtractor *ex = calloc(1, sizeof(*ex));
    if (!ex)
        return NULL;

    ex->fmtCtx = avformat_alloc_context();
    if (!ex->fmtCtx)
        goto fail;
    // Split-mdat MP4: moov already indexes every sample, so don't walk the rest of the
    // file's top-level boxes on open (see MP4LayoutProbe.h).
    if (macplayer_mp4_has_split_mdat(path))
        ex->fmtCtx->flags |= AVFMT_FLAG_IGNIDX;

    // On failure avformat_open_input frees the context and sets it to NULL.
    if (avformat_open_input(&ex->fmtCtx, path, NULL, NULL) < 0)
        goto fail;
    if (avformat_find_stream_info(ex->fmtCtx, NULL) < 0)
        goto fail;

    ex->videoIdx = av_find_best_stream(ex->fmtCtx, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (ex->videoIdx < 0)
        goto fail;

    // Only video packets are wanted: the demuxer can pass over every other stream's.
    for (unsigned i = 0; i < ex->fmtCtx->nb_streams; i++) {
        if ((int)i != ex->videoIdx)
            ex->fmtCtx->streams[i]->discard = AVDISCARD_ALL;
    }

    AVStream *stream = ex->fmtCtx->streams[ex->videoIdx];
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec)
        goto fail;

    ex->codecCtx = avcodec_alloc_context3(codec);
    if (!ex->codecCtx)
        goto fail;
    if (avcodec_parameters_to_context(ex->codecCtx, stream->codecpar) < 0)
        goto fail;
    // A thumbnail is a single frame, so the threads that help are the ones that share out
    // the work within a frame. FFmpeg's default is one thread, which makes a 4K or 8K
    // keyframe several times slower than it needs to be.
    ex->codecCtx->thread_count = 0;     // one per core
    ex->codecCtx->thread_type = FF_THREAD_SLICE;
    if (avcodec_open2(ex->codecCtx, codec, NULL) < 0)
        goto fail;

    ex->frame = av_frame_alloc();
    ex->pkt = av_packet_alloc();
    if (!ex->frame || !ex->pkt)
        goto fail;

    return ex;

fail:
    macplayer_frame_extractor_close(ex);
    return NULL;
}

void macplayer_frame_extractor_close(MacPlayerFrameExtractor *ex) {
    if (!ex)
        return;
    if (ex->frame)      av_frame_free(&ex->frame);
    if (ex->pkt)        av_packet_free(&ex->pkt);
    if (ex->swsCtx)     sws_freeContext(ex->swsCtx);
    if (ex->codecCtx)   avcodec_free_context(&ex->codecCtx);
    if (ex->fmtCtx)     avformat_close_input(&ex->fmtCtx);
    free(ex);
}

static void seekTo(MacPlayerFrameExtractor *ex, double timeSec) {
    int64_t ts = (int64_t)(timeSec * AV_TIME_BASE);
    av_seek_frame(ex->fmtCtx, -1, ts, AVSEEK_FLAG_BACKWARD);
    // Also takes the decoder out of the drained state a previous call left it in.
    avcodec_flush_buffers(ex->codecCtx);
}

/// Seeks to `timeSec` and decodes only the keyframe found there into `ex->frame`.
///
/// A keyframe decodes on its own, so its packet is the only one read and decoded. Sending
/// EOF right after it makes the decoder hand the frame over at once; fed normally, a decoder
/// that reorders frames holds it back until several more have been decoded.
///
/// `*keyframe` receives the keyframe's byte offset (-1 if unknown). If that is
/// `knownKeyframe`, nothing is decoded and the outcome is kFrameUnchanged.
static FrameOutcome decodeKeyframeAt(MacPlayerFrameExtractor *ex, double timeSec,
                                     int64_t knownKeyframe, int64_t *keyframe) {
    seekTo(ex, timeSec);

    // An indexed container lands on the keyframe. One without an index lands mid-GOP, and
    // the packets up to the next keyframe can't be decoded into anything worth showing.
    int skipped = 0;
    while (skipped < kMaxPacketsToKeyframe && av_read_frame(ex->fmtCtx, ex->pkt) >= 0) {
        if (ex->pkt->stream_index != ex->videoIdx) {
            av_packet_unref(ex->pkt);
            continue;
        }
        if (!(ex->pkt->flags & AV_PKT_FLAG_KEY)) {
            av_packet_unref(ex->pkt);
            skipped++;
            continue;
        }

        *keyframe = ex->pkt->pos;
        if (*keyframe >= 0 && *keyframe == knownKeyframe) {
            av_packet_unref(ex->pkt);
            return kFrameUnchanged;
        }
        int sent = avcodec_send_packet(ex->codecCtx, ex->pkt);
        av_packet_unref(ex->pkt);
        if (sent < 0)
            return kFrameNone;
        avcodec_send_packet(ex->codecCtx, NULL);
        return avcodec_receive_frame(ex->codecCtx, ex->frame) == 0 ? kFrameDecoded : kFrameNone;
    }
    return kFrameNone;
}

/// Seeks to `timeSec` and decodes forward into `ex->frame` until the decoder produces a
/// frame, however many packets that takes. For the streams decodeKeyframeAt() can't serve:
/// ones whose keyframes aren't marked, or aren't complete pictures by themselves.
static int decodeFirstFrameAt(MacPlayerFrameExtractor *ex, double timeSec) {
    seekTo(ex, timeSec);

    while (av_read_frame(ex->fmtCtx, ex->pkt) >= 0) {
        if (ex->pkt->stream_index != ex->videoIdx) {
            av_packet_unref(ex->pkt);
            continue;
        }
        int sent = avcodec_send_packet(ex->codecCtx, ex->pkt);
        av_packet_unref(ex->pkt);
        if (sent < 0)
            continue;
        if (avcodec_receive_frame(ex->codecCtx, ex->frame) == 0)
            return 1;
    }

    // Ran out of packets: drain whatever the decoder is still holding.
    avcodec_send_packet(ex->codecCtx, NULL);
    return avcodec_receive_frame(ex->codecCtx, ex->frame) == 0;
}

MacPlayerFrameResult macplayer_frame_extractor_extract(MacPlayerFrameExtractor *ex,
                                                       double timeSec, int maxWidth,
                                                       int64_t knownKeyframe) {
    MacPlayerFrameResult result = { .pixels = NULL, .width = 0, .height = 0,
                                    .keyframe = -1, .unchanged = 0 };
    if (!ex)
        return result;

    FrameOutcome outcome = kFrameNone;
    if (ex->keyframeMisses < kMaxKeyframeMisses) {
        outcome = decodeKeyframeAt(ex, timeSec, knownKeyframe, &result.keyframe);
        if (outcome == kFrameUnchanged) {
            result.unchanged = 1;
            return result;
        }
    }
    if (outcome == kFrameDecoded) {
        ex->keyframeMisses = 0;
    } else {
        result.keyframe = -1;
        if (!decodeFirstFrameAt(ex, timeSec))
            return result;
        if (ex->keyframeMisses < kMaxKeyframeMisses)
            ex->keyframeMisses++;
    }

    AVFrame *frame = ex->frame;

    // Calculate output dimensions
    int srcW = frame->width;
    int srcH = frame->height;
    int dstW, dstH;
    if (maxWidth > 0 && srcW > maxWidth) {
        dstW = maxWidth;
        dstH = srcH * maxWidth / srcW;
        // Ensure even dimensions for sws_scale
        dstH = (dstH + 1) & ~1;
    } else {
        dstW = srcW;
        dstH = srcH;
    }

    ex->swsCtx = sws_getCachedContext(ex->swsCtx, srcW, srcH, frame->format,
                                      dstW, dstH, AV_PIX_FMT_RGBA,
                                      SWS_BILINEAR, NULL, NULL, NULL);
    if (ex->swsCtx && dstW > 0 && dstH > 0) {
        // Scale straight into the caller-owned buffer: tightly packed RGBA rows.
        int rowBytes = dstW * 4;
        uint8_t *pixels = (uint8_t *)malloc((size_t)rowBytes * dstH);
        if (pixels) {
            uint8_t *dstData[4] = { pixels, NULL, NULL, NULL };
            int dstLinesize[4] = { rowBytes, 0, 0, 0 };
            sws_scale(ex->swsCtx, (const uint8_t *const *)frame->data, frame->linesize,
                      0, srcH, dstData, dstLinesize);
            result.pixels = pixels;
            result.width = dstW;
            result.height = dstH;
        }
    }
    // Without pixels there is nothing for a later call to be "unchanged" from.
    if (!result.pixels)
        result.keyframe = -1;

    av_frame_unref(frame);
    return result;
}
