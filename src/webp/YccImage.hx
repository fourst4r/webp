package webp;

import haxe.io.Bytes;

private typedef Rect = {
	minX:Int,
	minY:Int,
	maxX:Int,
	maxY:Int
}

class YccImage {
	public var Y:Bytes;
	public var Cb:Bytes;
	public var Cr:Bytes;
	public var YStride:Int;
	public var CStride:Int;
	public var rect:Rect;

	function new() {
	}

	public static function blank(width:Int, height:Int) {
		final img = new YccImage();
		img.rect = {
			minX: 0,
			minY: 0,
			maxX: width,
			maxY: height
		};
		img.YStride = width;
		img.CStride = width >> 1;

		// Allocate buffers filled with zero bytes.
		img.Y = Bytes.alloc(img.YStride * height);
		img.Cb = Bytes.alloc(img.CStride * (height >> 1));
		img.Cr = Bytes.alloc(img.CStride * (height >> 1));
		return img;
	}

	public function subImage(x:Int, y:Int, width:Int, height:Int):YccImage {
		final minX = x;
		final maxX = width - x;
		final minY = y;
		final maxY = height - y;

		var yi = yoffset(minX, minY);
		var ci = coffset(minX, minY);
		final sub = new YccImage();
		sub.Y = Y.sub(yi, Y.length-yi);
		sub.Cb = Cb.sub(ci, Cb.length-ci);
		sub.Cr = Cr.sub(ci, Cr.length-ci);
		sub.YStride = YStride;
		sub.CStride = CStride;
		sub.rect = {
			minX: minX,
			maxX: maxX,
			minY: minY,
			maxY: maxY,
		};
		// return &YCbCr{
		// 	Y:              p.Y[yi:],
		// 	Cb:             p.Cb[ci:],
		// 	Cr:             p.Cr[ci:],
		// 	SubsampleRatio: p.SubsampleRatio,
		// 	YStride:        p.YStride,
		// 	CStride:        p.CStride,
		// 	Rect:           r,
		// }
		return sub;
	}

	inline function yoffset(x:Int, y:Int):Int {
		return (y-rect.minY)*YStride + (x - rect.minX);
	}

	inline function coffset(x:Int, y:Int):Int {
		// Note this only works for 4:2:0, TODO: update for more subsample ratios
		return (Std.int(y/2)-Std.int(rect.minY/2))*CStride + (Std.int(x/2) - Std.int(rect.minX/2));
	}
}