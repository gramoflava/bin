#!/usr/bin/env python3
import argparse
import subprocess
import os
import sys
import logging
import tempfile
import json

# Global settings
LOG_FILE = "/tmp/automat.log"
ENABLE_LOGGING = False
USE_GPU = False
TRASH_MODE = False
DEBUG_MODE = False
SUFFIX = "-re"
DEFAULT_CODEC = "hevc"
DEFAULT_FORMAT = "mov"

logger = logging.getLogger("automat")

def setup_logging():
    logger.setLevel(logging.DEBUG if DEBUG_MODE else logging.INFO)
    fmt = logging.Formatter("[%(asctime)s] [%(levelname)s] %(message)s",
                             datefmt="%Y-%m-%d %H:%M:%S")
    if ENABLE_LOGGING:
        fh = logging.FileHandler(LOG_FILE)
        fh.setFormatter(fmt)
        fh.setLevel(logging.DEBUG if DEBUG_MODE else logging.INFO)
        logger.addHandler(fh)
    ch = logging.StreamHandler(sys.stdout)
    ch.setFormatter(logging.Formatter("%(message)s"))
    ch.setLevel(logging.DEBUG if DEBUG_MODE else logging.INFO)
    logger.addHandler(ch)

def display_error(message):
    print(f"Error: {message}", file=sys.stderr)
    logger.error(message)

def display_info(message):
    print(message)
    logger.info(message)

def display_debug(message):
    if DEBUG_MODE:
        print(f"Debug: {message}")
    logger.debug(message)

def run_command(cmd):
    return subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

def is_video_file(path):
    if not os.path.isfile(path):
        return False
    res = run_command(["file", "--mime-type", "-b", path])
    return res.stdout.strip().startswith("video/")

def is_image_file(path):
    if not os.path.isfile(path):
        return False
    res = run_command(["file", "--mime-type", "-b", path])
    return res.stdout.strip().startswith("image/")

def move_to_trash(path):
    if not os.path.isfile(path):
        display_error(f"File not found for trashing: {path}")
        return
    script = f'''
    tell application "Finder"
        move POSIX file "{os.path.abspath(path)}" to trash
    end tell
    '''
    res = run_command(["osascript", "-e", script])
    if res.returncode == 0:
        logger.info(f"Moved to trash: {path}")
        display_debug(f"Moved to trash: {path}")
    else:
        display_error(f"Trash failed: {res.stderr.strip()}")

def get_video_info(source):
    display_debug(f"Getting info for: {source}")
    cmd = ["ffprobe", "-v", "quiet", "-print_format", "json",
           "-show_format", "-show_streams", source]
    res = run_command(cmd)
    if res.returncode != 0:
        display_error(f"ffprobe error on {source}")
        return 0,0,0.0,0,0
    info = json.loads(res.stdout)
    stream = next((s for s in info.get("streams",[]) if s.get("codec_type")=="video"), {})
    width = stream.get("width", 0) or 0
    height = stream.get("height",0) or 0
    duration = float(info.get("format",{}).get("duration",0.0)) or 0.0
    bitrate = int(info.get("format",{}).get("bit_rate",0) or 0)
    filesize = os.path.getsize(source)
    logger.info(f"Info: {width}x{height}, {duration}s, {bitrate}b/s, {filesize} bytes")
    return width, height, duration, bitrate, filesize

def calculate_optimal_bitrate(w, h, curr, size, dur):
    display_debug(f"Calc bitrate for {w}x{h}, curr={curr}, size={size}, dur={dur}")
    pix = w*h
    if pix >= 8294400:   base = 6_000_000
    elif pix > 2073600:  base = 4_000_000
    elif pix >  921600:  base = 2_500_000
    else:                base = 1_200_000
    chosen = min(curr or base, base)
    if dur > 0:
        actual = int(size * 8 / dur)
        targ = int(actual * 0.8)
        if 0 < targ < chosen:
            chosen = targ
    chosen = max(chosen, 100_000)
    chosen = round(chosen/100_000)*100_000
    logger.info(f"Optimal bitrate: {chosen}")
    return chosen

def build_ffmpeg_command(src, codec, fmt, bitrate):
    display_debug(f"Build ffmpeg cmd: codec={codec}, fmt={fmt}, br={bitrate}")
    vf = "scale=trunc(iw/2)*2:trunc(ih/2)*2"
    kb = bitrate//1024
    if codec=="h264":
        vopt = f"-c:v h264_videotoolbox -b:v {kb}k -tag:v avc1"
    elif codec=="hevc":
        vopt = f"-c:v hevc_videotoolbox -b:v {kb}k -tag:v hvc1"
    elif codec=="av1":
        vopt = "-c:v libaom-av1 -crf 30 -b:v 0 -strict experimental"
    else:
        display_error(f"Invalid codec: {codec}")
        sys.exit(1)
    if fmt=="mkv":    vopt += " -f matroska"
    elif fmt=="webm":
        if codec!="av1":
            vopt = "-c:v libvpx-vp9 -crf 30 -b:v 0 -f webm"
        else:
            vopt += " -f webm"
    out = f"{os.path.splitext(src)[0]}{SUFFIX}.{fmt}"
    cmd = [ "ffmpeg", "-hwaccel", "videotoolbox", "-i", src
        ] + vopt.split() + [
            "-vf", vf,
            "-c:a", "aac", "-b:a", "128k",
            "-pix_fmt", "yuv420p",
            "-y", out
            ]
    return cmd, out

def process_video(src, codec, fmt):
    w,h,dur,br,sz = get_video_info(src)
    new_br = calculate_optimal_bitrate(w,h,br,sz,dur)
    cmd, out = build_ffmpeg_command(src, codec, fmt, new_br)
    logger.info("Running: " + " ".join(cmd))
    with tempfile.NamedTemporaryFile() as tmp:
        res = subprocess.run(cmd, stdout=tmp, stderr=tmp)
    if res.returncode!=0:
        display_error("ffmpeg failed")
        return False
    if not os.path.isfile(out) or os.path.getsize(out)==0:
        display_error(f"Output missing: {out}")
        return False
    orig_sz = os.path.getsize(src)
    new_sz  = os.path.getsize(out)
    red = (1-new_sz/orig_sz)*100 if orig_sz>0 else 0
    display_info(f"{orig_sz/1e6:.2f}→{new_sz/1e6:.2f} MB ({red:.1f}% reduction)")
    if TRASH_MODE:
        move_to_trash(src)
    return True

def process_image(src):
    out = f"{os.path.splitext(src)[0]}{SUFFIX}.heic"
    cmd = ["sips","-s","format","heic",src,"--out",out]
    logger.info("Running: " + " ".join(cmd))
    res = run_command(cmd)
    if res.returncode!=0:
        display_error("sips failed")
        return False
    if not os.path.isfile(out) or os.path.getsize(out)==0:
        display_error(f"Output missing: {out}")
        return False
    orig_sz = os.path.getsize(src)
    new_sz  = os.path.getsize(out)
    red = (1-new_sz/orig_sz)*100 if orig_sz>0 else 0
    display_info(f"{orig_sz/1e3:.2f}→{new_sz/1e3:.2f} KB ({red:.1f}% reduction)")
    if TRASH_MODE:
        move_to_trash(src)
    return True

def refine_recursive(directory, codec, fmt):
    display_info(f"Recursively refining: {directory}")
    files = []
    for root, _, names in os.walk(directory):
        for nm in names:
            if SUFFIX in nm: continue
            path = os.path.join(root, nm)
            if is_video_file(path) or is_image_file(path):
                files.append(path)
    total = len(files)
    display_info(f"Found {total} files")
    proc = fail = 0
    for idx, path in enumerate(files,1):
        kind = "video" if is_video_file(path) else "image"
        display_info(f"[{idx}/{total}] Processing {kind}: {path}")
        ok = process_video(path, codec, fmt) if kind=="video" else process_image(path)
        if ok:
            display_info(f"✓ {path}")
        else:
            fail += 1
            display_error(f"✗ {path}")
        proc += 1
    display_info(f"Done. Processed: {proc}, Failed: {fail}")

def main():
    global ENABLE_LOGGING, USE_GPU, TRASH_MODE, DEBUG_MODE
    p = argparse.ArgumentParser(description="Pythonized automat")
    p.add_argument("-v", action="store_true")
    p.add_argument("-c", default=DEFAULT_CODEC)
    p.add_argument("-g", action="store_true")
    p.add_argument("-f", default=DEFAULT_FORMAT)
    p.add_argument("-l", action="store_true")
    p.add_argument("-t", action="store_true")
    p.add_argument("-d", action="store_true")
    p.add_argument("operation", choices=["refine","amv","loop_audio","audiofy"])
    p.add_argument("source")
    p.add_argument("param", nargs="?")
    args = p.parse_args()

    ENABLE_LOGGING = args.l or args.v or args.d
    DEBUG_MODE    = args.d
    USE_GPU       = args.g
    TRASH_MODE    = args.t
    codec = args.c
    fmt   = args.f

    setup_logging()

    if args.operation=="refine" and os.path.isdir(args.source):
        refine_recursive(args.source, codec, fmt)
    else:
        if not os.path.exists(args.source):
            display_error(f"Not found: {args.source}")
            sys.exit(1)
        if is_video_file(args.source):
            process_video(args.source, codec, fmt)
        elif is_image_file(args.source):
            process_image(args.source)
        else:
            display_error(f"Unsupported type: {args.source}")
            sys.exit(1)

if __name__ == "__main__":
    main()