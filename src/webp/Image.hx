package webp;

import haxe.io.Bytes;

typedef Image = {
    header:FrameHeader,
    data:ImageData,
}

typedef FrameHeader = {
    keyFrame:Bool,
    versionNumber:Int,
    showFrame:Bool,
    firstPartitionLen:Int,
    width:Int,
    height:Int,
    xScale:Int,
    yScale:Int,
}

typedef AnimFrameHeader = {
    x:Int,
    y:Int,
    width:Int,
    height:Int,
    duration:Int,
    blend:Bool,
    dispose:Bool,
}

typedef AnimImage = {
    header:AnimFrameHeader,
    data:ImageData
}

enum ImageData {
    /** 
        YUV 4:2:0 (lossy WebP), with optional non-premultiplied alpha.
        - U and V planes are half-resolution.
        - Alpha (if present) is full-resolution, with stride of `ystride`.
    **/
    Yuv420(y:Bytes, ystride:Int, u:Bytes, v:Bytes, uvstride:Int, ?a:Bytes);
    /** Argb (non-premultiplied) is the format of lossless WebP. **/
    Argb(pix:Bytes, stride:Int);
    Anim(frames:Array<AnimImage>);
}
