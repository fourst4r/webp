# webp
Dependency free WebP decoder in pure Haxe.

- [x] Lossy support
- [x] Lossless support
- [x] Animated support

## Usage

```haxe
import webp.WebPDecoder;
import webp.Tools;
import webp.Image.ImageData;

function main() {
    final input = sys.io.File.read("image.webp");
    final decoded = Tools.toArgb(WebPDecoder.decode(input));
    input.close();

    switch (decoded.data) {
    case Argb(pix, stride):
        trace('Decoded ${decoded.header.width}x${decoded.header.height} ARGB buffer (stride: $stride)');
        // `pix` now holds tightly-packed ARGB bytes you can write to a PNG, bitmap, etc.
    case Anim(frames):
        trace('Animated WebP with ${frames.length} frames');
        // Each frame.data is already converted to ARGB.
    case Yuv420(_, _, _, _, _, _):
        // This case won't occur because Tools.toArgb converts YUV to ARGB.
    }
}
```
