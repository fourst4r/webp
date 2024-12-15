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
}