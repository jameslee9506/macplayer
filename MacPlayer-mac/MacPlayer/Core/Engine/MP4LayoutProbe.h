#ifndef MP4LayoutProbe_h
#define MP4LayoutProbe_h

/// Returns 1 when `path` is a non-fragmented MP4 whose media data is split across several
/// top-level boxes: `ftyp`, then `moov` without `mvex`, then an `mdat` that stops short of
/// the end of the file. Web downloaders that append one `mdat` per segment write this layout.
///
/// FFmpeg's mov demuxer walks every remaining top-level box of such a file before it reports
/// the file as open, although `moov` already indexes every sample. Callers use this to make
/// it skip that walk (AVFMT_FLAG_IGNIDX / mpv `index=recreate`); it then reads the later
/// boxes only when playback or a seek reaches them.
///
/// Fragmented files must not get that treatment — their index lives in the boxes being
/// skipped — so anything with `mvex` or `moof` returns 0, as does any file that can't be read.
/// Costs a few small reads at the start of the file.
int macplayer_mp4_has_split_mdat(const char *path);

#endif /* MP4LayoutProbe_h */
