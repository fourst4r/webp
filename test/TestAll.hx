import utest.Runner;
import utest.ui.Report;

class TestAll {
  public static function main() {
    //the short way in case you don't need to handle any specifics
    utest.UTest.run([new Visual()]);
  }
}