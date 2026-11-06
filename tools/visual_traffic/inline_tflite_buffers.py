#!/usr/bin/env python3
"""Rewrites a .tflite file so every weight lives inside the FlatBuffer.

Models exported with litert-torch store weights after the FlatBuffer and point
to them with Buffer.offset and Buffer.size. The interpreter inside
flutter_litert does not read those, and fails at the first run with
"Input tensor N lacks data". Putting the bytes back into Buffer.data gives a
model that every runtime can load. The numbers do not change: the output of
the rewritten model is bit for bit the output of the original.

Usage: inline_tflite_buffers.py IN.tflite OUT.tflite

Needs numpy, flatbuffers, and a module named schema_generated next to this
script, made from the TensorFlow Lite schema with the object API:

    flatc --python --gen-object-api --gen-onefile schema.fbs
"""
import sys

import flatbuffers
import numpy as np

import schema_generated as S


def main() -> None:
    src, dst = sys.argv[1], sys.argv[2]
    data = open(src, "rb").read()
    model = S.Model.GetRootAsModel(data, 0)
    obj = S.ModelT.InitFromObj(model)
    inlined = 0
    for buf in obj.buffers:
        if (buf.data is None or len(buf.data) == 0) and buf.size and buf.size > 0:
            buf.data = np.frombuffer(
                data[buf.offset:buf.offset + buf.size], dtype=np.uint8
            ).copy()
            buf.offset = 0
            buf.size = 0
            inlined += 1
    builder = flatbuffers.Builder(len(data) + 1024)
    builder.Finish(obj.Pack(builder), b"TFL3")
    out = bytes(builder.Output())
    with open(dst, "wb") as f:
        f.write(out)
    print(f"inlined {inlined} buffers, wrote {len(out)} bytes to {dst}")


if __name__ == "__main__":
    main()
