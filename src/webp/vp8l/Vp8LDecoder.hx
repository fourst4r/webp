package webp.vp8l;

import webp.vp8l.Transform;
import haxe.ds.Vector;
import haxe.io.Input;
import haxe.io.Bytes;
import webp.vp8l.HTree;

private final nLiteralCodes  = 256;
private final nLengthCodes   = 24;
private final nDistanceCodes = 40;

class Vp8LDecoder {
    public var r: Input;
    public var bits: Int = 0;
    public var nBits: Int = 0;

    final codeLengthCodeOrder = [
        17, 18, 0, 1, 2, 3, 4, 5, 16, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15,
    ];
    final repeatBits = [2, 3, 7];
    final repeatOffsets = [3, 3, 11];

    final alphabetSizes = [
        nLiteralCodes + nLengthCodes,
        nLiteralCodes,
        nLiteralCodes,
        nLiteralCodes,
        nDistanceCodes,
    ];

    // distanceMapTable is the look-up table for distanceMap.
    static final distanceMapTable = [
        0x18, 0x07, 0x17, 0x19, 0x28, 0x06, 0x27, 0x29, 0x16, 0x1a,
        0x26, 0x2a, 0x38, 0x05, 0x37, 0x39, 0x15, 0x1b, 0x36, 0x3a,
        0x25, 0x2b, 0x48, 0x04, 0x47, 0x49, 0x14, 0x1c, 0x35, 0x3b,
        0x46, 0x4a, 0x24, 0x2c, 0x58, 0x45, 0x4b, 0x34, 0x3c, 0x03,
        0x57, 0x59, 0x13, 0x1d, 0x56, 0x5a, 0x23, 0x2d, 0x44, 0x4c,
        0x55, 0x5b, 0x33, 0x3d, 0x68, 0x02, 0x67, 0x69, 0x12, 0x1e,
        0x66, 0x6a, 0x22, 0x2e, 0x54, 0x5c, 0x43, 0x4d, 0x65, 0x6b,
        0x32, 0x3e, 0x78, 0x01, 0x77, 0x79, 0x53, 0x5d, 0x11, 0x1f,
        0x64, 0x6c, 0x42, 0x4e, 0x76, 0x7a, 0x21, 0x2f, 0x75, 0x7b,
        0x31, 0x3f, 0x63, 0x6d, 0x52, 0x5e, 0x00, 0x74, 0x7c, 0x41,
        0x4f, 0x10, 0x20, 0x62, 0x6e, 0x30, 0x73, 0x7d, 0x51, 0x5f,
        0x40, 0x72, 0x7e, 0x61, 0x6f, 0x50, 0x71, 0x7f, 0x60, 0x70,
    ];

    // distanceMap maps an LZ77 backwards reference distance to a two-dimensional 
    // pixel offset, as specified in section 4.2.2.
    static function distanceMap(w:Int, code:Int):Int {
        if (code > distanceMapTable.length) {
            return code - distanceMapTable.length;
        }
        var distCode:Int = distanceMapTable[code - 1];
        var yOffset:Int = distCode >> 4;
        var xOffset:Int = 8 - (distCode & 0xF);
        var d:Int = yOffset * w + xOffset;
        return if (d >= 1) d else 1;
    }

    public function new(r: Input) {
        this.r = r;
    }

    // reads the next n bits from the decoder's bit-stream.
    public function read(n: Int): Int {
        while (nBits < n) {
            var c = r.readByte();
            bits |= (c & 0xFF) << nBits;
            nBits += 8;
        }
        var u = bits & ((1 << n) - 1);
        bits >>= n;
        nBits -= n;
        return u;
    }

    public function decodeTransform(w: Int, h: Int): {t: Transform, newWidth: Int} {
        var t = new Transform();
        t.oldWidth = w;
        var transformType = read(2);
        t.transformType = cast transformType;
        switch (t.transformType) {
            case TransformType.Predictor, TransformType.CrossColor:
                var bits = read(3);
                t.bits = bits + 2;
                t.pix = decodePix(nTiles(w, t.bits), nTiles(h, t.bits), 0, false);
            case TransformType.SubtractGreen:
                // No-op
            case TransformType.ColorIndexing:
                var nColors = read(8);
                nColors++;
                t.bits = switch (nColors) {
                    case 1, 2: 3;
                    case 3, 4: 2;
                    case 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16: 1;
                    default: 0;
                }
                w = nTiles(w, t.bits);
                var pix = decodePix(nColors, 1, 4 * 256, false);
                var p = 4;
                while (p < pix.length) {
                    pix.set(p, pix.get(p) + pix.get(p - 4));
                    pix.set(p + 1, pix.get(p + 1) + pix.get(p - 3));
                    pix.set(p + 2, pix.get(p + 2) + pix.get(p - 2));
                    pix.set(p + 3, pix.get(p + 3) + pix.get(p - 1));
                    p += 4;
                }
                t.pix = pix.sub(0, 4 * 256);
        }
        return { t: t, newWidth: w };
    }

    function decodeCodeLengths(dst: Array<Int>, codeLengthCodeLengths: Array<Int>): Void {
        var h = new HTree();
        h.build(codeLengthCodeLengths);

        var maxSymbol = dst.length;
        var useLength = read(1);
        if (useLength != 0) {
            var n = read(3);
            n = 2 + 2 * n;
            var ms = read(n);
            maxSymbol = ms + 2;
            if (maxSymbol > dst.length) throw "Invalid code lengths";
        }

        var prevCodeLength: Int = 8;

        var symbol = 0;
        while (symbol < dst.length) {
            if (maxSymbol == 0) break;
            maxSymbol--;
            var codeLength = h.next(this);
            if (codeLength < 16) {
                dst[symbol++] = codeLength;
                if (codeLength != 0) prevCodeLength = codeLength;
                continue;
            }

            var repeat = read(repeatBits[codeLength - 16]);
            repeat += repeatOffsets[codeLength - 16];
            if (symbol + repeat > dst.length) throw "Invalid code lengths";

            var cl: UInt = (codeLength == 16) ? prevCodeLength : 0;
            for (i in 0...repeat) dst[symbol++] = cl;
        }
    }

    function decodeHuffmanTree(h: HTree, alphabetSize: Int): Void {
        var useSimple = read(1);
        if (useSimple != 0) {
            var nSymbols = read(1) + 1;
            var firstSymbolLengthCode = read(1) * 7 + 1;
            var symbols = [0, 0];
            symbols[0] = read(firstSymbolLengthCode);
            if (nSymbols == 2) 
                symbols[1] = read(8);
            h.buildSimple(nSymbols, symbols, alphabetSize);
            return;
        }

        var nCodes = read(4) + 4;
        if (nCodes > codeLengthCodeOrder.length) 
            throw "Invalid Huffman tree";
        var codeLengthCodeLengths = [for (i in 0...codeLengthCodeOrder.length) 0];
        for (i in 0...nCodes) 
            codeLengthCodeLengths[codeLengthCodeOrder[i]] = read(3);

        var codeLengths = [for (i in 0...alphabetSize) 0];
        decodeCodeLengths(codeLengths, codeLengthCodeLengths);
        h.build(codeLengths);
    }

    function decodeHuffmanGroups(w:Int, h:Int, topLevel:Bool, ccBits:Int):
        {hGroups:Array<HGroup>, hPix:Bytes, hBits:Int} {
        
        var maxHGroupIndex = 0;
        var hPix:Bytes = null;
        var hBits = 0;
        
        if (topLevel) {
            var useMeta = read(1);
            if (useMeta != 0) {
                hBits = read(3) + 2;
                hPix = decodePix(nTiles(w, hBits), nTiles(h, hBits), 0, false);
                var p = 0;
                while (p < hPix.length) {
                    var i = (hPix.get(p) << 8) | hPix.get(p + 1);
                    if (maxHGroupIndex < i) 
                        maxHGroupIndex = i;
                    p += 4;
                }
            }
        }
        
        var hGroups:Array<HGroup> = [];
        for (i in 0...maxHGroupIndex + 1) {
            var group:HGroup = [for (i in 0...5) new HTree()];
            hGroups.push(group);
            for (j in 0...alphabetSizes.length) {
                var alphabetSize = alphabetSizes[j];
                if (j == 0 && ccBits > 0) 
                    alphabetSize += 1 << ccBits;
                decodeHuffmanTree(hGroups[i][j], alphabetSize);
            }
        }
        
        return {hGroups: hGroups, hPix: hPix, hBits: hBits};
    }

    function decodePix(w:Int, h:Int, minCap:Int, topLevel:Bool):Bytes {
        var ccBits = 0;
        var ccShift = 0;
        var ccEntries:Vector<Int> = null;
        
        if (read(1) != 0) {
            ccBits = read(4);
            if (ccBits < 1 || ccBits > 11) throw "Invalid color cache parameters";
            ccShift = 32 - ccBits;
            ccEntries = new Vector(1 << ccBits);
        }
        
        var huffmanData = decodeHuffmanGroups(w, h, topLevel, ccBits);
        var hGroups = huffmanData.hGroups;
        var hPix = huffmanData.hPix;
        var hBits = huffmanData.hBits;
        
        var hMask = if (hBits != 0) (1 << hBits) - 1 else 0;
        var tilesPerRow = if (hBits != 0) nTiles(w, hBits) else 0;
        
        var pix = Bytes.alloc(4 * w * h);
        var p = 0, cachedP = 0, x = 0, y = 0;
        var hg = hGroups[0];
        var lookupHG = hMask != 0;

        final huffGreen    = 0;
        final huffRed      = 1;
        final huffBlue     = 2;
        final huffAlpha    = 3;
        final huffDistance = 4;
        final nHuff        = 5;
        
        while (p < pix.length) {
            if (lookupHG) {
                var i = 4 * (tilesPerRow * (y >> hBits) + (x >> hBits));
                hg = hGroups[(hPix.get(i) << 8) | hPix.get(i + 1)];
            }
            
            var green = hg[huffGreen].next(this);
            
            if (green < nLiteralCodes) {
                var red = hg[huffRed].next(this);
                var blue = hg[huffBlue].next(this);
                var alpha = hg[huffAlpha].next(this);
                
                pix.set(p++, red);
                pix.set(p++, green);
                pix.set(p++, blue);
                pix.set(p++, alpha);
                
                x++;
                if (x == w) { 
                    x = 0; 
                    y++; 
                }
                lookupHG = hMask != 0 && (x & hMask) == 0;
                
            } else if (green < nLiteralCodes + nLengthCodes) {
                var length = lz77Param(green - nLiteralCodes);
                var distSym = hg[huffDistance].next(this);
                var distCode = lz77Param(distSym);
                var dist = distanceMap(w, distCode);
                
                var pEnd = p + 4 * length;
                var q = p - 4 * dist;
                var qEnd = pEnd - 4 * dist;
                
                if (p < 0 || q < 0 || pEnd > pix.length || qEnd > pix.length)
                    throw "Invalid LZ77 parameters";
                
                // TODO: use pix.blit for optimization
                while (p < pEnd) pix.set(p++, pix.get(q++));
                
                x += length;
                while (x >= w) { x -= w; y++; }
                lookupHG = hMask != 0;
                
            } else {
                // colorCacheMultiplier is the multiplier used for the color cache hash
                // function, specified in section 4.2.3.
                final colorCacheMultiplier = 0x1e35a7bd;
                while (cachedP < p) {
                    var argb = (pix.get(cachedP) << 16) | (pix.get(cachedP + 1) << 8) | (pix.get(cachedP + 2)) | (pix.get(cachedP + 3) << 24);
                    ccEntries[(argb * colorCacheMultiplier) >> ccShift] = argb;
                    cachedP += 4;
                }
                
                green -= nLiteralCodes + nLengthCodes;
                if (green >= ccEntries.length) throw "Invalid color cache index";
                
                var argb = ccEntries[green];
                pix.set(p++, (argb >> 16) & 0xFF);
                pix.set(p++, (argb >> 8) & 0xFF);
                pix.set(p++, argb & 0xFF);
                pix.set(p++, (argb >> 24) & 0xFF);
                
                x++;
                if (x == w) { x = 0; y++; }
                lookupHG = hMask != 0 && (x & hMask) == 0;
            }
        }
        return pix;
    }

    public function lz77Param(symbol: UInt): UInt {
        if (symbol < 4) {
            return symbol + 1;
        }
        var extraBits = (symbol - 2) >> 1;
        var offset = (2 + (symbol & 1)) << extraBits;
        var n = read(extraBits);
        return (offset + n + 1);
    }
    
    public static function decodeHeader(r: Input): {decoder: Vp8LDecoder, w: Int, h: Int} {
        var d = new Vp8LDecoder(r);
        var magic = d.read(8);
        if (magic == null || magic != 0x2f) {
            throw("vp8l: invalid header");
        }
        var width = d.read(14);
        if (width == null) throw("Read error");
        var height = d.read(14);
        if (height == null) throw("Read error");
        width++;
        height++;
        d.read(1); // Read and ignore the hasAlpha hint
        if (d.read(3) != 0) {
            throw("vp8l: invalid version");
        }
        return { decoder: d, w: width, h: height };
    }

    // Decode decodes a VP8L image from a reader.
    public static function decode(r:Input) {
        var result = decodeHeader(r);
        var d = result.decoder, w = result.w, h = result.h;

        // Decode the transforms.
        var nTransforms = 0;
        var transforms:Array<Transform> = [];
        var transformsSeen:Map<TransformType, Bool> = new Map();
        var originalW = w;

        while (true) {
            var more = d.read(1);
            if (more == 0) {
                break;
            }

            var dt = d.decodeTransform(w, h);
            final t = dt.t;
            w = dt.newWidth;
            if (t == null) {
                return null;
            }

            if (transformsSeen.exists(t.transformType)) {
                throw "vp8l: repeated transform";
            }

            transformsSeen.set(t.transformType, true);
            transforms.push(t);
            nTransforms++;
        }

        // Decode the transformed pixels.
        var pix = d.decodePix(w, h, 0, true);
        if (pix == null) {
            return null;
        }

        // Apply the inverse transformations.
        var i = nTransforms-1;
        while (i >= 0) {
            var t = transforms[i];
            pix = webp.vp8l.Transform.inverseTransforms[cast t.transformType](t, pix, h);
            i--;
        }
        
        return {
            pix: pix, 
            stride: 4 * originalW, 
            x: 0,
            y: 0,
            width: originalW,
            height: h
        };
    }
}



function decodePix(w: Int, h: Int, depth: Int, flag: Bool): Bytes {
    return Bytes.alloc(w * h * depth);
}


