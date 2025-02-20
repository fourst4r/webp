package webp;

import haxe.io.Bytes;
import webp.FrameHeader;

enum Image {
    /** YCbCr is the format of lossy WebP, with optional (non-premultiplied) alpha. **/
    YCbCrA(header:FrameHeader, y:Bytes, ystride:Int, cb:Bytes, cr:Bytes, cstride:Int, ?a:Bytes, ?astride:Int);
    /** Argb (non-premultiplied) is the format of lossless WebP. **/
    Argb(header:FrameHeader, pix:Bytes);
}