import utest.Assert;
import utest.Async;
import haxe.io.Bytes;

class Visual extends utest.Test {
  
    public function setup() {
    }

    function testAll() {
        final imgs = ["1", "2", "3", "4", "5", "1ll", "2ll", "3ll", "4ll", "5ll"];
        for (n in imgs) 
            convert(n);
        Assert.pass();
    }

    function convert(imgName:String) {
        // trace("convert "+imgName);
        final fi = sys.io.File.read("test/"+imgName+".webp");
        var img = webp.WebPDecoder.decode(fi);
        fi.close();
        img = webp.Tools.toArgb(img);
        final fo = sys.io.File.write("test/actual/"+imgName+".png");
        switch (img.data) {
        case Argb(pix, stride):
            final h = Std.int(pix.length/stride);
            final w = Std.int(stride/4);
            final pngData = format.png.Tools.build32ARGB(w, h, pix);
            new format.png.Writer(fo).write(pngData);
        default:
        }
        fo.close();


    }
}