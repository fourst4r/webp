package webp;

import haxe.ds.List;
import webp.FrameHeader;
import haxe.io.BytesInput;
import webp.types.ConcatInput;
import webp.vp8l.Vp8LDecoder;
import haxe.io.Bytes;
import haxe.io.Eof;
import haxe.io.Input;
import webp.Image.AnimFrameHeader;
import webp.Image.ImageData;
import webp.vp8.Vp8Decoder;

enum Chunk {
    CAlph(data:Bytes);
    CVp8(data:Bytes);
    CVp8l(data:Bytes);
    CVp8x(data:Bytes);
    CAnim(data:Bytes);
    CAnmf(data:Bytes);
    CUnknown(id:String, data:Bytes);
}

class WebPDecoder {
    var _i:Input;
    var _totalLen:Int;
    var _isLossy:Bool = false;
    var hasAlpha:Bool = false;
    var widthMinusOne:Int = 0;
    var heightMinusOne:Int = 0;
    var loopCount:Int = 0;
    var backgroundColor:Int = 0;
    var frames:Array<{header:AnimFrameHeader, data:ImageData}> = [];

    public function new(i:Input) {
        this._i = i;
    }

    function readRiffHeader() {
        if (_i.readString(4) != "RIFF")
            throw "Missing RIFF chunk header";
        final chunkLen = _i.readInt32();
        if (chunkLen < 4)
            throw "Short chunk data";
        final idk = _i.readInt32();
        _totalLen = chunkLen - 4;
    }

    function readRiffChunk() {
        if (_totalLen <= 0)
            return null;
		final id = _i.readString(4);
		final dataLen = _i.readInt32();
		final data = _i.read(dataLen);
        // Chunks are padded to even size; consume the pad byte when present.
        if ((dataLen & 1) == 1) {
            _i.readByte();
            _totalLen -= 1;
        }
        _totalLen -= dataLen + 8;
        final bi = new BytesInput(data);
		return switch id {
		case "ALPH":
            CAlph(data);
		case "VP8 ":
            CVp8(data);
		case "VP8L":
            CVp8l(data);
		case "VP8X":
            CVp8x(data);
        case "ANIM":
            CAnim(data);
        case "ANMF":
            CAnmf(data);
		default: 
            CUnknown(id, data);
		}
	}

    function readAlph(i:Input) {
        // Read the Pre-processing | Filter | Compression byte.
        final flags = i.readByte();
        final alpha = readAlpha(i, widthMinusOne, heightMinusOne, flags & 0x03);
        final alphaStride = widthMinusOne+1;
        unfilterAlpha(alpha, alphaStride, (flags >> 2) & 0x03);
        return {
            alpha: alpha,
            alphaStride: alphaStride
        };
    }

    function readVp8(i:BytesInput) {
        final vp8 = new Vp8Decoder(i);
        final header = vp8.decodeFrameHeader();
        final img = vp8.decodeFrame();
        _isLossy = true;
        return {
            header: header,
            y: img.Y,
            ystride: img.YStride,
            cb: img.Cb,
            cr: img.Cr,
            cstride: img.CStride,
        };
    }

    function readVp8l(i:Input) {
        final img = Vp8LDecoder.decode(i);
        final pix = img.pix;
        // TODO: refactor the code that originally changes this to RGBA (it's stored as ARGB internally by vp8 lossless format). It was done that way due to a limitation in the Go version.
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
            argb: img.pix,
            stride: img.stride,
            width: img.width,
            height: img.height,
        };
    }

    function readVp8x(i:Input) {
        final buf = i.read(10);

        var flags = buf.get(0);
        hasAlpha = (flags & 0x10) != 0;
        
        widthMinusOne = buf.get(4) | (buf.get(5) << 8) | (buf.get(6) << 16);
        heightMinusOne = buf.get(7) | (buf.get(8) << 8) | (buf.get(9) << 16);
    }

    function readAnim(i:Input) {
        backgroundColor = i.readInt32();
        final l0 = i.readByte();
        final l1 = i.readByte();
        loopCount = l0 | (l1 << 8);
    }

    function readAnmf(data:Bytes) {
        final i = new BytesInput(data);
        var remaining = data.length;

        final frameX = readUint24(i);
        final frameY = readUint24(i);
        final frameWidthMinusOne = readUint24(i);
        final frameHeightMinusOne = readUint24(i);
        final duration = readUint24(i);
        final flags = i.readByte();
        remaining -= 16; // consumed header bytes

        final dispose = (flags & 0x01) != 0;
        final blend = (flags & 0x02) == 0;

        final frameHeader:AnimFrameHeader = {
            x: frameX,
            y: frameY,
            width: frameWidthMinusOne + 1,
            height: frameHeightMinusOne + 1,
            duration: duration,
            blend: blend,
            dispose: dispose
        };

        final frameData = readFrameData(i, frameWidthMinusOne, frameHeightMinusOne);
        frames.push({ header: frameHeader, data: frameData });
    }

    public static function decode(i:Input):Image {
        final webp = new WebPDecoder(i);
        var lossy = null;
        var lossless = null;
        var alpha:Bytes = null;
        for (chunk in webp.decodeChunks(i)) {
            switch (chunk) {
            case CVp8x(data):
                webp.readVp8x(new BytesInput(data));
            case CAlph(data):
                final a = webp.readAlph(new BytesInput(data));
                alpha = a.alpha;
            case CVp8(data):
                lossy = webp.readVp8(new BytesInput(data));
            case CVp8l(data):
                lossless = webp.readVp8l(new BytesInput(data));
            case CAnim(data):
                webp.readAnim(new BytesInput(data));
            case CAnmf(data):
                webp.readAnmf(data);
            case CUnknown(id, data):
                // ignore
            }
        }
        if (webp.frames.length > 0) {
            final header = {
                keyFrame: true,
                versionNumber: 0,
                showFrame: true,
                firstPartitionLen: 0,
                width: webp.widthMinusOne + 1,
                height: webp.heightMinusOne + 1,
                xScale: 0,
                yScale: 0
            };
            return {
                header: header,
                data: Anim(webp.frames)
            };
        }
        if (lossless != null) {
            final header = lossless.header ?? {
                keyFrame: true,
                versionNumber: 0,
                showFrame: true,
                firstPartitionLen: 0,
                width: lossless.width,
                height: lossless.height,
                xScale: 0,
                yScale: 0
            };
            return {
                header: header,
                data: Argb(lossless.argb, lossless.stride)
            };
        }

        if (lossy != null) {
            return {
                header: lossy.header,
                data: Yuv420(lossy.y, lossy.ystride, lossy.cb, lossy.cr, lossy.cstride, alpha)
            };
        }

        throw "Invalid format: no VP8/VP8L chunk found";
    }

    function decodeChunks(i:Input):Array<Chunk> {
        readRiffHeader();
        final chunks = [];        
        while (true) {
            final chunk = readRiffChunk();
            if (chunk == null)
                break;
            chunks.push(chunk);
        }
        return chunks;
    }

    function readFrameData(i:BytesInput, frameWidthMinusOne:Int, frameHeightMinusOne:Int):ImageData {
        var alpha:Bytes = null;
        var lossy = null;
        var lossless = null;

        while (i.position < i.length) {
            if (i.length - i.position < 8)
                break; // not enough for another subchunk header
            var id:String;
            try {
                id = i.readString(4);
            } catch (_:Eof) {
                break;
            }
            final dataLen = i.readInt32();
            if (dataLen < 0 || dataLen > (i.length - i.position))
                throw "Invalid ANMF subchunk length";
            final data = i.read(dataLen);
            if ((dataLen & 1) == 1 && i.position < i.length)
                i.readByte(); // padded to even size

            switch id {
            case "ALPH":
                final aInput = new BytesInput(data);
                final flags = aInput.readByte();
                try {
                    final a = readAlpha(aInput, frameWidthMinusOne, frameHeightMinusOne, flags & 0x03);
                    unfilterAlpha(a, frameWidthMinusOne + 1, (flags >> 2) & 0x03);
                    alpha = a;
                } catch (_:Dynamic) {
                    // If alpha decoding fails, fall back to opaque frame.
                    alpha = null;
                }
            case "VP8 ":
                lossy = readVp8(new BytesInput(data));
            case "VP8L":
                lossless = readVp8l(new BytesInput(data));
            default:
                // ignore other sub-chunks inside the frame
            }
        }

        if (lossless != null) {
            return Argb(lossless.argb, lossless.stride);
        }

        if (lossy != null) {
            return Yuv420(lossy.y, lossy.ystride, lossy.cb, lossy.cr, lossy.cstride, alpha);
        }

        throw "Invalid format: no VP8/VP8L chunk found in ANMF";
    }

    inline static function readUint24(i:Input):Int {
        final b0 = i.readByte();
        final b1 = i.readByte();
        final b2 = i.readByte();
        return b0 | (b1 << 8) | (b2 << 16);
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
