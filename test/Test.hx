package;

import format.jpg.Writer;
import haxe.io.Bytes;
import webp.YccImage;
import sys.io.File;
import webp.WebPDecoder;

class TrackedInput extends haxe.io.Input {
    public var i:haxe.io.Input;

    public function new(i) this.i = i;

    override function read(nbytes:Int):Bytes {
        final b = i.read(nbytes);
        trace('read ${b.length} of $nbytes');
        return b;
    }

    override function readAll(?bufsize:Int):Bytes {
        final b = i.readAll(bufsize);
        trace('read ${b.length}');
        return b;
    }

    override function readByte():Int {
        trace('read 1');
        return i.readByte();
    }

    override function readBytes(s:Bytes, pos:Int, len:Int):Int {
        final n = i.readBytes(s, pos, len);
        trace('read ${n} of $len');
        return n;
    }

    override function readFullBytes(s:Bytes, pos:Int, len:Int) {
        trace('reading $len');
        super.readFullBytes(s, pos, len);
    }
}

function main() {
    trace(Sys.getCwd());
    final fi = File.read("test/a.webp");
    // final img = WebPDecoder.decode(new TrackedInput(fi)).image;
    final img = WebPDecoder.decode(new TrackedInput(fi));
    fi.close();

    final img = toARGB(img);
        // toARGB(img);
    // var rgba = yccToRgba(img);

    final fo = File.write("a.png");
    
    final pngData = format.png.Tools.build32ARGB(img.header.width, img.header.height, img.argb);
    new format.png.Writer(fo).write(pngData);
    // var jpg = new format.jpg.Writer(fo);
    // jpg.write({
    //     width: img.header.width,
    //     height: img.header.height,
    //     pixels: argb,
    //     quality: 100,
    // });
    fo.close();
    trace("ok");
}

function toARGB(img:webp.Image) {
    switch img {
    case Argb(header, pix): 
        return { header: header, argb: pix };
    case YCbCrA(header, y, ystride, cb, cr, cstride, a, astride):
        final width = header.width;
        final height = header.height;
        final argb = Bytes.alloc(width * height * 4);

        for (row in 0...height) {
            for (col in 0...width) {
                final yIndex = row * ystride + col;
                final cbCrIndex = (row >> 1) * cstride + (col >> 1);

                final Y = y.get(yIndex) & 0xFF;
                final Cb = (cb.get(cbCrIndex) & 0xFF) - 128;
                final Cr = (cr.get(cbCrIndex) & 0xFF) - 128;

                var R = Y + (1.402 * Cr);
                var G = Y - (0.344136 * Cb) - (0.714136 * Cr);
                var B = Y + (1.772 * Cb);

                R = Math.round(Math.max(0, Math.min(255, R)));
                G = Math.round(Math.max(0, Math.min(255, G)));
                B = Math.round(Math.max(0, Math.min(255, B)));

                final rgbaIndex = (row * width + col) * 4;
                argb.set(rgbaIndex, a?.get(row*astride+col) ?? 0xFF);
                argb.set(rgbaIndex+1, Std.int(R));
                argb.set(rgbaIndex+2, Std.int(G));
                argb.set(rgbaIndex+3, Std.int(B));
            }
        }
        return { header: header, argb: argb };
    };
}

function yccToRgb(ycc:YccImage):Bytes {
    final width = ycc.rect.maxX - ycc.rect.minX;
    final height = ycc.rect.maxY - ycc.rect.minY;
    final rgba = Bytes.alloc(width * height * 3);

    for (y in 0...height) {
        for (x in 0...width) {
            // Get Y, Cb, and Cr values
            final yIndex = y * ycc.YStride + x;
            final cbCrIndex = (y >> 1) * ycc.CStride + (x >> 1);

            final Y = ycc.Y.get(yIndex) & 0xFF;
            final Cb = (ycc.Cb.get(cbCrIndex) & 0xFF) - 128;
            final Cr = (ycc.Cr.get(cbCrIndex) & 0xFF) - 128;

            // Convert to RGB using ITU-R BT.601 conversion
            var R = Y + (1.402 * Cr);
            var G = Y - (0.344136 * Cb) - (0.714136 * Cr);
            var B = Y + (1.772 * Cb);

            // Clamp values to [0, 255]
            R = Math.round(Math.max(0, Math.min(255, R)));
            G = Math.round(Math.max(0, Math.min(255, G)));
            B = Math.round(Math.max(0, Math.min(255, B)));

            // Store as RGBA (assume full alpha)
            final rgbaIndex = (y * width + x) * 3;
            rgba.set(rgbaIndex, Std.int(R));
            rgba.set(rgbaIndex+1, Std.int(G));
            rgba.set(rgbaIndex+2, Std.int(B));
        }
    }

    return rgba;
}
function yccToRgba(ycc:YccImage):Bytes {
    final width = ycc.rect.maxX - ycc.rect.minX;
    final height = ycc.rect.maxY - ycc.rect.minY;
    final rgba = Bytes.alloc(width * height * 4);

    for (y in 0...height) {
        for (x in 0...width) {
            // Get Y, Cb, and Cr values
            final yIndex = y * ycc.YStride + x;
            final cbCrIndex = (y >> 1) * ycc.CStride + (x >> 1);

            final Y = ycc.Y.get(yIndex) & 0xFF;
            final Cb = (ycc.Cb.get(cbCrIndex) & 0xFF) - 128;
            final Cr = (ycc.Cr.get(cbCrIndex) & 0xFF) - 128;

            // Convert to RGB using ITU-R BT.601 conversion
            var R = Y + (1.402 * Cr);
            var G = Y - (0.344136 * Cb) - (0.714136 * Cr);
            var B = Y + (1.772 * Cb);

            // Clamp values to [0, 255]
            R = Math.round(Math.max(0, Math.min(255, R)));
            G = Math.round(Math.max(0, Math.min(255, G)));
            B = Math.round(Math.max(0, Math.min(255, B)));

            // Store as RGBA (assume full alpha)
            final rgbaIndex = (y * width + x) * 4;
            rgba.set(rgbaIndex, 255); // Alpha channel
            rgba.set(rgbaIndex+1, Std.int(R));
            rgba.set(rgbaIndex+2, Std.int(G));
            rgba.set(rgbaIndex+3, Std.int(B));
        }
    }

    return rgba;
}