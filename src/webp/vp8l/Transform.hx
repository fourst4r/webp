package webp.vp8l;

import haxe.io.Bytes;
import Math.abs;

enum abstract TransformType(Int) {
    var Predictor = 0;
    var CrossColor = 1;
    var SubtractGreen = 2;
    var ColorIndexing = 3;
}

class Transform {
    public var oldWidth: Int;
    public var transformType: TransformType;
    public var bits: Int;
    public var pix: Bytes;
    public function new() {}
}

// nTiles returns the number of tiles needed to cover size pixels, where each
// tile's side is 1<<bits pixels long.
function nTiles(dim: Int, bits: Int): Int {
    return (dim + (1 << bits) - 1) >> bits;
}

final inverseTransforms = [
	inversePredictor,
	inverseCrossColor,
	inverseSubtractGreen,
	inverseColorIndexing,
];

function inversePredictor(t:Transform, pix:Bytes, h:Int):Bytes {
    if (t.oldWidth == 0 || h == 0) {
        return pix;
    }

    // The first pixel's predictor is mode 0 (opaque black)
    pix.set(3, pix.get(3) + 0xFF);

    var p = 4;
    var mask = (1 << t.bits) - 1;

    // Handle first row
    for (x in 1...t.oldWidth) {
        // The rest of the first row's predictor is mode 1 (L)
        pix.set(p + 0, pix.get(p + 0) + pix.get(p - 4));
        pix.set(p + 1, pix.get(p + 1) + pix.get(p - 3));
        pix.set(p + 2, pix.get(p + 2) + pix.get(p - 2));
        pix.set(p + 3, pix.get(p + 3) + pix.get(p - 1));
        p += 4;
    }

    var top = 0;
    var tilesPerRow = nTiles(t.oldWidth, t.bits);

    // Handle remaining rows
    for (y in 1...h) {
        // The first column's predictor is mode 2 (T)
        pix.set(p + 0, pix.get(p + 0) + pix.get(top + 0));
        pix.set(p + 1, pix.get(p + 1) + pix.get(top + 1));
        pix.set(p + 2, pix.get(p + 2) + pix.get(top + 2));
        pix.set(p + 3, pix.get(p + 3) + pix.get(top + 3));
        p += 4;
        top += 4;

        var q = 4 * (y >> t.bits) * tilesPerRow;
        var predictorMode = t.pix.get(q + 1) & 0x0F;
        q += 4;

        for (x in 1...t.oldWidth) {
            if ((x & mask) == 0) {
                predictorMode = t.pix.get(q + 1) & 0x0F;
                q += 4;
            }

            switch (predictorMode) {
                case 0: // Opaque black
                    pix.set(p + 3, pix.get(p + 3) + 0xFF);

                case 1: // L
                    pix.set(p + 0, pix.get(p + 0) + pix.get(p - 4));
                    pix.set(p + 1, pix.get(p + 1) + pix.get(p - 3));
                    pix.set(p + 2, pix.get(p + 2) + pix.get(p - 2));
                    pix.set(p + 3, pix.get(p + 3) + pix.get(p - 1));

                case 2: // T
                    pix.set(p + 0, pix.get(p + 0) + pix.get(top + 0));
                    pix.set(p + 1, pix.get(p + 1) + pix.get(top + 1));
                    pix.set(p + 2, pix.get(p + 2) + pix.get(top + 2));
                    pix.set(p + 3, pix.get(p + 3) + pix.get(top + 3));

                case 3: // TR
                    pix.set(p + 0, pix.get(p + 0) + pix.get(top + 4));
                    pix.set(p + 1, pix.get(p + 1) + pix.get(top + 5));
                    pix.set(p + 2, pix.get(p + 2) + pix.get(top + 6));
                    pix.set(p + 3, pix.get(p + 3) + pix.get(top + 7));

                case 4: // TL
                    pix.set(p + 0, pix.get(p + 0) + pix.get(top - 4));
                    pix.set(p + 1, pix.get(p + 1) + pix.get(top - 3));
                    pix.set(p + 2, pix.get(p + 2) + pix.get(top - 2));
                    pix.set(p + 3, pix.get(p + 3) + pix.get(top - 1));

                case 5: // Average2(Average2(L, TR), T)
                    pix.set(p + 0, pix.get(p + 0) + avg2(avg2(pix.get(p - 4), pix.get(top + 4)), pix.get(top + 0)));
                    pix.set(p + 1, pix.get(p + 1) + avg2(avg2(pix.get(p - 3), pix.get(top + 5)), pix.get(top + 1)));
                    pix.set(p + 2, pix.get(p + 2) + avg2(avg2(pix.get(p - 2), pix.get(top + 6)), pix.get(top + 2)));
                    pix.set(p + 3, pix.get(p + 3) + avg2(avg2(pix.get(p - 1), pix.get(top + 7)), pix.get(top + 3)));

                case 6: // Average2(L, TL)
                    pix.set(p + 0, pix.get(p + 0) + avg2(pix.get(p - 4), pix.get(top - 4)));
                    pix.set(p + 1, pix.get(p + 1) + avg2(pix.get(p - 3), pix.get(top - 3)));
                    pix.set(p + 2, pix.get(p + 2) + avg2(pix.get(p - 2), pix.get(top - 2)));
                    pix.set(p + 3, pix.get(p + 3) + avg2(pix.get(p - 1), pix.get(top - 1)));

                case 7: // Average2(L, T)
                    pix.set(p + 0, pix.get(p + 0) + avg2(pix.get(p - 4), pix.get(top + 0)));
                    pix.set(p + 1, pix.get(p + 1) + avg2(pix.get(p - 3), pix.get(top + 1)));
                    pix.set(p + 2, pix.get(p + 2) + avg2(pix.get(p - 2), pix.get(top + 2)));
                    pix.set(p + 3, pix.get(p + 3) + avg2(pix.get(p - 1), pix.get(top + 3)));

                case 8: // Average2(TL, T)
                    pix.set(p + 0, pix.get(p + 0) + avg2(pix.get(top - 4), pix.get(top + 0)));
                    pix.set(p + 1, pix.get(p + 1) + avg2(pix.get(top - 3), pix.get(top + 1)));
                    pix.set(p + 2, pix.get(p + 2) + avg2(pix.get(top - 2), pix.get(top + 2)));
                    pix.set(p + 3, pix.get(p + 3) + avg2(pix.get(top - 1), pix.get(top + 3)));

                case 9: // Average2(T, TR)
                    pix.set(p + 0, pix.get(p + 0) + avg2(pix.get(top + 0), pix.get(top + 4)));
                    pix.set(p + 1, pix.get(p + 1) + avg2(pix.get(top + 1), pix.get(top + 5)));
                    pix.set(p + 2, pix.get(p + 2) + avg2(pix.get(top + 2), pix.get(top + 6)));
                    pix.set(p + 3, pix.get(p + 3) + avg2(pix.get(top + 3), pix.get(top + 7)));

                case 10: // Average2(Average2(L, TL), Average2(T, TR))
                    pix.set(p + 0, pix.get(p + 0) + avg2(avg2(pix.get(p - 4), pix.get(top - 4)), avg2(pix.get(top + 0), pix.get(top + 4))));
                    pix.set(p + 1, pix.get(p + 1) + avg2(avg2(pix.get(p - 3), pix.get(top - 3)), avg2(pix.get(top + 1), pix.get(top + 5))));
                    pix.set(p + 2, pix.get(p + 2) + avg2(avg2(pix.get(p - 2), pix.get(top - 2)), avg2(pix.get(top + 2), pix.get(top + 6))));
                    pix.set(p + 3, pix.get(p + 3) + avg2(avg2(pix.get(p - 1), pix.get(top - 1)), avg2(pix.get(top + 3), pix.get(top + 7))));

                case 11: // Select(L, T, TL)
                    var l0 = pix.get(p - 4);
                    var l1 = pix.get(p - 3);
                    var l2 = pix.get(p - 2);
                    var l3 = pix.get(p - 1);
                    var c0 = pix.get(top - 4);
                    var c1 = pix.get(top - 3);
                    var c2 = pix.get(top - 2);
                    var c3 = pix.get(top - 1);
                    var t0 = pix.get(top + 0);
                    var t1 = pix.get(top + 1);
                    var t2 = pix.get(top + 2);
                    var t3 = pix.get(top + 3);
                    
                    var l = abs(c0 - t0) + abs(c1 - t1) + abs(c2 - t2) + abs(c3 - t3);
                    var t = abs(c0 - l0) + abs(c1 - l1) + abs(c2 - l2) + abs(c3 - l3);

                    if (l < t) {
                        pix.set(p + 0, pix.get(p + 0) + l0);
                        pix.set(p + 1, pix.get(p + 1) + l1);
                        pix.set(p + 2, pix.get(p + 2) + l2);
                        pix.set(p + 3, pix.get(p + 3) + l3);
                    } else {
                        pix.set(p + 0, pix.get(p + 0) + t0);
                        pix.set(p + 1, pix.get(p + 1) + t1);
                        pix.set(p + 2, pix.get(p + 2) + t2);
                        pix.set(p + 3, pix.get(p + 3) + t3);
                    }

                case 12: // ClampAddSubtractFull(L, T, TL)
                    pix.set(p + 0, pix.get(p + 0) + clampAddSubtractFull(pix.get(p - 4), pix.get(top + 0), pix.get(top - 4)));
                    pix.set(p + 1, pix.get(p + 1) + clampAddSubtractFull(pix.get(p - 3), pix.get(top + 1), pix.get(top - 3)));
                    pix.set(p + 2, pix.get(p + 2) + clampAddSubtractFull(pix.get(p - 2), pix.get(top + 2), pix.get(top - 2)));
                    pix.set(p + 3, pix.get(p + 3) + clampAddSubtractFull(pix.get(p - 1), pix.get(top + 3), pix.get(top - 1)));

                case 13: // ClampAddSubtractHalf(Average2(L, T), TL)
                    pix.set(p + 0, pix.get(p + 0) + clampAddSubtractHalf(avg2(pix.get(p - 4), pix.get(top + 0)), pix.get(top - 4)));
                    pix.set(p + 1, pix.get(p + 1) + clampAddSubtractHalf(avg2(pix.get(p - 3), pix.get(top + 1)), pix.get(top - 3)));
                    pix.set(p + 2, pix.get(p + 2) + clampAddSubtractHalf(avg2(pix.get(p - 2), pix.get(top + 2)), pix.get(top - 2)));
                    pix.set(p + 3, pix.get(p + 3) + clampAddSubtractHalf(avg2(pix.get(p - 1), pix.get(top + 3)), pix.get(top - 1)));
            }
            p += 4;
            top += 4;
        }
    }
    return pix;
}

function inverseCrossColor(t:Transform, pix:Bytes, h:Int):Bytes {
    var greenToRed:Int = 0, greenToBlue:Int = 0, redToBlue:Int = 0;
    var p:Int = 0, mask:Int = (1 << t.bits) - 1, tilesPerRow:Int = nTiles(t.oldWidth, t.bits);
    
    function uint8ToInt8(x: Int): Int {
        return (x & 0xFF) >= 0x80 ? (x & 0xFF) - 0x100 : (x & 0xFF);
    }

    for (y in 0...h) {
        var q:Int = 4 * ((y >> t.bits) * tilesPerRow);
        for (x in 0...t.oldWidth) {
            if ((x & mask) == 0) {
                redToBlue = uint8ToInt8(t.pix.get(q + 0));
                greenToBlue = uint8ToInt8(t.pix.get(q + 1));
                greenToRed = uint8ToInt8(t.pix.get(q + 2));
                q += 4;
            }

            var red:Int = pix.get(p + 0);
            var green:Int = pix.get(p + 1);
            var blue:Int = pix.get(p + 2);

            red += ((greenToRed * uint8ToInt8(green)) >>> 5);
            blue += ((greenToBlue * uint8ToInt8(green)) >>> 5);
            blue = (blue & 0xff) + ((redToBlue * uint8ToInt8(red)) >>> 5);

            pix.set(p + 0, red);
            pix.set(p + 2, blue);
            p += 4;
        }
    }
    return pix;
}


function inverseSubtractGreen(t:Transform, pix:Bytes, h:Int):Bytes {
    var p = 0;
    while (p < pix.length) {
        var green = pix.get(p + 1);
        pix.set(p+0, pix.get(p+0) + green);
        pix.set(p+2, pix.get(p+2) + green);
        p += 4;
    }
    return pix;
}

function inverseColorIndexing(t:Transform, pix:Bytes, h:Int):Bytes {
    if (t.bits == 0) {
        var p = 0;
        while (p < pix.length) {
            var i = 4 * pix.get(p + 1);
            pix.set(p + 0, t.pix.get(i + 0));
            pix.set(p + 1, t.pix.get(i + 1));
            pix.set(p + 2, t.pix.get(i + 2));
            pix.set(p + 3, t.pix.get(i + 3));
            p += 4;
        }
        return pix;
    }

    var vMask = 0, xMask = 0, bitsPerPixel = Std.int(8 >> t.bits);
    switch (t.bits) {
        case 1:
            vMask = 0x0f; xMask = 0x01;
        case 2:
            vMask = 0x03; xMask = 0x03;
        case 3:
            vMask = 0x01; xMask = 0x07;
    }

    var d = 0, p = 0, v = 0;
    var dst = Bytes.alloc(4 * t.oldWidth * h);

    for (y in 0...h) {
        for (x in 0...t.oldWidth) {
            if ((x & xMask) == 0) {
                v = pix.get(p + 1);
                p += 4;
            }

            var i = 4 * (v & vMask);
            dst.set(d + 0, t.pix.get(i + 0));
            dst.set(d + 1, t.pix.get(i + 1));
            dst.set(d + 2, t.pix.get(i + 2));
            dst.set(d + 3, t.pix.get(i + 3));
            d += 4;

            v >>>= bitsPerPixel;
        }
    }
    return dst;
}

function avg2(a:Int, b:Int):Int {
    return Std.int((a + b) / 2) & 0xff;
}

function clampAddSubtractFull(a:Int, b:Int, c:Int):Int {
    var x = a + b - c;
    return x < 0 ? 0 : (x > 255 ? 255 : x);
}

function clampAddSubtractHalf(a:Int, b:Int):Int {
    var x = a + Std.int((a - b) / 2);
    return x < 0 ? 0 : (x > 255 ? 255 : x);
}
