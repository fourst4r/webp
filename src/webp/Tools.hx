package webp;

import haxe.io.Bytes;

class Tools {
    public static function toArgb(img:webp.Image) {
        switch img.data {
        case Argb(pix, stride): 
            return img;
        case YCbCrA(y, ystride, cb, cr, cstride, a, astride):
            final width = img.header.width;
            final height = img.header.height;
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
            
            return {
                header: Reflect.copy(img.header),
                data: Argb(argb, img.header.width*4)
            };
        };
    }
}