package webp;

import haxe.io.Bytes;
import haxe.io.Input;

class WebPDecoder {
    public static function decode(input:Input, configOnly:Bool = false) {
        var riffReader = new RiffReader(input);
        if (riffReader.formType != WEBP) 
            throw "Invalid format";

        var alpha:Bytes = null;
        var alphaStride:Int = 0;
        var wantAlpha:Bool = false;
        var seenVP8X:Bool = false;
        var widthMinusOne:Int = 0;
        var heightMinusOne:Int = 0;
        var buf = Bytes.alloc(10);

        while (true) {
            var chunk = riffReader.next();
            if (chunk == null) 
                throw "Invalid format";

            switch (chunk.id) {
                case "ALPH":
                    if (!wantAlpha) 
                        throw "Invalid format";
                    wantAlpha = false;

                    chunk.data.readBytes(buf, 0, 1);
                    var preprocessing = buf.get(0);
                    alpha = readAlpha(chunk.data, widthMinusOne, heightMinusOne, preprocessing & 0x03);
                    alphaStride = calculateAlphaStride(widthMinusOne);
                    unfilterAlpha(alpha, alphaStride, (preprocessing >> 2) & 0x03);

                case "VP8 ":
                    if (wantAlpha || chunk.length < 0) 
                        throw "Invalid format";

                    var vp8Decoder = new VP8Decoder(chunk.data);
                    var frameHeader = vp8Decoder.decodeFrameHeader();

                    if (configOnly) {
                        return {
                            colorModel: ColorModel.YCbCr,
                            width: frameHeader.width,
                            height: frameHeader.height
                        };
                    }

                    var image = vp8Decoder.decodeFrame();
                    if (alpha != null) {
                        return {
                            image: new NYCbCrAImage(image, alpha, alphaStride)
                        };
                    }
                    return { image: image };

                case "VP8L":
                    // if (wantAlpha || alpha != null) 
                        throw "Invalid format";

                    if (configOnly) {
                        return VP8LDecoder.decodeConfig(chunk.data);
                    }
                    return { image: VP8LDecoder.decode(chunk.data) };

                case "VP8X":
                    if (seenVP8X) 
                        throw "Invalid format";
                    seenVP8X = true;

                    if (chunk.length != 10) 
                        throw "Invalid format";

                    chunk.data.readBytes(buf, 0, 10);

                    var flags = buf.get(0);
                    var hasAlpha = (flags & 0x10) != 0;
                    wantAlpha = hasAlpha;

                    widthMinusOne = buf.get(4) | (buf.get(5) << 8) | (buf.get(6) << 16);
                    heightMinusOne = buf.get(7) | (buf.get(8) << 8) | (buf.get(9) << 16);

                    if (configOnly) {
                        throw "unimplemented";
                        // return {
                        //     colorModel: hasAlpha ? ColorModel.NYCbCrA : ColorModel.YCbCr,
                        //     width: widthMinusOne + 1,
                        //     height: heightMinusOne + 1
                        // };
                    }
            }
        }
    }

    static function readAlpha(input:Input, width:Int, height:Int, method:Int):Bytes {
        // Implementation of alpha decoding
        throw "Not implemented";
    }

    static function unfilterAlpha(alpha:Bytes, stride:Int, method:Int) {
        // Implementation of alpha filtering
        throw "Not implemented";
    }
}