package webp.vp8l;

import webp.vp8l.Vp8LDecoder.Vp8LDecoder;

typedef HGroup = Array<HTree>;

typedef HNode = {
    var symbol: Int; // Huffman symbol
    var children: Int; // Index of first child node, or -1 for leaf
}

class HTree {
    static final reverseBits = [
        0x00, 0x80, 0x40, 0xc0, 0x20, 0xa0, 0x60, 0xe0, 0x10, 0x90, 0x50, 0xd0, 0x30, 0xb0, 0x70, 0xf0,
        0x08, 0x88, 0x48, 0xc8, 0x28, 0xa8, 0x68, 0xe8, 0x18, 0x98, 0x58, 0xd8, 0x38, 0xb8, 0x78, 0xf8,
        0x04, 0x84, 0x44, 0xc4, 0x24, 0xa4, 0x64, 0xe4, 0x14, 0x94, 0x54, 0xd4, 0x34, 0xb4, 0x74, 0xf4,
        0x0c, 0x8c, 0x4c, 0xcc, 0x2c, 0xac, 0x6c, 0xec, 0x1c, 0x9c, 0x5c, 0xdc, 0x3c, 0xbc, 0x7c, 0xfc,
        0x02, 0x82, 0x42, 0xc2, 0x22, 0xa2, 0x62, 0xe2, 0x12, 0x92, 0x52, 0xd2, 0x32, 0xb2, 0x72, 0xf2,
        0x0a, 0x8a, 0x4a, 0xca, 0x2a, 0xaa, 0x6a, 0xea, 0x1a, 0x9a, 0x5a, 0xda, 0x3a, 0xba, 0x7a, 0xfa,
        0x06, 0x86, 0x46, 0xc6, 0x26, 0xa6, 0x66, 0xe6, 0x16, 0x96, 0x56, 0xd6, 0x36, 0xb6, 0x76, 0xf6,
        0x0e, 0x8e, 0x4e, 0xce, 0x2e, 0xae, 0x6e, 0xee, 0x1e, 0x9e, 0x5e, 0xde, 0x3e, 0xbe, 0x7e, 0xfe,
        0x01, 0x81, 0x41, 0xc1, 0x21, 0xa1, 0x61, 0xe1, 0x11, 0x91, 0x51, 0xd1, 0x31, 0xb1, 0x71, 0xf1,
        0x09, 0x89, 0x49, 0xc9, 0x29, 0xa9, 0x69, 0xe9, 0x19, 0x99, 0x59, 0xd9, 0x39, 0xb9, 0x79, 0xf9,
        0x05, 0x85, 0x45, 0xc5, 0x25, 0xa5, 0x65, 0xe5, 0x15, 0x95, 0x55, 0xd5, 0x35, 0xb5, 0x75, 0xf5,
        0x0d, 0x8d, 0x4d, 0xcd, 0x2d, 0xad, 0x6d, 0xed, 0x1d, 0x9d, 0x5d, 0xdd, 0x3d, 0xbd, 0x7d, 0xfd,
        0x03, 0x83, 0x43, 0xc3, 0x23, 0xa3, 0x63, 0xe3, 0x13, 0x93, 0x53, 0xd3, 0x33, 0xb3, 0x73, 0xf3,
        0x0b, 0x8b, 0x4b, 0xcb, 0x2b, 0xab, 0x6b, 0xeb, 0x1b, 0x9b, 0x5b, 0xdb, 0x3b, 0xbb, 0x7b, 0xfb,
        0x07, 0x87, 0x47, 0xc7, 0x27, 0xa7, 0x67, 0xe7, 0x17, 0x97, 0x57, 0xd7, 0x37, 0xb7, 0x77, 0xf7,
        0x0f, 0x8f, 0x4f, 0xcf, 0x2f, 0xaf, 0x6f, 0xef, 0x1f, 0x9f, 0x5f, 0xdf, 0x3f, 0xbf, 0x7f, 0xff,
    ];

    static inline var leafNode:Int = -1;
    static inline var lutSize:Int = 7;
    static inline var lutMask:Int = (1 << lutSize) - 1;

    var nodes:Array<HNode>;
    var lut:Array<Int>;

    public function new() {
        nodes = [ { symbol: 0, children: 0 } ]; // Root node
        lut = new Array<Int>();
        for (i in 0...1 << lutSize) lut.push(0);
    }

    public function insert(symbol:Int, code:Int, codeLength:Int) {
        if (symbol > 0xFFFF || codeLength > 0xFE)
            throw "Invalid Huffman tree";

        var baseCode = 0;
        if (codeLength > lutSize) {
            baseCode = reverseBits[(code >> (codeLength - lutSize)) & 0xFF] >> (8 - lutSize);
        } else {
            baseCode = reverseBits[code & 0xFF] >> (8 - codeLength);
            for (i in 0...1 << (lutSize - codeLength)) {
                lut[baseCode | (i << codeLength)] = (symbol << 8) | (codeLength + 1);
            }
        }

        var n = 0;
        var jump = lutSize;
        while (codeLength > 0) {
            codeLength--;
            if (n >= nodes.length) 
                throw "Invalid Huffman tree";

            switch (nodes[n].children) {
                case leafNode: 
                    throw "Invalid Huffman tree";
                case 0:
                    // if (nodes.length == nodes.capacity) 
                    //     throw "Invalid Huffman tree";
                    nodes[n].children = nodes.length;
                    nodes.push({ symbol: 0, children: 0 });
                    nodes.push({ symbol: 0, children: 0 });
            }
            n = nodes[n].children + (code >> codeLength & 1);
            jump--;
            if (jump == 0 && lut[baseCode] == 0) {
                lut[baseCode] = n << 8;
            }
        }

        if (nodes[n].children == 0) {
            nodes[n].children = leafNode;
        } else if (nodes[n].children != leafNode) {
            throw "Invalid Huffman tree";
        }
        nodes[n].symbol = symbol;
    }

    public function build(codeLengths:Array<Int>) {
        var nSymbols = 0, lastSymbol = 0;
        for (symbol => cl in codeLengths) {
            if (cl != 0) {
                nSymbols++;
                lastSymbol = symbol;
            }
        }
        
        if (nSymbols == 0) 
            throw "Invalid Huffman tree";
        
        nodes = [{ symbol: 0, children: 0 }];
        if (nSymbols == 1) {
            insert(lastSymbol, 0, 0);
            return;
        }

        var codes = codeLengthsToCodes(codeLengths);

        for (symbol => cl in codeLengths) {
            if (cl > 0) 
                insert(symbol, codes[symbol], cl);
        }
    }

    // buildSimple builds a Huffman tree with 1 or 2 symbols.
    public function buildSimple(nSymbols:Int, symbols:Array<Int>, alphabetSize:Int) {
        nodes = [{symbol: 0, children: 0}]; // Initialize with a single root node
        nodes.resize(2 * nSymbols - 1); // Allocate space

        for (i in 0...nSymbols) {
            if (symbols[i] >= alphabetSize) {
                throw "Invalid huffman tree";
            }
            insert(symbols[i], i, nSymbols - 1);
        }
    }

    public function next(d:Vp8LDecoder):Int {
        function slowPath(n) {
            while (nodes[n].children != leafNode) {
                if (d.nBits == 0) {
                    var c = d.r.readByte();
                    d.bits = c;
                    d.nBits = 8;
                }
                n = nodes[n].children + (d.bits & 1);
                d.bits >>= 1;
                d.nBits--;
            }
            return nodes[n].symbol;
        }

        if (d.nBits < lutSize) {
            try {
                d.bits |= d.r.readByte() << d.nBits;
                d.nBits += 8;
            } catch (e:haxe.io.Eof) {
                // There are no more bytes of data, but we may still be able
				// to read the next symbol out of the previously read bits.
                return slowPath(0);
            }
        }

        var n = lut[d.bits & lutMask];
        if (n & 0xFF != 0) {
            var b = (n & 0xFF) - 1;
            d.bits >>= b;
            d.nBits -= b;
            return n >> 8;
        }

        n >>= 8;
        d.bits >>= lutSize;
        d.nBits -= lutSize;
        
        return slowPath(n);
    }

    public static function codeLengthsToCodes(codeLengths:Array<Int>):Array<Int> {
        var maxCodeLength = 0;
        for (cl in codeLengths) {
            if (maxCodeLength < cl) maxCodeLength = cl;
        }
        var maxAllowedCodeLength = 15;
        if (codeLengths.length == 0 || maxCodeLength > maxAllowedCodeLength) 
            throw "Invalid Huffman tree";

        var histogram = new Array<Int>();
        for (i in 0...maxAllowedCodeLength + 1) histogram.push(0);
        for (cl in codeLengths) histogram[cl]++;

        var currCode = 0;
        var nextCodes = new Array<Int>();
        for (i in 0...maxAllowedCodeLength + 1) nextCodes.push(0);

        for (cl in 1...nextCodes.length) {
            currCode = (currCode + histogram[cl - 1]) << 1;
            nextCodes[cl] = currCode;
        }

        var codes = new Array<Int>();
        for (i in 0...codeLengths.length) codes.push(0);
        for (symbol => cl in codeLengths) {
            if (cl > 0) {
                codes[symbol] = nextCodes[cl];
                nextCodes[cl]++;
            }
        }
        return codes;
    }
}