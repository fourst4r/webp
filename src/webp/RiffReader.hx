package webp;

import haxe.io.Bytes;
import webp.types.UInt8Vector;
import haxe.io.Input;

function u32(b) {
    return b[0] | b[1]<<8 | b[2]<<16 | b[3]<<24;
}

class RiffReader {
    public var r:Input;

    public var totalLen:Int = 0;
    public var chunkLen:Int = 0;

    public var chunkReader:ChunkReader;
    public var buf:UInt8Vector;
    public var padded:Bool;

    public function new(r:Input) {
        this.r = r;

        var buf = r.read(8);
        if (buf == null || buf.length < 8) {
            throw "MissingRIFFChunkHeader";
        }
        if (buf.getString(0, 4) != "RIFF") {
            throw "MissingRIFFChunkHeader";
        }

        final chunkLen = buf.getInt32(4);


        // return newListReader(u32(buf, 4), r);
    
        if (chunkLen < 4) {
            throw "ShortChunkData";
        }
        // var z = new Reader(chunkData);
        r.read(4);
        this.buf = buf;
        // z.buf = chunkData.read(new haxe.io.Bytes(4)).toArray();
        // if (z.buf == null || z.buf.length < 4) {
        //     return {listType: null, data: null, err: "ShortChunkData"};
        // }
        totalLen = chunkLen - 4;
        // return {listType: new FourCC([z.buf[0], z.buf[1], z.buf[2], z.buf[3]]), data: z, err: null};
    }

    public function next():{chunkID:String, chunkLen:Int, chunkData:Input} {
        // Drain the rest of the previous chunk
        if (chunkLen != 0) {
            final got = r.read(chunkLen);
            if (got.length != chunkLen) {
                throw "ShortChunkData";
            }
        }
        chunkReader = null;

        if (padded) {
            if (totalLen == 0) {
                throw "ListSubchunkTooLong";
            }
            totalLen--;
            if (r.readByte() == -1) {
                throw "MissingPaddingByte";
            }
        }

        if (totalLen == 0) {
            throw "EOF";
        }

        if (totalLen < 8) {
            throw "ShortChunkHeader";
        }
        totalLen -= 8;
        buf = r.read(8);

        final chunkID = buf.getString(0, 4);
        chunkLen = buf.getInt32(4); //(buf[4] << 24) | (buf[5] << 16) | (buf[6] << 8) | buf[7];
        
        if (chunkLen > totalLen) {
            throw "ListSubchunkTooLong";
        }

        padded = (chunkLen & 1) == 1;
        chunkReader = new ChunkReader(this);
        return {chunkID: chunkID, chunkLen: chunkLen, chunkData: chunkReader};
    }
}

class ChunkReader extends Input {
    public var z:RiffReader;

    public function new(z:RiffReader) {
        this.z = z;
    }

    public override function readByte():Int {
        return z.r.readByte();
    }

    public override function readBytes(p:Bytes, pos:Int, len:Int):Int {
        if (z.chunkReader != this) return 0;

        var n = Std.int(Math.min(z.chunkLen, p.length));
        var bytesRead = z.r.readBytes(p, 0, n);
        z.totalLen -= bytesRead;
        z.chunkLen -= bytesRead;
        if (bytesRead < n) {
            throw "UnexpectedEOF";
        }
        return bytesRead;
    }

    // public function read(p:haxe.io.Bytes):Int {
    //     if (z.chunkReader != this) return 0;

    //     var n = Std.int(Math.min(z.chunkLen, p.length));
    //     var bytesRead = z.r.readBytes(p, 0, n);
    //     z.totalLen -= bytesRead;
    //     z.chunkLen -= bytesRead;
    //     if (bytesRead < n) {
    //         throw "UnexpectedEOF";
    //     }
    //     return bytesRead;
    // }
} 
