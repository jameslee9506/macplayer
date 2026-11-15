#include "MP4LayoutProbe.h"

#include <fcntl.h>
#include <stdint.h>
#include <sys/stat.h>
#include <unistd.h>

#define FOURCC(a, b, c, d) \
    (((uint32_t)(a) << 24) | ((uint32_t)(b) << 16) | ((uint32_t)(c) << 8) | (uint32_t)(d))

// Bounds on how many headers we read, so a file that only looks like MP4 costs little.
enum { kMaxBoxesBeforeMdat = 16, kMaxMoovChildren = 256 };

typedef struct {
    uint32_t type;
    int64_t size;      // whole box, header included
    int headerSize;
} Box;

static uint32_t be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}

static uint64_t be64(const uint8_t *p) {
    return ((uint64_t)be32(p) << 32) | be32(p + 4);
}

/// Reads the box header at `pos`. `limit` is the end of the enclosing container.
/// Returns 0 if there is no well-formed box there.
static int readBox(int fd, int64_t pos, int64_t limit, Box *box) {
    uint8_t header[16];
    if (limit - pos < 8)
        return 0;
    ssize_t n = pread(fd, header, sizeof(header), pos);
    if (n < 8)
        return 0;

    uint64_t size = be32(header);
    box->type = be32(header + 4);
    box->headerSize = 8;
    if (size == 1) {            // 64-bit size follows the type
        if (n < 16)
            return 0;
        size = be64(header + 8);
        box->headerSize = 16;
    } else if (size == 0) {     // box runs to the end of its container
        size = (uint64_t)(limit - pos);
    }
    if (size < (uint64_t)box->headerSize || size > (uint64_t)(limit - pos))
        return 0;
    box->size = (int64_t)size;
    return 1;
}

static int containerHasChild(int fd, int64_t start, int64_t end, uint32_t type) {
    Box box;
    int64_t pos = start;
    for (int i = 0; i < kMaxMoovChildren && readBox(fd, pos, end, &box); i++, pos += box.size) {
        if (box.type == type)
            return 1;
    }
    return 0;
}

int macplayer_mp4_has_split_mdat(const char *path) {
    int fd = open(path, O_RDONLY | O_CLOEXEC);
    if (fd < 0)
        return 0;

    int result = 0;
    struct stat st;
    if (fstat(fd, &st) != 0 || !S_ISREG(st.st_mode))
        goto done;
    int64_t fileSize = st.st_size;

    Box box;
    if (!readBox(fd, 0, fileSize, &box) || box.type != FOURCC('f', 't', 'y', 'p'))
        goto done;

    int sawMoov = 0;
    int64_t pos = box.size;
    for (int i = 0; i < kMaxBoxesBeforeMdat && readBox(fd, pos, fileSize, &box); i++, pos += box.size) {
        if (box.type == FOURCC('m', 'o', 'o', 'v')) {
            if (containerHasChild(fd, pos + box.headerSize, pos + box.size, FOURCC('m', 'v', 'e', 'x')))
                goto done;      // fragmented
            sawMoov = 1;
        } else if (box.type == FOURCC('m', 'o', 'o', 'f')) {
            goto done;          // fragmented
        } else if (box.type == FOURCC('m', 'd', 'a', 't')) {
            // With moov still to come, the demuxer has to walk on to find it anyway.
            result = sawMoov && pos + box.size < fileSize;
            goto done;
        }
    }

done:
    close(fd);
    return result;
}
