package webp;

import haxe.io.BytesInput;
import webp.types.ConcatInput;
import webp.vp8l.Vp8LDecoder;
import haxe.io.Bytes;
import haxe.io.Input;
import webp.vp8.Vp8Decoder;

class WebPDecoder {
    public static function decode(input:Input, configOnly:Bool = false):Image {
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
                    var header = vp8Decoder.decodeFrameHeader();

                    var img = vp8Decoder.decodeFrame();
                    
                    return {
                        header: header,
                        data: YCbCrA(img.Y, img.YStride, img.Cb, img.Cr, img.CStride, alpha, alphaStride)
                    };

                case "VP8L":
                    if (wantAlpha || alpha != null) 
                        throw "Invalid format";
                    
                    final img = Vp8LDecoder.decode(chunk.chunkData);
                    final pix = img.pix;
                    
                    // TODO: remove the code that originally changes this to RGBA (it's stored as ARGB internally by vp8 lossless format)
                    var i = 0;
                    while (i < pix.length) {
                        // Extract RGBA channels
                        final r = pix.get(i);
                        final g = pix.get(i + 1);
                        final b = pix.get(i + 2);
                        final a = pix.get(i + 3);
                
                        // Reorder to ARGB
                        pix.set(i, a);
                        pix.set(i + 1, r);
                        pix.set(i + 2, g);
                        pix.set(i + 3, b);

                        i += 4;
                    }

                    return { 
                        header: null,
                        data: Argb(img.pix, img.stride)
                    };

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

                case "ANIM":
                    final d = chunk.chunkData;
                    final bgColor = d.readInt32();
                    final loopCount = d.readUInt16();

                case "ANMF":
                    final d = chunk.chunkData;
                    final x = d.readUInt24();
                    final y = d.readUInt24();
                    final widthMinusOne = d.readUInt24();
                    final heightMinusOne = d.readUInt24();
                    final frameDurationMs = d.readUInt24();
                    final flags = d.readByte();
                    final disposal = flags & 1;
                    final blending = flags & 2;

                default:
                    throw "Unimplemented chunk type: " + chunk.chunkID;
            }
        }
    }

    static function readAlpha(chunkData:Input, widthMinusOne:Int, heightMinusOne:Int, compression:Int):Bytes {
        switch (compression) {
        case 0:
            final w = widthMinusOne + 1;
            final h = heightMinusOne + 1;
            final alpha = Bytes.alloc(w * h);
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
            var header = Bytes.alloc(5);
            header.set(0, 0x2f); // VP8L magic number
            header.set(1, widthMinusOne & 0xff);
            header.set(2, (widthMinusOne >> 8) | ((heightMinusOne & 0x3f) << 6));
            header.set(3, (heightMinusOne >> 2) & 0xff);
            header.set(4, (heightMinusOne >> 10) & 0xff);

            // Combine header and chunk data
            final concatInput = new ConcatInput(new BytesInput(header), chunkData);

            // Decode VP8L compressed alpha values
            var alphaImage = Vp8LDecoder.decode(concatInput);

            // Extract alpha values from the green channel of the image
            var pix = alphaImage.pix; // Assuming pix is an array of bytes (ARGB format)
            var alpha = Bytes.alloc(Std.int(pix.length / 4));
            for (i in 0...alpha.length) {
                alpha.set(i, pix.get(i * 4 + 1)); // Green channel
            }
            return alpha;

        default:
            throw ("Invalid format: unsupported compression type");
        }
    }

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
                    final c = alpha.get(i + j - alphaStride - 1);
                    final b = alpha.get(i + j - alphaStride);
                    final a = alpha.get(i + j - 1);
                    var x = a + b - c;
                    x = x < 0 ? 0 : (x > 255 ? 255 : x);
                    alpha.set(i + j, alpha.get(i + j) + x);
                }

                i += alphaStride;
            }
        }
    }
}