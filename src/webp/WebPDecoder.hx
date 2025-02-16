package webp;

import haxe.io.Bytes;
import haxe.io.Input;
import webp.vp8.Vp8Decoder;

class WebPDecoder {
    public static function decode(input:Input, configOnly:Bool = false) {
        var riffReader = new RiffReader(input);
        // if (riffReader.formType != WEBP) 
        //     throw "Invalid format";

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

            switch (chunk.chunkID) {
                case "ALPH":
                    if (!wantAlpha) throw "Invalid format";
                    wantAlpha = false;

                    // Read the Pre-processing | Filter | Compression byte.
                    final flags = chunk.chunkData.readByte();
                    alpha = readAlpha(chunk.chunkData, widthMinusOne, heightMinusOne, flags & 0x03);
                    alphaStride = widthMinusOne+1;
                    unfilterAlpha(alpha, alphaStride, (flags >> 2) & 0x03);

                case "VP8 ":
                    if (wantAlpha || chunk.chunkLen < 0) 
                        throw "Invalid format";

                    var vp8Decoder = new Vp8Decoder();
                    vp8Decoder.init(chunk.chunkData, chunk.chunkLen);
                    var frameHeader = vp8Decoder.decodeFrameHeader();

                    if (configOnly) {
                        throw "Unimplemented";
                        // return {
                        //     // colorModel: ColorModel.YCbCr,
                        //     width: frameHeader.width,
                        //     height: frameHeader.height
                        // };
                    }

                    var image = vp8Decoder.decodeFrame();
                    if (alpha != null) {
                        throw "Not implemented";
                        // return {
                        //     image: new NYCbCrAImage(image, alpha, alphaStride)
                        // };
                    }
                    return { image: image };

                case "VP8L":
                    // if (wantAlpha || alpha != null) 
                        throw "Invalid format";

                    // if (configOnly) {
                    //     return VP8LDecoder.decodeConfig(chunk.data);
                    // }
                    // return { image: VP8LDecoder.decode(chunk.data) };

                case "VP8X":
                    if (seenVP8X) 
                        throw "Invalid format";
                    seenVP8X = true;

                    if (chunk.chunkLen != 10) 
                        throw "Invalid format";

                    chunk.chunkData.readBytes(buf, 0, 10);

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
                default:
                    throw "Unimplemented chunk type: " + chunk.chunkID;
            }
        }
    }

    static function readAlpha(
        chunkData: Input,
        widthMinusOne: Int,
        heightMinusOne: Int,
        compression: Int
    ): Bytes {
        switch (compression) {
            case 0:
                var w = widthMinusOne + 1;
                var h = heightMinusOne + 1;
                var alpha = Bytes.alloc(w * h);
                try {
                    chunkData.readFullBytes(alpha, 0, w * h);
                } catch (e) {
                    throw ("Failed to read alpha values: " + e);
                }
                return alpha;

            case 1:
                // Validate dimensions
                if (widthMinusOne > 0x3fff || heightMinusOne > 0x3fff) {
                    throw ("Invalid format: dimensions too large");
                }

                // Create a synthesized VP8L header
                var header = Bytes.ofData([
                    0x2f, // VP8L magic number
                    widthMinusOne & 0xff,
                    (widthMinusOne >> 8) | ((heightMinusOne & 0x3f) << 6),
                    (heightMinusOne >> 2) & 0xff,
                    (heightMinusOne >> 10) & 0xff
                ]);

                // Combine header and chunk data
                var combined = Bytes.alloc(header.length + chunkData.length);
                combined.blit(0, header, 0, header.length);
                combined.blit(header.length, chunkData.readAll(), 0, chunkData.length);

                // Decode VP8L compressed alpha values
                var alphaImage = Vp8L.decode(combined); // Hypothetical library function
                if (alphaImage == null) {
                    throw "Failed to decode VP8L";
                }

                // Extract alpha values from the green channel of the image
                var pix = alphaImage.pix; // Assuming pix is an array of bytes (ARGB format)
                var alpha = Bytes.alloc(pix.length / 4);
                for (i in 0...alpha.length) {
                    alpha.set(i, pix[i * 4 + 1]); // Green channel
                }
                return alpha;

            default:
                throw ("Invalid format: unsupported compression type");
        }
    }

    // static function readAlpha(input:Input, width:Int, height:Int, method:Int):Bytes {
    //     // Implementation of alpha decoding
    //     throw "Not implemented";
    // }

    static function unfilterAlpha(alpha:Bytes, alphaStride:Int, filter:Int):Void {
        if (alpha.length == 0 || alphaStride == 0) {
            return;
        }
        
        switch (filter) {
            case 1: // Horizontal filter
                for (i in 1...alphaStride) {
                    alpha.set(i, alpha.get(i) + alpha.get(i - 1));
                }
                var i = alphaStride;
                while (i < alpha.length) {
                    // The first column is equivalent to the vertical filter.
                    alpha.set(i, alpha.get(i) + alpha.get(i - alphaStride));
                    
                    for (j in 1...alphaStride) {
                        alpha.set(i + j, alpha.get(i + j) + alpha.get(i + j - 1));
                    }
                    i += alphaStride;
                }
    
            case 2: // Vertical filter
                // The first row is equivalent to the horizontal filter.
                for (i in 1...alphaStride) {
                    alpha.set(i, alpha.get(i) + alpha.get(i - 1));
                }
                for (i in alphaStride...alpha.length) {
                    alpha.set(i, alpha.get(i) + alpha.get(i - alphaStride));
                }
    
            case 3: // Gradient filter
                // The first row is equivalent to the horizontal filter.
                for (i in 1...alphaStride) {
                    alpha.set(i, alpha.get(i) + alpha.get(i - 1));
                }

                var i = alphaStride;
                while (i < alpha.length) {
                    // The first column is equivalent to the vertical filter.
                    alpha.set(i, alpha.get(i) + alpha.get(i - alphaStride));
                    
                    // The interior is predicted on the three top/left pixels.
                    for (j in 1...alphaStride) {
                        var c = alpha.get(i + j - alphaStride - 1);
                        var b = alpha.get(i + j - alphaStride);
                        var a = alpha.get(i + j - 1);
                        var x = a + b - c;
                        x = x < 0 ? 0 : (x > 255 ? 255 : x);
                        alpha.set(i + j, alpha.get(i + j) + x);
                    }

                    i += alphaStride;
                }
        }
    }
}