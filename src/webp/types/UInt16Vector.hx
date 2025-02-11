package webp.types;

import haxe.io.Bytes;

abstract UInt16Vector(Bytes) {
    static inline final BYTES = 2;

    public inline function new(b, size:Int) {
        this = b ?? Bytes.alloc(size*BYTES);
    }

    @:op([])
    public inline function get(i:Int):Int {
        return this.getUInt16(i*BYTES);
    }

    @:op([])
    public inline function set(i:Int, value:Int) {
        this.setUInt16(i*BYTES, value);
    }
}