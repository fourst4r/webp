import utest.Assert;
import utest.Async;
import haxe.io.Bytes;
import webp.Image;
import webp.Image.ImageData;

class Visual extends utest.Test {
  
    public function setup() {
    }

    function testAll() {
        final imgs = [/*"1", "2", "3", "4", "5", "1ll", "2ll", "3ll", "4ll", "5ll", "1a",*/ "2a"];
        for (n in imgs) 
            convert(n);
        Assert.pass();
    }

    function convert(imgName:String) {
        trace("convert "+imgName);
        final fi = sys.io.File.read("test/"+imgName+".webp");
        var img = webp.WebPDecoder.decode(fi);
        fi.close();
        img = webp.Tools.toArgb(img);
        switch (img.data) {
        case Argb(_, _), Yuv420(_, _, _, _, _, _):
            final argb = toArgbBytes(img.data, img.header.width, img.header.height);
            final fo = sys.io.File.write("test/actual/"+imgName+".png");
            final pngData = format.png.Tools.build32ARGB(img.header.width, img.header.height, argb);
            new format.png.Writer(fo).write(pngData);
            fo.close();
        case Anim(frames):
            for (idx in 0...frames.length) {
                final frame = frames[idx];
                final argb = toArgbBytes(frame.data, frame.header.width, frame.header.height);
                final fo = sys.io.File.write('test/actual/${imgName}_${idx}.png');
                final pngData = format.png.Tools.build32ARGB(frame.header.width, frame.header.height, argb);
                new format.png.Writer(fo).write(pngData);
                fo.close();
            }
        }
    }
}

function toArgbBytes(data:ImageData, width:Int, height:Int):Bytes {
    return switch data {
    case Argb(pix, stride):
        if (stride == width * 4) {
            pix;
        } else {
            // Normalize stride to tightly packed ARGB
            final out = Bytes.alloc(width * height * 4);
            for (row in 0...height) {
                out.blit(row * width * 4, pix, row * stride, width * 4);
            }
            out;
        }
    case Yuv420(y, ystride, cb, cr, cstride, a):
        final argb = Bytes.alloc(width * height * 4);
        final alphaStride = width;
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

                final idx = (row * width + col) * 4;
                argb.set(idx, a?.get(row * alphaStride + col) ?? 0xFF);
                argb.set(idx + 1, Std.int(R));
                argb.set(idx + 2, Std.int(G));
                argb.set(idx + 3, Std.int(B));
            }
        }
        argb;
    case Anim(_):
        throw "Nested Anim not supported";
    };
}
