package webp;

import haxe.io.Bytes;
import webp.FrameHeader;

typedef Image = {
    header:FrameHeader,
    data:ImageData,
}

enum ImageData {
    /** YCbCr is the format of lossy WebP, with optional (non-premultiplied) alpha. **/
    YCbCrA(y:Bytes, ystride:Int, cb:Bytes, cr:Bytes, cstride:Int, ?a:Bytes, ?astride:Int);
    /** Argb (non-premultiplied) is the format of lossless WebP. **/
    Argb(pix:Bytes, stride:Int);
}