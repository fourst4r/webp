import haxe.io.BytesInput;
import haxe.Timer;

final lossy = sys.io.File.getBytes("test/1.webp");
final lossless = sys.io.File.getBytes("test/1ll.webp");
final target = #if hl "hl" #elseif cpp "cpp" #elseif jvm "jvm" #else "???" #end;

function main() {
    Sys.print('| $target | ' + benchmark(decodeLossy, 100));
    Sys.println(' | ' + benchmark(decodeLossless, 100));
}

function decodeLossy() {
    final img = webp.WebPDecoder.decode(new BytesInput(lossy));
}

function decodeLossless() {
    final img = webp.WebPDecoder.decode(new BytesInput(lossless));
}

function benchmark(fn:Void->Void, iterations:Int = 10):Float {
    var totalTime = 0.0;
    for (i in 0...iterations) {
        final start = Timer.stamp();
        fn();
        totalTime += Timer.stamp() - start;
    }
    return totalTime / iterations;
}