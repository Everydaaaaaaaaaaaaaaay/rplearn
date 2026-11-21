"""Pixel coverage for full-screen photographic activity scenes."""

REFERENCE_WIDTH = 1206
REFERENCE_HEIGHT = 2622
MAX_DISPLAY_SCALE = 1.2
PROCESSING = 'EXIF orientation; RGB; maximum 8192x3200px without upscaling; JPEG quality 92, 4:4:4; no generated edits'


def display_scale(width, height):
    return max(REFERENCE_WIDTH / width, REFERENCE_HEIGHT / height)


def has_screen_resolution(width, height):
    return width > 0 and height > 0 and display_scale(width, height) <= MAX_DISPLAY_SCALE
