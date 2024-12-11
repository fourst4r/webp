// Copyright 2011 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Package vp8 implements a decoder for the VP8 lossy image format.
// The VP8 specification is RFC 6386.
package webp.vp8;

// This file implements the top-level decoding algorithm.

import webp.vp8.Token;
import webp.vp8.Quant;
import webp.vp8.Filter;
import webp.vp8.Partition;
import haxe.io.BytesInput;
import haxe.ds.Vector;

class LimitReader {
    public var r:BytesInput;
    public var n:Int;

    public function new(r:BytesInput, n:Int) {
        this.r = r;
        this.n = n;
    }

    public function readFull(p:haxe.io.Bytes):Void {
        if (p.length > n) {
            throw "Unexpected EOF";
        }
        r.readBytes(p, 0, p.length);
        n -= p.length;
    }
}

typedef FrameHeader = {
    var keyFrame:Bool;
    var versionNumber:Int;
    var showFrame:Bool;
    var firstPartitionLen:Int;
    var width:Int;
    var height:Int;
    var xScale:Int;
    var yScale:Int;
}

final nSegment = 4;
final nSegmentProb = 3;

typedef SegmentHeader = {
    var useSegment:Bool;
    var updateMap:Bool;
    var relativeDelta:Bool;
    var quantizer:Array<Int>;
    var filterStrength:Array<Int>;
    var prob:Array<Int>;
}

class FilterConstants {
    public static inline var nRefLFDelta = 4;
    public static inline var nModeLFDelta = 4;
}

typedef FilterHeader = {
    var simple:Bool;
    var level:Int;
    var sharpness:Int;
    var useLFDelta:Bool;
    var refLFDelta:Array<Int>;
    var modeLFDelta:Array<Int>;
    var perSegmentLevel:Array<Int>;
}

class MB {
    public var pred:Array<Int>;
    public var nzMask:Int;
    public var nzY16:Int;
    public function new() {
        pred = [];
        nzMask = 0;
        nzY16 = 0;
    }
}

class Decoder {
    public var r:LimitReader;
    public var scratch:haxe.io.Bytes;
    public var img:YccImage;
    public var mbw:Int;
    public var mbh:Int;
    public var frameHeader:FrameHeader;
    public var segmentHeader:SegmentHeader;
    public var filterHeader:FilterHeader;
    public var fp:Partition;
    public var op:Vector<Partition>;
    public var nOP:Int;
    public var quant:Vector<Quant>;
    public var tokenProb:Array<Array<Array<Array<Int>>>>;
    // public var tokenProb:Vector<Vector<Vector<Vector<Int>>>>;
    public var useSkipProb:Bool;
    public var skipProb:Int;
    public var filterParams:Vector<Vector<FilterParam>>;
    public var perMBFilterParams:Array<FilterParam>;
    public var segment:Int;
    public var leftMB:MB;
    public var upMB:Array<MB>;
    public var nzDCMask:Int;
    public var nzACMask:Int;
    public var usePredY16:Bool;
    public var predY16:Int;
    public var predC8:Int;
    public var predY4:Vector<Vector<Int>>;
    public var coeff:Vector<Int>;
    public var ybr:Vector<Vector<Int>>;

    public function new() {
        scratch = haxe.io.Bytes.alloc(8);
        op = new Vector(8);
        quant = new Vector(nSegment);

        tokenProb = [];
        // tokenProb = new Vector(nPlane);
        // for (i in 0...tokenProb.length) {
        //     tokenProb[i] = new Vector(nBand);
        //     for (j in 0...tokenProb[i].length) {
        //         tokenProb[i][j] = new Vector(nContext);
        //         for (k in 0...tokenProb[i][j].length) {
        //             tokenProb[i][j][k] = new Vector(nProb);
        //         }
        //     }
        // }

        filterParams = new Vector(nSegment);
        for (i in 0...filterParams.length) filterParams[i] = new Vector(2);

        perMBFilterParams = [];
        upMB = [];

        predY4 = new Vector(4);
        for (i in 0...predY4.length) predY4[i] = new Vector(4);
        
        coeff = new Vector(1*16*16 + 2*8*8 + 1*4*4);
        
        ybr = new Vector(1 + 16 + 1 + 8);
        for (i in 0...ybr.length) ybr[i] = new Vector(32);
    }

    public function init(r:BytesInput, n:Int):Void {
        this.r = new LimitReader(r, n);
    }

    public function decodeFrameHeader():FrameHeader {
        var b = scratch.sub(0, 3);
        r.readFull(b);

        frameHeader = {
            keyFrame: (b.get(0) & 1) == 0,
            versionNumber: (b.get(0) >> 1) & 7,
            showFrame: (b.get(0) >> 4) & 1 == 1,
            firstPartitionLen: (b.get(0) >> 5) | (b.get(1) << 3) | (b.get(2) << 11),
            width: 0,
            height: 0,
            yScale: 0,
            xScale: 0
        };

        if (!frameHeader.keyFrame) {
            return frameHeader;
        }

        b = scratch.sub(0, 7);
        r.readFull(b);

        if (b.get(0) != 0x9d || b.get(1) != 0x01 || b.get(2) != 0x2a) {
            throw "vp8: invalid format";
        }

        frameHeader.width = (b.get(4) & 0x3f) << 8 | b.get(3);
        frameHeader.height = (b.get(6) & 0x3f) << 8 | b.get(5);
        frameHeader.xScale = b.get(4) >> 6;
        frameHeader.yScale = b.get(6) >> 6;
        mbw = (frameHeader.width + 0x0f) >> 4;
        mbh = (frameHeader.height + 0x0f) >> 4;

        segmentHeader = {
            prob: [0xff, 0xff, 0xff],
            filterStrength: [],
            quantizer: [],
            useSegment: false,
            updateMap: false,
            relativeDelta: false,
        };

        tokenProb = defaultTokenProb;
        segment = 0;
        return frameHeader;
    }

    public function ensureImg():Void {
        if (img != null && 
            img.rect.minX == 0 && img.rect.minY == 0 && 
            img.rect.maxX >= 16 * mbw && img.rect.maxY >= 16 * mbh) {
            return;
        }
        
        var m = YccImage.blank(16 * mbw, 16 * mbh);
        img = m.subImage(0, 0, frameHeader.width, frameHeader.height);
        perMBFilterParams = [];
        upMB = [];
    }

    public function parseSegmentHeader():Void {
        segmentHeader.useSegment = fp.readBit(uniformProb);
        if (!segmentHeader.useSegment) {
            segmentHeader.updateMap = false;
            return;
        }

        segmentHeader.updateMap = fp.readBit(uniformProb);
        if (fp.readBit(uniformProb)) {
            segmentHeader.relativeDelta = !fp.readBit(uniformProb);
            for (i in 0...segmentHeader.quantizer.length) {
                segmentHeader.quantizer[i] = fp.readOptionalInt(uniformProb, 7);
            }
            for (i in 0...segmentHeader.filterStrength.length) {
                segmentHeader.filterStrength[i] = fp.readOptionalInt(uniformProb, 6);
            }
        }

        if (!segmentHeader.updateMap) return;

        for (i in 0...segmentHeader.prob.length) {
            segmentHeader.prob[i] = if (fp.readBit(uniformProb)) 
                fp.readUint(uniformProb, 8) else 0xff;
        }
    }

    public function parseFilterHeader():Void {
        filterHeader.simple = fp.readBit(uniformProb);
        filterHeader.level = fp.readUint(uniformProb, 6);
        filterHeader.sharpness = fp.readUint(uniformProb, 3);
        filterHeader.useLFDelta = fp.readBit(uniformProb);

        if (filterHeader.useLFDelta && fp.readBit(uniformProb)) {
            for (i in 0...filterHeader.refLFDelta.length) {
                filterHeader.refLFDelta[i] = fp.readOptionalInt(uniformProb, 6);
            }
            for (i in 0...filterHeader.modeLFDelta.length) {
                filterHeader.modeLFDelta[i] = fp.readOptionalInt(uniformProb, 6);
            }
        }

        if (filterHeader.level == 0) return;

        if (segmentHeader.useSegment) {
            for (i in 0...filterHeader.perSegmentLevel.length) {
                var strength = segmentHeader.filterStrength[i];
                if (segmentHeader.relativeDelta) {
                    strength += filterHeader.level;
                }
                filterHeader.perSegmentLevel[i] = strength;
            }
        } else {
            filterHeader.perSegmentLevel[0] = filterHeader.level;
        }
        computeFilterParams();
    }

    public function parseOtherPartitions():Bool {
        final maxNOP = 8;
        var partLens = new Vector(maxNOP);
        nOP = 1 << fp.readUint(uniformProb, 2);

        var n = 3 * (nOP - 1);
        partLens[nOP - 1] = r.n - n;
        if (partLens[nOP - 1] < 0) return false;

        if (n > 0) {
            var buf = Bytes.alloc(n);
            r.readFull(buf);
            for (i in 0...nOP - 1) {
                var pl = buf.get(3 * i) | (buf.get(3 * i + 1) << 8) | (buf.get(3 * i + 2) << 16);
                if (pl > partLens[nOP - 1]) return false;
                partLens[i] = pl;
                partLens[nOP - 1] -= pl;
            }
        }

        if (1 << 24 <= partLens[nOP - 1]) return false;

        var buf = Bytes.alloc(r.n);
        r.readFull(buf);
        for (i in 0...nOP) {
            if (i >= partLens.length) break;
            op[i].init(buf.sub(0, partLens[i]));
        }
        return true;
    }

    public function parseOtherHeaders():Bool {
        // Initialize and parse the first partition
        var firstPartition = Bytes.alloc(frameHeader.firstPartitionLen);
        try r.readFull(firstPartition) catch (e) return false;

        fp.init(firstPartition);

        if (frameHeader.keyFrame) {
            // Read and ignore color space and pixel clamp values
            fp.readBit(uniformProb);
            fp.readBit(uniformProb);
        }

        parseSegmentHeader();
        parseFilterHeader();

        if (!parseOtherPartitions()) return false;

        parseQuant();

        if (!frameHeader.keyFrame) {
            // Golden and AltRef frames are only for video
            return false;
        }

        // Read and ignore refreshLastFrameBuffer bit
        fp.readBit(uniformProb);

        parseTokenProb();
        useSkipProb = fp.readBit(uniformProb);

        if (useSkipProb) {
            skipProb = fp.readUint(uniformProb, 8);
        }

        if (fp.unexpectedEOF) return false;
        return true;
    }

    public function decodeFrame():YccImage {
        ensureImg();
        if (!parseOtherHeaders()) return null;

        // Reconstruct the rows
        for (mbx in 0...mbw) {
            upMB[mbx] = new MB();
        }

        for (mby in 0...mbh) {
            leftMB = new MB();

            for (mbx in 0...mbw) {
                var skip = reconstruct(mbx, mby);
                var fs = filterParams[segment][btou(!usePredY16)];
                fs.inner = fs.inner || !skip;
                perMBFilterParams[mbw * mby + mbx] = fs;
            }
        }

        if (fp.unexpectedEOF) return null;

        for (i in 0...nOP) {
            if (op[i].unexpectedEOF) return null;
        }

        // Apply the loop filter
        if (filterHeader.level != 0) {
            if (filterHeader.simple) {
                simpleFilter();
            } else {
                normalFilter();
            }
        }

        return img;
    }

    function parseQuant():Void {
        var baseQ0 = fp.readUint(uniformProb, 7);
        var dqy1DC = fp.readOptionalInt(uniformProb, 4);
        var dqy2DC = fp.readOptionalInt(uniformProb, 4);
        var dqy2AC = fp.readOptionalInt(uniformProb, 4);
        var dquvDC = fp.readOptionalInt(uniformProb, 4);
        var dquvAC = fp.readOptionalInt(uniformProb, 4);

        function clip(x:Int, min:Int, max:Int):Int {
            return if (x < min) min else if (x > max) max else x;
        }

        for (i in 0...nSegment) {
            var q = baseQ0;
            if (segmentHeader.useSegment) {
                if (segmentHeader.relativeDelta) {
                    q += segmentHeader.quantizer[i];
                } else {
                    q = segmentHeader.quantizer[i];
                }
            }

            quant[i].y1[0] = dequantTableDC[clip(q + dqy1DC, 0, 127)];
            quant[i].y1[1] = dequantTableAC[clip(q, 0, 127)];
            quant[i].y2[0] = dequantTableDC[clip(q + dqy2DC, 0, 127)] * 2;
            quant[i].y2[1] = Std.int(dequantTableAC[clip(q + dqy2AC, 0, 127)] * 155 / 100);
            if (quant[i].y2[1] < 8) {
                quant[i].y2[1] = 8;
            }

            quant[i].uv[0] = dequantTableDC[clip(q + dquvDC, 0, 117)];
            quant[i].uv[1] = dequantTableAC[clip(q + dquvAC, 0, 127)];
        }
    }

    function simpleFilter():Void {
        for (mby in 0...mbh) {
            for (mbx in 0...mbw) {
                var f = perMBFilterParams[mbw * mby + mbx];
                if (f.level == 0) continue;

                var l = f.level;
                var yIndex = Std.int((mby * img.YStride + mbx) * 16);

                if (mbx > 0) filter2(img.Y, l + 4, yIndex, img.YStride, 1);

                if (f.inner) {
                    filter2(img.Y, l, yIndex + 0x4, img.YStride, 1);
                    filter2(img.Y, l, yIndex + 0x8, img.YStride, 1);
                    filter2(img.Y, l, yIndex + 0xC, img.YStride, 1);
                }

                if (mby > 0) filter2(img.Y, l + 4, yIndex, 1, img.YStride);

                if (f.inner) {
                    filter2(img.Y, l, yIndex + Std.int(img.YStride * 0x4), 1, img.YStride);
                    filter2(img.Y, l, yIndex + Std.int(img.YStride * 0x8), 1, img.YStride);
                    filter2(img.Y, l, yIndex + Std.int(img.YStride * 0xC), 1, img.YStride);
                }
            }
        }
    }

    function normalFilter():Void {
        for (mby in 0...mbh) {
            for (mbx in 0...mbw) {
                var f = perMBFilterParams[mbw * mby + mbx];
                if (f.level == 0) continue;

                var l = f.level;
                var il = f.ilevel;
                var hl = f.hlevel;
                var yIndex = Std.int((mby * img.YStride + mbx) * 16);
                var cIndex = Std.int((mby * img.CStride + mbx) * 8);

                if (mbx > 0) {
                    filter246(img.Y, 16, l + 4, il, hl, yIndex, img.YStride, 1, false);
                    filter246(img.Cb, 8, l + 4, il, hl, cIndex, img.CStride, 1, false);
                    filter246(img.Cr, 8, l + 4, il, hl, cIndex, img.CStride, 1, false);
                }

                if (f.inner) {
                    filter246(img.Y, 16, l, il, hl, yIndex + 0x4, img.YStride, 1, true);
                    filter246(img.Y, 16, l, il, hl, yIndex + 0x8, img.YStride, 1, true);
                    filter246(img.Y, 16, l, il, hl, yIndex + 0xC, img.YStride, 1, true);
                    filter246(img.Cb, 8, l, il, hl, cIndex + 0x4, img.CStride, 1, true);
                    filter246(img.Cr, 8, l, il, hl, cIndex + 0x4, img.CStride, 1, true);
                }

                if (mby > 0) {
                    filter246(img.Y, 16, l + 4, il, hl, yIndex, 1, img.YStride, false);
                    filter246(img.Cb, 8, l + 4, il, hl, cIndex, 1, img.CStride, false);
                    filter246(img.Cr, 8, l + 4, il, hl, cIndex, 1, img.CStride, false);
                }

                if (f.inner) {
                    filter246(img.Y, 16, l, il, hl, yIndex + Std.int(img.YStride * 0x4), 1, img.YStride, true);
                    filter246(img.Y, 16, l, il, hl, yIndex + Std.int(img.YStride * 0x8), 1, img.YStride, true);
                    filter246(img.Y, 16, l, il, hl, yIndex + Std.int(img.YStride * 0xC), 1, img.YStride, true);
                    filter246(img.Cb, 8, l, il, hl, cIndex + Std.int(img.CStride * 0x4), 1, img.CStride, true);
                    filter246(img.Cr, 8, l, il, hl, cIndex + Std.int(img.CStride * 0x4), 1, img.CStride, true);
                }
            }
        }
    }

    function computeFilterParams():Void {
        inline function min(a:Int, b:Int):Int {
            return a < b ? a : b;
        }

        inline function max(a:Int, b:Int):Int {
            return a > b ? a : b;
        }

        for (i in 0...filterParams.length) {
            var baseLevel = filterHeader.level;

            if (segmentHeader.useSegment) {
                baseLevel = segmentHeader.filterStrength[i];
                if (segmentHeader.relativeDelta) baseLevel += filterHeader.level;
            }

            for (j in 0...filterParams[i].length) {
                var p = filterParams[i][j];
                p.inner = j != 0;

                var level = baseLevel;
                if (filterHeader.useLFDelta) {
                    level += filterHeader.refLFDelta[0];
                    if (j != 0) level += filterHeader.modeLFDelta[0];
                }

                if (level <= 0) {
                    p.level = 0;
                    continue;
                }

                level = min(level, 63);
                var ilevel = level;

                if (filterHeader.sharpness > 0) {
                    ilevel >>= (filterHeader.sharpness > 4 ? 2 : 1);
                    ilevel = min(ilevel, 9 - filterHeader.sharpness);
                }

                ilevel = max(ilevel, 1);
                p.ilevel = ilevel;
                p.level = 2 * level + ilevel;

                p.hlevel = if (frameHeader.keyFrame)
                    if (level < 15) 0 else if (level < 40) 1 else 2
                else
                    if (level < 15) 0 else if (level < 20) 1 else if (level < 40) 2 else 3;
            }
        }
    }

    function prepareYBR(mbx:Int, mby:Int):Void {
		if (mbx == 0) {
			for (y in 0...17) ybr[y][7] = 0x81;
			for (y in 17...26) {
				ybr[y][7] = 0x81;
				ybr[y][23] = 0x81;
			}
		} else {
			for (y in 0...17) ybr[y][7] = ybr[y][7 + 16];
			for (y in 17...26) {
				ybr[y][7] = ybr[y][15];
				ybr[y][23] = ybr[y][31];
			}
		}

		if (mby == 0) {
			for (x in 7...28) ybr[0][x] = 0x7f;
			for (x in 7...16) ybr[17][x] = 0x7f;
			for (x in 23...32) ybr[17][x] = 0x7f;
		} else {
			for (i in 0...16) ybr[0][8 + i] =  img.Y.get((16 * mby - 1) * img.YStride + 16 * mbx + i);
			for (i in 0...8) ybr[17][8 + i] =  img.Cb.get((8 * mby - 1) * img.CStride + 8 * mbx + i);
			for (i in 0...8) ybr[17][24 + i] = img.Cr.get((8 * mby - 1) * img.CStride + 8 * mbx + i);

			if (mbx == mbw - 1) {
				for (i in 16...20) ybr[0][8 + i] = img.Y.get((16 * mby - 1) * img.YStride + 16 * mbx + 15);
			} else {
				for (i in 16...20) ybr[0][8 + i] = img.Y.get((16 * mby - 1) * img.YStride + 16 * mbx + i);
			}
		}

        var y = 4;
        while (y < 16) {
            for (x in 24...28) ybr[y][x] = ybr[0][x];
            y += 4;
        }
	}
}