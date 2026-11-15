#include "FFmpegFrameExtractor.h"

#include "../../Core/Engine/MP4LayoutProbe.h"

#include <stdlib.h>

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>

struct MacPlayerFrameExtractor {
    AVFormatContext *fmtCtx;
    AVCodecContext *codecCtx;
    struct SwsContext *swsCtx;   // cached across frames; rebuilt if the frame geometry changes
    AVFrame *frame;
    AVPacket *pkt;
    int videoIdx;
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

    AVStream *stream = ex->fmtCtx->streams[ex->videoIdx];
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec)
        goto fail;

    ex->codecCtx = avcodec_alloc_context3(codec);
    if (!ex->codecCtx)
        goto fail;
    if (avcodec_parameters_to_context(ex->codecCtx, stream->codecpar) < 0)
        goto fail;
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

/// Seek to the keyframe at or before `timeSec` and decode it into `ex->frame`.
static int decodeFrameAt(MacPlayerFrameExtractor *ex, double timeSec) {
    int64_t ts = (int64_t)(timeSec * AV_TIME_BASE);
    av_seek_frame(ex->fmtCtx, -1, ts, AVSEEK_FLAG_BACKWARD);
    // Also takes the decoder out of the drained state a previous call may have left it in.
    avcodec_flush_buffers(ex->codecCtx);

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
                                                       double timeSec, int maxWidth) {
    MacPlayerFrameResult result = { .pixels = NULL, .width = 0, .height = 0 };
    if (!ex || !decodeFrameAt(ex, timeSec))
        return result;

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

    av_frame_unref(frame);
    return result;
}
