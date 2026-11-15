#include "FFmpegFrameExtractor.h"

#include <libavformat/avformat.h>
#include <libavcodec/avcodec.h>
#include <libswscale/swscale.h>
#include <libavutil/imgutils.h>

MacPlayerFrameResult macplayer_extract_frame(const char *path, double timeSec, int maxWidth) {
    MacPlayerFrameResult result = { .pixels = NULL, .width = 0, .height = 0 };

    AVFormatContext *fmtCtx = NULL;
    AVCodecContext *codecCtx = NULL;
    struct SwsContext *swsCtx = NULL;
    AVFrame *frame = NULL;
    AVFrame *rgbaFrame = NULL;
    AVPacket *pkt = NULL;
    uint8_t *rgbaBuf = NULL;

    // Open input
    if (avformat_open_input(&fmtCtx, path, NULL, NULL) < 0)
        goto cleanup;
    if (avformat_find_stream_info(fmtCtx, NULL) < 0)
        goto cleanup;

    // Find best video stream
    int videoIdx = av_find_best_stream(fmtCtx, AVMEDIA_TYPE_VIDEO, -1, -1, NULL, 0);
    if (videoIdx < 0)
        goto cleanup;

    AVStream *stream = fmtCtx->streams[videoIdx];
    const AVCodec *codec = avcodec_find_decoder(stream->codecpar->codec_id);
    if (!codec)
        goto cleanup;

    codecCtx = avcodec_alloc_context3(codec);
    if (!codecCtx)
        goto cleanup;
    if (avcodec_parameters_to_context(codecCtx, stream->codecpar) < 0)
        goto cleanup;
    if (avcodec_open2(codecCtx, codec, NULL) < 0)
        goto cleanup;

    // Seek
    int64_t ts = (int64_t)(timeSec * AV_TIME_BASE);
    av_seek_frame(fmtCtx, -1, ts, AVSEEK_FLAG_BACKWARD);
    avcodec_flush_buffers(codecCtx);

    // Decode one frame
    frame = av_frame_alloc();
    pkt = av_packet_alloc();
    if (!frame || !pkt)
        goto cleanup;

    int gotFrame = 0;
    while (av_read_frame(fmtCtx, pkt) >= 0) {
        if (pkt->stream_index != videoIdx) {
            av_packet_unref(pkt);
            continue;
        }
        if (avcodec_send_packet(codecCtx, pkt) < 0) {
            av_packet_unref(pkt);
            continue;
        }
        av_packet_unref(pkt);

        if (avcodec_receive_frame(codecCtx, frame) == 0) {
            gotFrame = 1;
            break;
        }
    }

    // Flush decoder if we haven't got a frame yet
    if (!gotFrame) {
        avcodec_send_packet(codecCtx, NULL);
        if (avcodec_receive_frame(codecCtx, frame) != 0)
            goto cleanup;
    }

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

    // Set up scaler to RGBA
    swsCtx = sws_getContext(srcW, srcH, frame->format,
                            dstW, dstH, AV_PIX_FMT_RGBA,
                            SWS_BILINEAR, NULL, NULL, NULL);
    if (!swsCtx)
        goto cleanup;

    rgbaFrame = av_frame_alloc();
    if (!rgbaFrame)
        goto cleanup;

    int bufSize = av_image_get_buffer_size(AV_PIX_FMT_RGBA, dstW, dstH, 1);
    if (bufSize < 0)
        goto cleanup;

    rgbaBuf = (uint8_t *)av_malloc(bufSize);
    if (!rgbaBuf)
        goto cleanup;

    av_image_fill_arrays(rgbaFrame->data, rgbaFrame->linesize,
                         rgbaBuf, AV_PIX_FMT_RGBA, dstW, dstH, 1);

    sws_scale(swsCtx, (const uint8_t *const *)frame->data, frame->linesize,
              0, srcH, rgbaFrame->data, rgbaFrame->linesize);

    // Copy to caller-owned buffer
    result.width = dstW;
    result.height = dstH;
    result.pixels = (uint8_t *)malloc(bufSize);
    if (result.pixels) {
        // Copy row by row in case linesize != dstW*4
        int rowBytes = dstW * 4;
        for (int y = 0; y < dstH; y++) {
            memcpy(result.pixels + y * rowBytes,
                   rgbaFrame->data[0] + y * rgbaFrame->linesize[0],
                   rowBytes);
        }
    }

cleanup:
    if (rgbaBuf)    av_free(rgbaBuf);
    if (rgbaFrame)  av_frame_free(&rgbaFrame);
    if (frame)      av_frame_free(&frame);
    if (pkt)        av_packet_free(&pkt);
    if (swsCtx)     sws_freeContext(swsCtx);
    if (codecCtx)   avcodec_free_context(&codecCtx);
    if (fmtCtx)     avformat_close_input(&fmtCtx);

    return result;
}
