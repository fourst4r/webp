// Copyright 2014 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.
package webp.vp8;

typedef FilterParam = {
	var level:Int;
	var ilevel:Int;
	var hlevel:Int;
	var inner:Bool;
}

private inline function abs(x:Int):Int {
    return if (x < 0) -x else x;
}

private inline function clamp127(x:Int):Int {
    return if (x < -127) -127 else if (x > 127) 127 else x;
}

private inline function clamp15(x:Int):Int {
    return if (x < -15) -15 else if (x > 15) 15 else x;
}

private inline function clamp255(x:Int):Int {
    return if (x < 0) 0 else if (x > 255) 255 else x;
}

// Modifies a 2-pixel wide or 2-pixel high band along an edge.
function filter2(pix:Array<Int>, level:Int, index:Int, iStep:Int, jStep:Int):Void {
    for (n in 0...16) {
        var p1 = pix[index - 2 * jStep];
        var p0 = pix[index - 1 * jStep];
        var q0 = pix[index + 0 * jStep];
        var q1 = pix[index + 1 * jStep];

        if ((abs(p0 - q0) << 1) + (abs(p1 - q1) >> 1) > level) {
            index += iStep;
            continue;
        }

        var a = 3 * (q0 - p0) + clamp127(p1 - q1);
        var a1 = clamp15((a + 4) >> 3);
        var a2 = clamp15((a + 3) >> 3);

        pix[index - 1 * jStep] = clamp255(p0 + a2);
        pix[index + 0 * jStep] = clamp255(q0 - a1);

        index += iStep;
    }
}

// Modifies a 2-, 4-, or 6-pixel wide or high band along an edge.
function filter246(pix:Array<Int>, n:Int, level:Int, ilevel:Int, hlevel:Int, index:Int, iStep:Int, jStep:Int, fourNotSix:Bool):Void {
    while (n > 0) {
        var p3 = pix[index - 4 * jStep];
        var p2 = pix[index - 3 * jStep];
        var p1 = pix[index - 2 * jStep];
        var p0 = pix[index - 1 * jStep];
        var q0 = pix[index + 0 * jStep];
        var q1 = pix[index + 1 * jStep];
        var q2 = pix[index + 2 * jStep];
        var q3 = pix[index + 3 * jStep];

        if ((abs(p0 - q0) << 1) + (abs(p1 - q1) >> 1) > level ||
            abs(p3 - p2) > ilevel || abs(p2 - p1) > ilevel || abs(p1 - p0) > ilevel ||
            abs(q1 - q0) > ilevel || abs(q2 - q1) > ilevel || abs(q3 - q2) > ilevel) {
            index += iStep;
            n--;
            continue;
        }

        if (abs(p1 - p0) > hlevel || abs(q1 - q0) > hlevel) {
            // Filter 2 pixels
            var a = 3 * (q0 - p0) + clamp127(p1 - q1);
            var a1 = clamp15((a + 4) >> 3);
            var a2 = clamp15((a + 3) >> 3);

            pix[index - 1 * jStep] = clamp255(p0 + a2);
            pix[index + 0 * jStep] = clamp255(q0 - a1);

        } else if (fourNotSix) {
            // Filter 4 pixels
            var a = 3 * (q0 - p0);
            var a1 = clamp15((a + 4) >> 3);
            var a2 = clamp15((a + 3) >> 3);
            var a3 = (a1 + 1) >> 1;

            pix[index - 2 * jStep] = clamp255(p1 + a3);
            pix[index - 1 * jStep] = clamp255(p0 + a2);
            pix[index + 0 * jStep] = clamp255(q0 - a1);
            pix[index + 1 * jStep] = clamp255(q1 - a3);

        } else {
            // Filter 6 pixels
            var a = clamp127(3 * (q0 - p0) + clamp127(p1 - q1));
            var a1 = (27 * a + 63) >> 7;
            var a2 = (18 * a + 63) >> 7;
            var a3 = (9 * a + 63) >> 7;

            pix[index - 3 * jStep] = clamp255(p2 + a3);
            pix[index - 2 * jStep] = clamp255(p1 + a2);
            pix[index - 1 * jStep] = clamp255(p0 + a1);
            pix[index + 0 * jStep] = clamp255(q0 - a1);
            pix[index + 1 * jStep] = clamp255(q1 - a2);
            pix[index + 2 * jStep] = clamp255(q2 - a3);
        }

        index += iStep;
        n--;
    }
}