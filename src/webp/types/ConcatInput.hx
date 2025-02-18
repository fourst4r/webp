package webp.types;

import haxe.io.Eof;
import haxe.io.Input;
import haxe.io.Bytes;

class ConcatInput extends Input {
    var _inputs:Array<Input>;
    var _current:Int;

    public function new(...inputs:Input) {
        if (inputs == null || inputs.length == 0)
            throw "Inputs array cannot be null or empty";
            
        this._inputs = inputs;
        this._current = 0;
    }

    override public function readByte():Int {
        while (_current < _inputs.length) {
            try {
                return _inputs[_current].readByte();
            } catch (e:Eof) {
                _current++;
            }
        }
        throw new Eof();
    }

    override public function readBytes(buf:Bytes, pos:Int, len:Int):Int {
        var totalRead = 0;
        var remaining = len;

        while (remaining > 0 && _current < _inputs.length) {
            try {
                var read = _inputs[_current].readBytes(buf, pos + totalRead, remaining);
                totalRead += read;
                remaining -= read;
            } catch (e:Eof) {
                _current++;
            }
        }

        if (totalRead == 0 && _current >= _inputs.length)
            throw new Eof();
            
        return totalRead;
    }

    override public function close() {
        for (input in _inputs) {
            input.close();
        }
    }
}