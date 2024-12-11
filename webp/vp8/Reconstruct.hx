package webp.vp8;

final bCoeffBase = 1 * 16 * 16 + 0 * 8 * 8;
final rCoeffBase = 1 * 16 * 16 + 1 * 8 * 8;
final whtCoeffBase = 1 * 16 * 16 + 2 * 8 * 8;

final ybrYX = 8;
final ybrYY = 1;
final ybrBX = 8;
final ybrBY = 18;
final ybrRX = 24;
final ybrRY = 18;

inline function btou(b:Bool):Int {
    return if (b) 1 else 0;
}

inline function pack(x:Array<Int>, shift:Int):Int {
    return (x[0] << 0 | x[1] << 1 | x[2] << 2 | x[3] << 3) << shift;
}

final unpack:Array<Array<Int>> = [
    [0, 0, 0, 0], [1, 0, 0, 0], [0, 1, 0, 0], [1, 1, 0, 0],
    [0, 0, 1, 0], [1, 0, 1, 0], [0, 1, 1, 0], [1, 1, 1, 0],
    [0, 0, 0, 1], [1, 0, 0, 1], [0, 1, 0, 1], [1, 1, 0, 1],
    [0, 0, 1, 1], [1, 0, 1, 1], [0, 1, 1, 1], [1, 1, 1, 1]
];

final bands:Array<Int> = [
    0, 1, 2, 3, 6, 4, 5, 6, 6, 6, 6, 6, 6, 6, 6, 7, 0
];

final cat3456:Array<Array<Int>> = [
    [173, 148, 140, 0, 0, 0, 0, 0, 0, 0, 0, 0],
    [176, 155, 140, 135, 0, 0, 0, 0, 0, 0, 0, 0],
    [180, 157, 141, 134, 130, 0, 0, 0, 0, 0, 0, 0],
    [254, 254, 243, 230, 196, 177, 153, 140, 133, 130, 129, 0]
];

final zigzag:Array<Int> = [
    0, 1, 4, 8, 5, 2, 3, 6, 9, 12, 13, 10, 7, 11, 14, 15
];