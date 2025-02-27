package webp.types;

import haxe.io.Bytes;

@:forward(getString, getInt32, getUInt16, sub, fill, blit, length)
abstract UInt8Vector(Bytes) from Bytes {
    public inline function new(?b, size:Int) {
        this = b ?? Bytes.alloc(size);
    }

    @:op([])
    public inline function get(i:Int):Int {
        return this.get(i);
    }

    @:op([])
    public inline function set(i:Int, value:Int) {
        this.set(i, value);
    }

    public static inline function filled(size:Int, value:Int) {
        final b = Bytes.alloc(size);
        b.fill(0, size, value);
        return b;
    }
}