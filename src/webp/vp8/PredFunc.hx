package webp.vp8;

// This file implements the predicition functions, as specified in chapter 12.
//
// For each macroblock (of 1x16x16 luma and 2x8x8 chroma coefficients), the
// luma values are either predicted as one large 16x16 region or 16 separate
// 4x4 regions. The chroma values are always predicted as one 8x8 region.
//
// For 4x4 regions, the target block's predicted values (Xs) are a function of
// its previously-decoded top and left border values, as well as a number of
// pixels from the top-right:
//
//	a b c d e f g h
//	p X X X X
//	q X X X X
//	r X X X X
//	s X X X X
//
// The predictor modes are:
//	- DC: all Xs = (b + c + d + e + p + q + r + s + 4) / 8.
//	- TM: the first X = (b + p - a), the second X = (c + p - a), and so on.
//	- VE: each X = the weighted average of its column's top value and that
//	      value's neighbors, i.e. averages of abc, bcd, cde or def.
//	- HE: similar to VE except rows instead of columns, and the final row is
//	      an average of r, s and s.
//	- RD, VR, LD, VL, HD, HU: these diagonal modes ("Right Down", "Vertical
//	      Right", etc) are more complicated and are described in section 12.3.
// All Xs are clipped to the range [0, 255].
//
// For 8x8 and 16x16 regions, the target block's predicted values are a
// function of the top and left border values without the top-right overhang,
// i.e. without the 8x8 or 16x16 equivalent of f, g and h. Furthermore:
//	- There are no diagonal predictor modes, only DC, TM, VE and HE.
//	- The DC mode has variants for macroblocks in the top row and/or left
//	  column, i.e. for macroblocks with mby == 0 || mbx == 0.
//	- The VE and HE modes take only the column top or row left values; they do
//	  not smooth that top/left value with its neighbors.

// nPred is the number of predictor modes, not including the Top/Left versions
// of the DC predictor mode.
final nPred = 10;

final predDC = 0;
final predTM = 1;
final predVE = 2;
final predHE = 3;
final predRD = 4;
final predVR = 5;
final predLD = 6;
final predVL = 7;
final predHD = 8;
final predHU = 9;
final predDCTop = 10;
final predDCLeft = 11;
final predDCTopLeft = 12;

function checkTopLeftPred(mbx: Int, mby: Int, p: Int): Int {
    if (p != predDC) return p;
    
    if (mbx == 0) {
        if (mby == 0) return predDCTopLeft;
        return predDCLeft;
    }
    
    if (mby == 0) return predDCTop;
    
    return predDC;
}

final predFunc4 = /*[...]func(*Vp8Decoder, int, int)*/[
	predFunc4DC,
	predFunc4TM,
	predFunc4VE,
	predFunc4HE,
	predFunc4RD,
	predFunc4VR,
	predFunc4LD,
	predFunc4VL,
	predFunc4HD,
	predFunc4HU,
	null,
	null,
	null,
];

final predFunc8 = /*[...]func(*Vp8Decoder, int, int)*/[
	predFunc8DC,
	predFunc8TM,
	predFunc8VE,
	predFunc8HE,
	null,
	null,
	null,
	null,
	null,
	null,
	predFunc8DCTop,
	predFunc8DCLeft,
	predFunc8DCTopLeft,
];

final predFunc16 = /*[...]func(*Vp8Decoder, int, int)*/[
	predFunc16DC,
	predFunc16TM,
	predFunc16VE,
	predFunc16HE,
	null,
	null,
	null,
	null,
	null,
	null,
	predFunc16DCTop,
	predFunc16DCLeft,
	predFunc16DCTopLeft,
];

function predFunc4DC(z: Vp8Decoder, y: Int, x: Int): Void {
    var sum: Int = 4;
    for (i in 0...4) {
        sum += z.ybr[y - 1][x + i];
    }
    for (j in 0...4) {
        sum += z.ybr[y + j][x - 1];
    }
    
    var avg = Std.int(sum / 8);
    for (j in 0...4) {
        for (i in 0...4) {
            z.ybr[y + j][x + i] = avg;
        }
    }
}

function predFunc4TM(z: Vp8Decoder, y: Int, x: Int): Void {
    var delta0 = -z.ybr[y - 1][x - 1];
    for (j in 0...4) {
        var delta1 = delta0 + z.ybr[y + j][x - 1];
        for (i in 0...4) {
            var delta2 = delta1 + z.ybr[y - 1][x + i];
            z.ybr[y + j][x + i] = clip(delta2, 0, 255);
        }
    }
}

function predFunc4VE(z: Vp8Decoder, y: Int, x: Int): Void {
    var a = z.ybr[y - 1][x - 1];
    var b = z.ybr[y - 1][x + 0];
    var c = z.ybr[y - 1][x + 1];
    var d = z.ybr[y - 1][x + 2];
    var e = z.ybr[y - 1][x + 3];
    var f = z.ybr[y - 1][x + 4];
    
    var abc = Std.int((a + 2 * b + c + 2) / 4);
    var bcd = Std.int((b + 2 * c + d + 2) / 4);
    var cde = Std.int((c + 2 * d + e + 2) / 4);
    var def = Std.int((d + 2 * e + f + 2) / 4);
    
    for (j in 0...4) {
        z.ybr[y + j][x + 0] = abc;
        z.ybr[y + j][x + 1] = bcd;
        z.ybr[y + j][x + 2] = cde;
        z.ybr[y + j][x + 3] = def;
    }
}

function predFunc4HE(z: Vp8Decoder, y: Int, x: Int): Void {
    var s = z.ybr[y + 3][x - 1];
    var r = z.ybr[y + 2][x - 1];
    var q = z.ybr[y + 1][x - 1];
    var p = z.ybr[y + 0][x - 1];
    var a = z.ybr[y - 1][x - 1];
    
    var ssr = Std.int((s + 2 * s + r + 2) / 4);
    var srq = Std.int((s + 2 * r + q + 2) / 4);
    var rqp = Std.int((r + 2 * q + p + 2) / 4);
    var apq = Std.int((a + 2 * p + q + 2) / 4);
    
    for (i in 0...4) {
        z.ybr[y + 0][x + i] = apq;
        z.ybr[y + 1][x + i] = rqp;
        z.ybr[y + 2][x + i] = srq;
        z.ybr[y + 3][x + i] = ssr;
    }
}

function predFunc4RD(z: Vp8Decoder, y: Int, x: Int): Void {
    var s = z.ybr[y + 3][x - 1];
    var r = z.ybr[y + 2][x - 1];
    var q = z.ybr[y + 1][x - 1];
    var p = z.ybr[y + 0][x - 1];
    var a = z.ybr[y - 1][x - 1];
    var b = z.ybr[y - 1][x + 0];
    var c = z.ybr[y - 1][x + 1];
    var d = z.ybr[y - 1][x + 2];
    var e = z.ybr[y - 1][x + 3];
    
    var srq = Std.int((s + 2 * r + q + 2) / 4);
    var rqp = Std.int((r + 2 * q + p + 2) / 4);
    var qpa = Std.int((q + 2 * p + a + 2) / 4);
    var pab = Std.int((p + 2 * a + b + 2) / 4);
    var abc = Std.int((a + 2 * b + c + 2) / 4);
    var bcd = Std.int((b + 2 * c + d + 2) / 4);
    var cde = Std.int((c + 2 * d + e + 2) / 4);
    
    z.ybr[y + 0][x + 0] = pab;
    z.ybr[y + 0][x + 1] = abc;
    z.ybr[y + 0][x + 2] = bcd;
    z.ybr[y + 0][x + 3] = cde;
    
    z.ybr[y + 1][x + 0] = qpa;
    z.ybr[y + 1][x + 1] = pab;
    z.ybr[y + 1][x + 2] = abc;
    z.ybr[y + 1][x + 3] = bcd;
    
    z.ybr[y + 2][x + 0] = rqp;
    z.ybr[y + 2][x + 1] = qpa;
    z.ybr[y + 2][x + 2] = pab;
    z.ybr[y + 2][x + 3] = abc;
    
    z.ybr[y + 3][x + 0] = srq;
    z.ybr[y + 3][x + 1] = rqp;
    z.ybr[y + 3][x + 2] = qpa;
    z.ybr[y + 3][x + 3] = pab;
}

function predFunc4VR(z:Vp8Decoder, y:Int, x:Int):Void {
    var r = z.ybr[y+2][x-1];
    var q = z.ybr[y+1][x-1];
    var p = z.ybr[y+0][x-1];
    var a = z.ybr[y-1][x-1];
    var b = z.ybr[y-1][x+0];
    var c = z.ybr[y-1][x+1];
    var d = z.ybr[y-1][x+2];
    var e = z.ybr[y-1][x+3];

    var ab = Std.int((a + b + 1) / 2);
    var bc = Std.int((b + c + 1) / 2);
    var cd = Std.int((c + d + 1) / 2);
    var de = Std.int((d + e + 1) / 2);

    var rqp = Std.int((r + 2 * q + p + 2) / 4);
    var qpa = Std.int((q + 2 * p + a + 2) / 4);
    var pab = Std.int((p + 2 * a + b + 2) / 4);
    var abc = Std.int((a + 2 * b + c + 2) / 4);
    var bcd = Std.int((b + 2 * c + d + 2) / 4);
    var cde = Std.int((c + 2 * d + e + 2) / 4);

    z.ybr[y+0][x+0] = ab;
    z.ybr[y+0][x+1] = bc;
    z.ybr[y+0][x+2] = cd;
    z.ybr[y+0][x+3] = de;

    z.ybr[y+1][x+0] = pab;
    z.ybr[y+1][x+1] = abc;
    z.ybr[y+1][x+2] = bcd;
    z.ybr[y+1][x+3] = cde;

    z.ybr[y+2][x+0] = qpa;
    z.ybr[y+2][x+1] = ab;
    z.ybr[y+2][x+2] = bc;
    z.ybr[y+2][x+3] = cd;

    z.ybr[y+3][x+0] = rqp;
    z.ybr[y+3][x+1] = pab;
    z.ybr[y+3][x+2] = abc;
    z.ybr[y+3][x+3] = bcd;
}

function predFunc4LD(z:Vp8Decoder, y:Int, x:Int):Void {
    var a = z.ybr[y-1][x+0];
    var b = z.ybr[y-1][x+1];
    var c = z.ybr[y-1][x+2];
    var d = z.ybr[y-1][x+3];
    var e = z.ybr[y-1][x+4];
    var f = z.ybr[y-1][x+5];
    var g = z.ybr[y-1][x+6];
    var h = z.ybr[y-1][x+7];

    var abc = Std.int((a + 2 * b + c + 2) / 4);
    var bcd = Std.int((b + 2 * c + d + 2) / 4);
    var cde = Std.int((c + 2 * d + e + 2) / 4);
    var def = Std.int((d + 2 * e + f + 2) / 4);
    var efg = Std.int((e + 2 * f + g + 2) / 4);
    var fgh = Std.int((f + 2 * g + h + 2) / 4);
    var ghh = Std.int((g + 2 * h + h + 2) / 4);

    z.ybr[y+0][x+0] = abc;
    z.ybr[y+0][x+1] = bcd;
    z.ybr[y+0][x+2] = cde;
    z.ybr[y+0][x+3] = def;

    z.ybr[y+1][x+0] = bcd;
    z.ybr[y+1][x+1] = cde;
    z.ybr[y+1][x+2] = def;
    z.ybr[y+1][x+3] = efg;

    z.ybr[y+2][x+0] = cde;
    z.ybr[y+2][x+1] = def;
    z.ybr[y+2][x+2] = efg;
    z.ybr[y+2][x+3] = fgh;

    z.ybr[y+3][x+0] = def;
    z.ybr[y+3][x+1] = efg;
    z.ybr[y+3][x+2] = fgh;
    z.ybr[y+3][x+3] = ghh;
}

function predFunc4VL(z: Vp8Decoder, y:Int, x:Int):Void {
    var a = z.ybr[y-1][x+0];
    var b = z.ybr[y-1][x+1];
    var c = z.ybr[y-1][x+2];
    var d = z.ybr[y-1][x+3];
    var e = z.ybr[y-1][x+4];
    var f = z.ybr[y-1][x+5];
    var g = z.ybr[y-1][x+6];
    var h = z.ybr[y-1][x+7];
    
    var ab = Std.int((a + b + 1) / 2);
    var bc = Std.int((b + c + 1) / 2);
    var cd = Std.int((c + d + 1) / 2);
    var de = Std.int((d + e + 1) / 2);
    
    var abc = Std.int((a + 2 * b + c + 2) / 4);
    var bcd = Std.int((b + 2 * c + d + 2) / 4);
    var cde = Std.int((c + 2 * d + e + 2) / 4);
    var def = Std.int((d + 2 * e + f + 2) / 4);
    var efg = Std.int((e + 2 * f + g + 2) / 4);
    var fgh = Std.int((f + 2 * g + h + 2) / 4);
    
    z.ybr[y+0][x+0] = ab;
    z.ybr[y+0][x+1] = bc;
    z.ybr[y+0][x+2] = cd;
    z.ybr[y+0][x+3] = de;
    z.ybr[y+1][x+0] = abc;
    z.ybr[y+1][x+1] = bcd;
    z.ybr[y+1][x+2] = cde;
    z.ybr[y+1][x+3] = def;
    z.ybr[y+2][x+0] = bc;
    z.ybr[y+2][x+1] = cd;
    z.ybr[y+2][x+2] = de;
    z.ybr[y+2][x+3] = efg;
    z.ybr[y+3][x+0] = bcd;
    z.ybr[y+3][x+1] = cde;
    z.ybr[y+3][x+2] = def;
    z.ybr[y+3][x+3] = fgh;
}

function predFunc4HD(z: Vp8Decoder, y:Int, x:Int):Void {
    var s = z.ybr[y+3][x-1];
    var r = z.ybr[y+2][x-1];
    var q = z.ybr[y+1][x-1];
    var p = z.ybr[y+0][x-1];
    var a = z.ybr[y-1][x-1];
    var b = z.ybr[y-1][x+0];
    var c = z.ybr[y-1][x+1];
    var d = z.ybr[y-1][x+2];
    
    var sr = Std.int((s + r + 1) / 2);
    var rq = Std.int((r + q + 1) / 2);
    var qp = Std.int((q + p + 1) / 2);
    var pa = Std.int((p + a + 1) / 2);
    
    var srq = Std.int((s + 2 * r + q + 2) / 4);
    var rqp = Std.int((r + 2 * q + p + 2) / 4);
    var qpa = Std.int((q + 2 * p + a + 2) / 4);
    var pab = Std.int((p + 2 * a + b + 2) / 4);
    var abc = Std.int((a + 2 * b + c + 2) / 4);
    var bcd = Std.int((b + 2 * c + d + 2) / 4);
    
    z.ybr[y+0][x+0] = pa;
    z.ybr[y+0][x+1] = pab;
    z.ybr[y+0][x+2] = abc;
    z.ybr[y+0][x+3] = bcd;
    z.ybr[y+1][x+0] = qp;
    z.ybr[y+1][x+1] = qpa;
    z.ybr[y+1][x+2] = pa;
    z.ybr[y+1][x+3] = pab;
    z.ybr[y+2][x+0] = rq;
    z.ybr[y+2][x+1] = rqp;
    z.ybr[y+2][x+2] = qp;
    z.ybr[y+2][x+3] = qpa;
    z.ybr[y+3][x+0] = sr;
    z.ybr[y+3][x+1] = srq;
    z.ybr[y+3][x+2] = rq;
    z.ybr[y+3][x+3] = rqp;
}

function predFunc4HU(z:Vp8Decoder, y:Int, x:Int):Void {
    var s:Int = z.ybr[y+3][x-1];
    var r:Int = z.ybr[y+2][x-1];
    var q:Int = z.ybr[y+1][x-1];
    var p:Int = z.ybr[y+0][x-1];
    var pq:Int = Std.int((p + q + 1) / 2);
    var qr:Int = Std.int((q + r + 1) / 2);
    var rs:Int = Std.int((r + s + 1) / 2);
    var pqr:Int = Std.int((p + 2*q + r + 2) / 4);
    var qrs:Int = Std.int((q + 2*r + s + 2) / 4);
    var rss:Int = Std.int((r + 2*s + s + 2) / 4);
    var sss:Int = s;

    z.ybr[y+0][x+0] = pq;
    z.ybr[y+0][x+1] = pqr;
    z.ybr[y+0][x+2] = qr;
    z.ybr[y+0][x+3] = qrs;
    z.ybr[y+1][x+0] = qr;
    z.ybr[y+1][x+1] = qrs;
    z.ybr[y+1][x+2] = rs;
    z.ybr[y+1][x+3] = rss;
    z.ybr[y+2][x+0] = rs;
    z.ybr[y+2][x+1] = rss;
    z.ybr[y+2][x+2] = sss;
    z.ybr[y+2][x+3] = sss;
    z.ybr[y+3][x+0] = sss;
    z.ybr[y+3][x+1] = sss;
    z.ybr[y+3][x+2] = sss;
    z.ybr[y+3][x+3] = sss;
}

function predFunc8DC(z:Vp8Decoder, y:Int, x:Int):Void {
    var sum:Int = 8;
    for (i in 0...8) {
        sum += z.ybr[y-1][x+i];
    }
    for (j in 0...8) {
        sum += z.ybr[y+j][x-1];
    }
    var avg:Int = Std.int(sum / 16);
    for (j in 0...8) {
        for (i in 0...8) {
            z.ybr[y+j][x+i] = avg;
        }
    }
}

function predFunc8TM(z:Vp8Decoder, y:Int, x:Int):Void {
    var delta0:Int = -z.ybr[y-1][x-1];
    for (j in 0...8) {
        var delta1:Int = delta0 + z.ybr[y+j][x-1];
        for (i in 0...8) {
            var delta2:Int = delta1 + z.ybr[y-1][x+i];
            z.ybr[y+j][x+i] = Std.int(clip(delta2, 0, 255));
        }
    }
}

function predFunc8VE(z:Vp8Decoder, y:Int, x:Int):Void {
    for (j in 0...8) {
        for (i in 0...8) {
            z.ybr[y+j][x+i] = z.ybr[y-1][x+i];
        }
    }
}

function predFunc8HE(z:Vp8Decoder, y:Int, x:Int):Void {
    for (j in 0...8) {
        for (i in 0...8) {
            z.ybr[y+j][x+i] = z.ybr[y+j][x-1];
        }
    }
}

function predFunc8DCTop(z:Vp8Decoder, y:Int, x:Int):Void {
    var sum:Int = 4;
    for (j in 0...8) {
        sum += z.ybr[y+j][x-1];
    }
    var avg:Int = Std.int(sum / 8);
    for (j in 0...8) {
        for (i in 0...8) {
            z.ybr[y+j][x+i] = avg;
        }
    }
}

function predFunc8DCLeft(z:Vp8Decoder, y:Int, x:Int):Void {
    var sum:Int = 4;
    for (i in 0...8) {
        sum += z.ybr[y-1][x+i];
    }
    var avg:Int = Std.int(sum / 8);
    for (j in 0...8) {
        for (i in 0...8) {
            z.ybr[y+j][x+i] = avg;
        }
    }
}

function predFunc8DCTopLeft(z:Vp8Decoder, y:Int, x:Int):Void {
    for (j in 0...8) {
        for (i in 0...8) {
            z.ybr[y+j][x+i] = 0x80;
        }
    }
}

function predFunc16DC(z:Vp8Decoder, y:Int, x:Int):Void {
    var sum:Int = 16;
    for (i in 0...16) {
        sum += z.ybr[y-1][x+i];
    }
    for (j in 0...16) {
        sum += z.ybr[y+j][x-1];
    }
    var avg:Int = Std.int(sum / 32);
    for (j in 0...16) {
        for (i in 0...16) {
            z.ybr[y+j][x+i] = avg;
        }
    }
}

function predFunc16TM(z:Vp8Decoder, y:Int, x:Int):Void {
    var delta0:Int = -z.ybr[y-1][x-1];
    for (j in 0...16) {
        var delta1:Int = delta0 + z.ybr[y+j][x-1];
        for (i in 0...16) {
            var delta2:Int = delta1 + z.ybr[y-1][x+i];
            z.ybr[y+j][x+i] = Std.int(clip(delta2, 0, 255));
        }
    }
}

function predFunc16VE(z:Vp8Decoder, y:Int, x:Int):Void {
    for (j in 0...16) {
        for (i in 0...16) {
            z.ybr[y+j][x+i] = z.ybr[y-1][x+i];
        }
    }
}

function predFunc16HE(z:Vp8Decoder, y:Int, x:Int):Void {
    for (j in 0...16) {
        for (i in 0...16) {
            z.ybr[y+j][x+i] = z.ybr[y+j][x-1];
        }
    }
}

function predFunc16DCTop(z:Vp8Decoder, y:Int, x:Int):Void {
    var sum:Int = 8;
    for (j in 0...16) {
        sum += z.ybr[y+j][x-1];
    }
    var avg:Int = Std.int(sum / 16);
    for (j in 0...16) {
        for (i in 0...16) {
            z.ybr[y+j][x+i] = avg;
        }
    }
}

function predFunc16DCLeft(z:Vp8Decoder, y:Int, x:Int):Void {
    var sum:Int = 8;
    for (i in 0...16) {
        sum += z.ybr[y-1][x+i];
    }
    var avg:Int = Std.int(sum / 16);
    for (j in 0...16) {
        for (i in 0...16) {
            z.ybr[y+j][x+i] = avg;
        }
    }
}

function predFunc16DCTopLeft(z:Vp8Decoder, y:Int, x:Int):Void {
    for (j in 0...16) {
        for (i in 0...16) {
            z.ybr[y+j][x+i] = 0x80;
        }
    }
}

private function clip(value: Int, min: Int, max: Int): Int {
    return value < min ? min : (value > max ? max : value);
}

