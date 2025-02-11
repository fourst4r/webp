package webp.vp8;

import haxe.io.Bytes;

final uniformProb:Int = 128;

class Partition {
    public var buf:Bytes;
    public var r:Int = 0;
    public var rangeM1:Int = 254;
    public var bits:Int = 0;
    public var nBits:Int = 0;
    public var unexpectedEOF:Bool = false;

    static var lutShift:Array<Int> = [
        7, 6, 6, 5, 5, 5, 5, 4, 4, 4, 4, 4, 4, 4, 4,
        3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3, 3,
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2, 2,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
        1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 1,
    ];

    static var lutRangeM1:Array<Int> = [
        127, 127, 191, 127, 159, 191, 223,
        127, 143, 159, 175, 191, 207, 223, 239,
        127, 135, 143, 151, 159, 167, 175, 183, 191, 199, 207, 215, 223, 231, 239, 247,
        127, 131, 135, 139, 143, 147, 151, 155, 159, 163, 167, 171, 175, 179, 183, 187,
        191, 195, 199, 203, 207, 211, 215, 219, 223, 227, 231, 235, 239, 243, 247, 251,
        127, 129, 131, 133, 135, 137, 139, 141, 143, 145, 147, 149, 151, 153, 155, 157,
        159, 161, 163, 165, 167, 169, 171, 173, 175, 177, 179, 181, 183, 185, 187, 189,
        191, 193, 195, 197, 199, 201, 203, 205, 207, 209, 211, 213, 215, 217, 219, 221,
        223, 225, 227, 229, 231, 233, 235, 237, 239, 241, 243, 245, 247, 249, 251, 253
    ];

    public function new(buf:Bytes) {
		init(buf);
	}

    // Initialize the partition
	public function init(buf:Bytes):Void {
		this.buf = buf;
		this.r = 0;
		this.rangeM1 = 254;
		this.bits = 0;
		this.nBits = 0;
		this.unexpectedEOF = false;
	}

    // Read the next bit
	public function readBit(prob:Int):Bool {
		if (nBits < 8) {
			if (r >= buf.length) {
				unexpectedEOF = true;
				return false;
			}
			// Fetch next byte from buf
			var x = buf.get(r);
			bits |= x << (8 - nBits);
			r++;
			nBits += 8;
		}

		var split = ((rangeM1 * prob) >> 8) + 1;
		var bit = bits >= (split << 8);
		if (bit) {
			rangeM1 -= split;
			bits -= split << 8;
		} else {
			rangeM1 = split - 1;
		}

		if (rangeM1 < 127) {
			var shift = lutShift[rangeM1];
			rangeM1 = lutRangeM1[rangeM1];
			bits <<= shift;
			nBits -= shift;
		}

		return bit;
	}

    // Read an n-bit unsigned integer
	public function readUint(prob:Int, n:Int):Int {
		var u = 0;
		for (i in 0...n) {
			if (readBit(prob)) {
				u |= 1 << (n - i - 1);
			}
		}
		return u;
	}

    // Read an n-bit signed integer
	public function readInt(prob:Int, n:Int):Int {
		var u = readUint(prob, n);
		var b = readBit(prob);
		if (b) return -u;
		return u;
	}

    // Read an optional signed integer where the likely result is zero
	public function readOptionalInt(prob:Int, n:Int):Int {
		if (!readBit(prob)) {
			return 0;
		}
		return readInt(prob, n);
	}
}