package webp;

import haxe.io.BytesInput;
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

    public var chunkReader:Input;
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
    
        if (chunkLen < 4) {
            throw "ShortChunkData";
        }
        r.read(4);
        this.buf = buf;
        totalLen = chunkLen - 4;
    }

    public function next():{chunkID:String, chunkLen:Int, chunkData:Input} {
        chunkReader = null;

        if (padded) {
            if (totalLen == 0)
                throw "ListSubchunkTooLong";
            totalLen--;
            if (r.readByte() == -1)
                throw "MissingPaddingByte";
        }

        if (totalLen == 0)
            throw "EOF";
        

        final chunkHeaderSize = 8;
        if (totalLen < chunkHeaderSize)
            throw "ShortChunkHeader";
        
        totalLen -= chunkHeaderSize;
        buf = r.read(chunkHeaderSize);

        final chunkID = buf.getString(0, 4);
        chunkLen = buf.getInt32(4);
        
        if (chunkLen > totalLen) 
            throw "ListSubchunkTooLong";

        padded = (chunkLen & 1) == 1;

        final chunk = r.read(chunkLen);
        chunkReader = new BytesInput(chunk);

        return {chunkID: chunkID, chunkLen: chunkLen, chunkData: chunkReader};
    }
}

class ChunkReader extends Input {
    public var z:RiffReader;

    public function new(z:RiffReader) {
        this.z = z;
    }

    public override function readByte():Int {
        final b = z.r.readByte();
        z.totalLen--;
        z.chunkLen--;
        return b;
    }

    public override function readBytes(p:Bytes, pos:Int, len:Int):Int {
        if (z.chunkReader != this)
            throw "Stale reader";

        final n = Std.int(Math.min(z.chunkLen, p.length));
        final bytesRead = z.r.readBytes(p, 0, n);
        z.totalLen -= bytesRead;
        z.chunkLen -= bytesRead;
        return bytesRead;
    }

    public override function readFullBytes(s:Bytes, pos:Int, len:Int) {
        super.readFullBytes(s, pos, len);
        z.totalLen -= len;
        z.chunkLen -= len;
    }
} 
