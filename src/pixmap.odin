package startrace

import "base:intrinsics"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:os"
import "core:os/os2"

Vector3u8 :: [3]u8

PixMapMode :: enum {
    HumanReadable = 3,
    Binary        = 6,
}

PixMap :: struct($E: typeid) where intrinsics.type_is_integer(E) && intrinsics.type_is_unsigned(E) {
    mode:        PixMapMode,
    width:       i32,
    height:      i32,
    element_max: i64,
    image:       [][3]E,
}

new_pixmap :: proc(
    mode: PixMapMode,
    width: i32,
    height: i32,
    $E: typeid,
) -> PixMap(E) where intrinsics.type_is_integer(E) &&
    intrinsics.type_is_unsigned(E) {
    element_max: i64 = 1
    for _ in 0 ..< size_of(E) * 8 {
        element_max *= 2
    }
    element_max -= 1
    return PixMap(E) {
        mode = mode,
        width = width,
        height = height,
        element_max = element_max,
        image = make([][3]E, width * height),
    }
}

pixmap_write :: proc(out: os.Handle, pixmap: ^PixMap($E)) -> (bytes_written: int) {
    // header
    bytes_written = fmt.fprintf(out, "P%d %d %d %d", int(pixmap.mode), pixmap.width, pixmap.height, pixmap.element_max)

    // image data
    for pixel in pixmap.image {
        bytes_written += fmt.fprintf(out, " %d %d %d", pixel.r, pixel.g, pixel.b)
    }

    return
}
