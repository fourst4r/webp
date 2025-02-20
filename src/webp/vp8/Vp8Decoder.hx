// Copyright 2011 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Package vp8 implements a decoder for the VP8 lossy image format.
// The VP8 specification is RFC 6386.
package webp.vp8;

// This file implements the top-level decoding algorithm.

import webp.types.UInt8Vector;
import webp.types.Int8Vector;
import haxe.io.Input;
import haxe.io.Bytes;
import haxe.io.BytesInput;
import haxe.ds.Vector;
import webp.vp8.Token;
import webp.vp8.Quant;
import webp.vp8.Filter;
import webp.vp8.Partition;
import webp.vp8.Reconstruct;
import webp.vp8.Pred;
import webp.vp8.PredFunc;

class LimitReader {
    public var r:Input;
    public var n:Int;

    public function new(r:Input, n:Int) {
        this.r = r;
        this.n = n;
    }

    public function readFull(p:haxe.io.Bytes):Void {
        if (p.length > n) {
            throw "Unexpected EOF";
        }
        r.readFullBytes(p, 0, p.length);
        n -= p.length;
    }
}

final nSegment = 4;
final nSegmentProb = 3;

typedef SegmentHeader = {
    var useSegment:Bool;
    var updateMap:Bool;
    var relativeDelta:Bool;
    var quantizer:Int8Vector;
    var filterStrength:Int8Vector;
    var prob:UInt8Vector;
}

final nRefLFDelta = 4;
final nModeLFDelta = 4;

typedef FilterHeader = {
    var simple:Bool;
    var level:Int;
    var sharpness:Int;
    var useLFDelta:Bool;
    var refLFDelta:Int8Vector;
    var modeLFDelta:Int8Vector;
    var perSegmentLevel:Int8Vector;
}

class MB {
    public var pred:UInt8Vector;
    public var nzMask:Int;
    public var nzY16:Int;
    public function new() {
        pred = new UInt8Vector(4);
        nzMask = 0;
        nzY16 = 0;
    }
}

class Vp8Decoder {
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
        for (i in 0...quant.length) quant[i] = new Quant();

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
        for (i in 0...filterParams.length) {
            filterParams[i] = new Vector(2);
            filterParams[i][0] = { level:0, ilevel:0, hlevel:0, inner:false };
            filterParams[i][1] = { level:0, ilevel:0, hlevel:0, inner:false };
        }
        
        perMBFilterParams = [];
        upMB = [];

        predY4 = new Vector(4);
        for (i in 0...predY4.length) predY4[i] = new Vector(4);
        
        coeff = new Vector(1*16*16 + 2*8*8 + 1*4*4);
        
        ybr = new Vector(1 + 16 + 1 + 8);
        for (i in 0...ybr.length) ybr[i] = new Vector(32, 0);

        filterHeader = {
            simple: false,
            perSegmentLevel: new Int8Vector(nSegment),
            modeLFDelta: new Int8Vector(nModeLFDelta),
            refLFDelta: new Int8Vector(nRefLFDelta),
            useLFDelta: false,
            sharpness: 0,
            level: 0
        };
    }

    public function init(r:Input, n:Int):Void {
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
            prob: new UInt8Vector(nSegmentProb),//[0xff, 0xff, 0xff],
            filterStrength: new Int8Vector(nSegment),
            quantizer: new Int8Vector(nSegment),
            useSegment: false,
            updateMap: false,
            relativeDelta: false,
        };
        for (i in 0...segmentHeader.prob.length) segmentHeader.prob[i] = 0xff;

        tokenProb = defaultTokenProb;
        segment = 0;
        return frameHeader;
    }

    function ensureImg():Void {
        if (img != null && 
            img.rect.minX == 0 && img.rect.minY == 0 && 
            img.rect.maxX >= 16 * mbw && img.rect.maxY >= 16 * mbh) {
            return;
        }
        
        var m = YccImage.blank(16 * mbw, 16 * mbh);
        // TODO: impl subimage
        // img = m;
        img = m.subImage(0, 0, frameHeader.width, frameHeader.height);
        perMBFilterParams = [];
        upMB = [];
    }

    function parseSegmentHeader():Void {
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

    function parseFilterHeader():Void {
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

    function parseOtherPartitions():Bool {
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
            op[i] = new Partition(buf.sub(0, partLens[i]));
        }
        return true;
    }

    function parseOtherHeaders():Bool {
        // Initialize and parse the first partition
        var firstPartition = Bytes.alloc(frameHeader.firstPartitionLen);
        try 
            r.readFull(firstPartition) 
        catch (e) 
                return false;

        fp = new Partition(firstPartition); // certified

        if (frameHeader.keyFrame) {
            // Read and ignore color space and pixel clamp values
            fp.readBit(uniformProb);
            fp.readBit(uniformProb);
        }

        parseSegmentHeader();
        parseFilterHeader(); // certified

        if (!parseOtherPartitions()) return false;

        parseQuant(); // certified

        if (!frameHeader.keyFrame) {
            // Golden and AltRef frames are only for video
            return false;
        }

        // Read and ignore refreshLastFrameBuffer bit
        fp.readBit(uniformProb);

        parseTokenProb(); // certified
        useSkipProb = fp.readBit(uniformProb);

        if (useSkipProb) {
            skipProb = fp.readUint(uniformProb, 8);
        }

        if (fp.unexpectedEOF) return false;
        return true;
    }

    function parseTokenProb():Void {
        for (i in 0...tokenProb.length)
            for (j in 0...tokenProb[i].length)
                for (k in 0...tokenProb[i][j].length)
                    for (l in 0...tokenProb[i][j][k].length)
                        if (fp.readBit(tokenProbUpdateProb[i][j][k][l]))
                            tokenProb[i][j][k][l] = fp.readUint(uniformProb, 8);
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

    function parseResiduals4(r: Partition, plane: Int, context: Int, quant: Array<Int>, skipFirstCoeff: Bool, coeffBase: Int): Int {
        var prob = tokenProb[plane];
        var n = skipFirstCoeff ? 1 : 0;
        var p = prob[bands[n]][context];
        
        if (!r.readBit(p[0])) return 0;
        //1,165,230,250,199,191,247,159,255,255,128
        while (n != 16) {
            n++;
            if (!r.readBit(p[1])) {
                p = prob[bands[n]][0];
                continue;
            }
            
            var v: Int = 0;
            if (!r.readBit(p[2])) {
                v = 1;
                p = prob[bands[n]][1];
            } else {
                if (!r.readBit(p[3])) {
                    v = !r.readBit(p[4]) ? 2 : 3 + r.readUint(p[5], 1);
                } else if (!r.readBit(p[6])) {
                    v = !r.readBit(p[7]) 
                        ? 5 + r.readUint(159, 1)
                        : 7 + 2 * r.readUint(165, 1) + r.readUint(145, 1);
                } else {
                    var b1 = r.readUint(p[8], 1);
                    var b0 = r.readUint(p[9 + b1], 1);
                    var cat = 2 * b1 + b0;
                    var tab = cat3456[cat];
                    for (i in 0...tab.length) {
                        if (tab[i] == 0) break;
                        v *= 2;
                        v += r.readUint(tab[i], 1);
                    }
                    v += 3 + (8 << cat);
                }
                p = prob[bands[n]][2];
            }
            
            var z = zigzag[n - 1];
            var c = v * quant[z > 0 ? 1 : 0];
            c = r.readBit(uniformProb) ? -c : c;
            
            coeff[coeffBase + z] = c;
            
            if (n == 16 || !r.readBit(p[0])) return 1;
        }
        
        return 1;
    }

    function parseResiduals(mbx: Int, mby: Int): Bool {
        var partition = op[mby & (nOP - 1)];
        var plane = planeY1SansY2;
        var quant = this.quant[segment];
        
        if (usePredY16) {
            var nz = parseResiduals4(partition, planeY2, 
                leftMB.nzY16 + upMB[mbx].nzY16, 
                quant.y2, false, whtCoeffBase);
            leftMB.nzY16 = nz;
            upMB[mbx].nzY16 = nz;
            inverseWHT16();
            plane = planeY1WithY2;
        }
        
        var nzDC: Array<Int> = [0, 0, 0, 0];
        var nzAC: Array<Int> = [0, 0, 0, 0];
        var nzDCMask: Int = 0;
        var nzACMask: Int = 0;
        var coeffBase: Int = 0;
        
        var lnz = unpack[leftMB.nzMask & 0x0f].copy();
        var unz = unpack[upMB[mbx].nzMask & 0x0f].copy();
        
        // Luma processing
        for (y in 0...4) {
            var nz = lnz[y];
            for (x in 0...4) {
                nz = parseResiduals4(partition, plane, 
                    nz + unz[x], quant.y1, usePredY16, coeffBase);
                unz[x] = nz;
                nzAC[x] = nz;
                nzDC[x] = coeff[coeffBase] != 0 ? 1 : 0;
                coeffBase += 16;
            }
            lnz[y] = nz;
            nzDCMask |= pack(nzDC, y * 4);
            nzACMask |= pack(nzAC, y * 4);
        }
        
        var lnzMask = pack(lnz, 0);
        var unzMask = pack(unz, 0);
        
        // Chroma processing
        lnz = unpack[leftMB.nzMask >> 4].copy();
        unz = unpack[upMB[mbx].nzMask >> 4].copy();
        
        var c = 0;
        while (c < 4) {
            for (y in 0...2) {
                var nz = lnz[y + c];
                for (x in 0...2) {
                    nz = parseResiduals4(partition, planeUV, 
                        nz + unz[x + c], quant.uv, false, coeffBase);
                    unz[x + c] = nz;
                    nzAC[y * 2 + x] = nz;
                    nzDC[y * 2 + x] = coeff[coeffBase] != 0 ? 1 : 0;
                    coeffBase += 16;
                }
                lnz[y + c] = nz;
            }
            nzDCMask |= pack(nzDC, 16 + c * 2);
            nzACMask |= pack(nzAC, 16 + c * 2);
            c += 2;
        }
        
        lnzMask |= pack(lnz, 4);
        unzMask |= pack(unz, 4);
        
        leftMB.nzMask = lnzMask;
        upMB[mbx].nzMask = unzMask;
        this.nzDCMask = nzDCMask;
        this.nzACMask = nzACMask;
        
        return nzDCMask == 0 && nzACMask == 0;
    }

    function reconstructMacroblock(mbx: Int, mby: Int): Void {
        if (usePredY16) {
            var p = checkTopLeftPred(mbx, mby, predY16);
            predFunc16[p](this, 1, 8);
            
            for (j in 0...4) {
                for (i in 0...4) {
                    var n = 4 * j + i;
                    var y = 4 * j + 1;
                    var x = 4 * i + 8;
                    var mask = 1 << n;
                    
                    if ((nzACMask & mask) != 0) {
                        inverseDCT4(y, x, 16 * n);
                    } else if ((nzDCMask & mask) != 0) {
                        inverseDCT4DCOnly(y, x, 16 * n);
                    }
                }
            }
        } else {
            for (j in 0...4) {
                for (i in 0...4) {
                    var n = 4 * j + i;
                    var y = 4 * j + 1;
                    var x = 4 * i + 8;
                    
                    predFunc4[predY4[j][i]](this, y, x);
                    
                    var mask = 1 << n;
                    if ((nzACMask & mask) != 0) {
                        inverseDCT4(y, x, 16 * n);
                    } else if ((nzDCMask & mask) != 0) {
                        inverseDCT4DCOnly(y, x, 16 * n);
                    }
                }
            }
        }
        
        var p = checkTopLeftPred(mbx, mby, predC8);
        predFunc8[p](this, ybrBY, ybrBX);
        
        if ((nzACMask & 0x0f0000) != 0) {
            inverseDCT8(ybrBY, ybrBX, bCoeffBase);
        } else if ((nzDCMask & 0x0f0000) != 0) {
            inverseDCT8DCOnly(ybrBY, ybrBX, bCoeffBase);
        }
        
        predFunc8[p](this, ybrRY, ybrRX);
        
        if ((nzACMask & 0xf00000) != 0) {
            inverseDCT8(ybrRY, ybrRX, rCoeffBase);
        } else if ((nzDCMask & 0xf00000) != 0) {
            inverseDCT8DCOnly(ybrRY, ybrRX, rCoeffBase);
        }
    }
    
    function reconstruct(mbx: Int, mby: Int): Bool {
        if (segmentHeader.updateMap) {
            segment = !fp.readBit(segmentHeader.prob[0]) 
                ? fp.readUint(segmentHeader.prob[1], 1)
                : fp.readUint(segmentHeader.prob[2], 1) + 2;
        }
        
        var skip = useSkipProb ? fp.readBit(skipProb) : false;
        
        for (i in 0...coeff.length) {
            coeff[i] = 0;
        }
        
        prepareYBR(mbx, mby);
        // formatMatrix(ybr);
        usePredY16 = fp.readBit(145);
        
        if (usePredY16) {
            parsePredModeY16(mbx);
        } else {
            parsePredModeY4(mbx);
        }
        
        parsePredModeC8();
        
        if (!skip) {
            skip = parseResiduals(mbx, mby);
        } else {
            if (usePredY16) {
                leftMB.nzY16 = 0;
                upMB[mbx].nzY16 = 0;
            }
            
            leftMB.nzMask = 0;
            upMB[mbx].nzMask = 0;
            nzDCMask = 0;
            nzACMask = 0;
        }
        
        reconstructMacroblock(mbx, mby);
        // formatMatrix(ybr);

        for (y in 0...16) {
            var i = (mby * img.YStride + mbx) * 16 + y * img.YStride;
            copy(img.Y, i, ybr[ybrYY + y], ybrYX, 16);
        }
        
        for (y in 0...8) {
            var i = (mby * img.CStride + mbx) * 8 + y * img.CStride;
            copy(img.Cb, i, ybr[ybrBY + y], ybrBX, 8);
            copy(img.Cr, i, ybr[ybrRY + y], ybrRX, 8);
        }
        
        return skip;
    }

    static function formatMatrix<T>(matrix: Vector<Vector<T>>) {
        var output = new StringBuf();
        for (row in matrix) {
            output.add("| ");
            for (cell in row) {
                output.add('${Std.string(cell)} ');
            }
            output.add("|\n");
        }
        trace(output.toString());
    }

    static function copy(dst:Bytes, pos:Int, src:Vector<Int>, srcpos:Int, len:Int):Void {
        #if !neko
		if (pos < 0 || srcpos < 0 || len < 0 || pos + len > dst.length || srcpos + len > src.length)
			throw "out of bounds";
		#end

        var dsti = pos;
        for (srci in srcpos...(srcpos + len)) {
            dst.set(dsti++, src[srci]);
        }
    }

    public function parsePredModeY16(mbx:Int):Void {
        var p:Int = predDC;
        if (!fp.readBit(156)) {
            if (!fp.readBit(163)) {
                p = predDC;
            } else {
                p = predVE;
            }
        } else if (!fp.readBit(128)) {
            p = predHE;
        } else {
            p = predTM;
        }
        for (i in 0...4) {
            upMB[mbx].pred[i] = p;
            leftMB.pred[i] = p;
        }
        predY16 = p;
    }

    public function parsePredModeC8():Void {
        if (!fp.readBit(142)) {
            predC8 = predDC;
        } else if (!fp.readBit(114)) {
            predC8 = predVE;
        } else if (!fp.readBit(183)) {
            predC8 = predHE;
        } else {
            predC8 = predTM;
        }
    }

    public function parsePredModeY4(mbx:Int):Void {
        for (j in 0...4) {
            var p:Int = leftMB.pred[j];
            for (i in 0...4) {
                var prob:Array<Int> = predProb[upMB[mbx].pred[i]][p];
                if (!fp.readBit(prob[0])) {
                    p = predDC;
                } else if (!fp.readBit(prob[1])) {
                    p = predTM;
                } else if (!fp.readBit(prob[2])) {
                    p = predVE;
                } else if (!fp.readBit(prob[3])) {
                    if (!fp.readBit(prob[4])) {
                        p = predHE;
                    } else if (!fp.readBit(prob[5])) {
                        p = predRD;
                    } else {
                        p = predVR;
                    }
                } else if (!fp.readBit(prob[6])) {
                    p = predLD;
                } else if (!fp.readBit(prob[7])) {
                    p = predVL;
                } else if (!fp.readBit(prob[8])) {
                    p = predHD;
                } else {
                    p = predHU;
                }
                predY4[j][i] = p;
                upMB[mbx].pred[i] = p;
            }
            leftMB.pred[j] = p;
        }
    }
    
    function inverseDCT4(y:Int, x:Int, coeffBase:Int):Void {
        final c1:Int = 85627; // 65536 * cos(pi/8) * sqrt(2)
        final c2:Int = 35468; // 65536 * sin(pi/8) * sqrt(2)
        var m:Array<Array<Int>> = [[0,0,0,0],[0,0,0,0],[0,0,0,0],[0,0,0,0]];
    
        for (i in 0...4) {
            var a:Int = Std.int(coeff[coeffBase+0]) + Std.int(coeff[coeffBase+8]);
            var b:Int = Std.int(coeff[coeffBase+0]) - Std.int(coeff[coeffBase+8]);
            var c:Int = (Std.int(coeff[coeffBase+4])*c2 >> 16) - (Std.int(coeff[coeffBase+12])*c1 >> 16);
            var d:Int = (Std.int(coeff[coeffBase+4])*c1 >> 16) + (Std.int(coeff[coeffBase+12])*c2 >> 16);
            
            m[i][0] = a + d;
            m[i][1] = b + c;
            m[i][2] = b - c;
            m[i][3] = a - d;
            coeffBase++;
        }
    
        for (j in 0...4) {
            var dc:Int = m[0][j] + 4;
            var a:Int = dc + m[2][j];
            var b:Int = dc - m[2][j];
            var c:Int = (m[1][j]*c2 >> 16) - (m[3][j]*c1 >> 16);
            var d:Int = (m[1][j]*c1 >> 16) + (m[3][j]*c2 >> 16);
            
            ybr[y+j][x+0] = clip8(Std.int(ybr[y+j][x+0]) + (a+d >> 3));
            ybr[y+j][x+1] = clip8(Std.int(ybr[y+j][x+1]) + (b+c >> 3));
            ybr[y+j][x+2] = clip8(Std.int(ybr[y+j][x+2]) + (b-c >> 3));
            ybr[y+j][x+3] = clip8(Std.int(ybr[y+j][x+3]) + (a-d >> 3));
        }
    }
    
    function inverseDCT4DCOnly(y:Int, x:Int, coeffBase:Int):Void {
        var dc:Int = (Std.int(coeff[coeffBase+0]) + 4) >> 3;
        for (j in 0...4) {
            for (i in 0...4) {
                ybr[y+j][x+i] = clip8(Std.int(ybr[y+j][x+i]) + dc);
            }
        }
    }
    
    function inverseDCT8(y:Int, x:Int, coeffBase:Int):Void {
        inverseDCT4(y+0, x+0, coeffBase+0*16);
        inverseDCT4(y+0, x+4, coeffBase+1*16);
        inverseDCT4(y+4, x+0, coeffBase+2*16);
        inverseDCT4(y+4, x+4, coeffBase+3*16);
    }
    
    function inverseDCT8DCOnly(y:Int, x:Int, coeffBase:Int):Void {
        inverseDCT4DCOnly(y+0, x+0, coeffBase+0*16);
        inverseDCT4DCOnly(y+0, x+4, coeffBase+1*16);
        inverseDCT4DCOnly(y+4, x+0, coeffBase+2*16);
        inverseDCT4DCOnly(y+4, x+4, coeffBase+3*16);
    }
    
    function inverseWHT16():Void {
        var m:Array<Int> = [for (_ in 0...16) 0];
        
        for (i in 0...4) {
            var a0:Int = Std.int(coeff[384+0+i]) + Std.int(coeff[384+12+i]);
            var a1:Int = Std.int(coeff[384+4+i]) + Std.int(coeff[384+8+i]);
            var a2:Int = Std.int(coeff[384+4+i]) - Std.int(coeff[384+8+i]);
            var a3:Int = Std.int(coeff[384+0+i]) - Std.int(coeff[384+12+i]);
            
            m[0+i] = a0 + a1;
            m[8+i] = a0 - a1;
            m[4+i] = a3 + a2;
            m[12+i] = a3 - a2;
        }
    
        var out:Int = 0;
        for (i in 0...4) {
            var dc:Int = m[0+i*4] + 3;
            var a0:Int = dc + m[3+i*4];
            var a1:Int = m[1+i*4] + m[2+i*4];
            var a2:Int = m[1+i*4] - m[2+i*4];
            var a3:Int = dc - m[3+i*4];
            
            coeff[out+0] = Std.int((a0 + a1) >> 3);
            coeff[out+16] = Std.int((a3 + a2) >> 3);
            coeff[out+32] = Std.int((a0 - a1) >> 3);
            coeff[out+48] = Std.int((a3 - a2) >> 3);
            out += 64;
        }
    }

    static function clip8(i:Int):Int {
        return 
            i < 0 ? 0 : 
            i > 255 ? 255 : 
            Std.int(i);
    }
}