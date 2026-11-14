#!/usr/bin/env python3
"""重新生成 peer.torrent。内容不入库：每个文件由 "peer-fixture <路径>\\n" 循环填满 512 KiB，
与 tests/lib/runtime.sh 的 peer_content 一致，由做种端在容器内现场写出。"""
import hashlib
import pathlib

SIZE, PIECE = 512 * 1024, 64 * 1024
PATHS = ["a.bin", "b.bin", "sub/c.bin", "sub/d.bin"]


def content(path):
    line = f"peer-fixture {path}\n".encode()
    return (line * (SIZE // len(line) + 1))[:SIZE]


def bencode(value):
    if isinstance(value, int):
        return b"i%de" % value
    if isinstance(value, str):
        value = value.encode()
    if isinstance(value, bytes):
        return b"%d:%s" % (len(value), value)
    if isinstance(value, list):
        return b"l" + b"".join(map(bencode, value)) + b"e"
    return b"d" + b"".join(bencode(k) + bencode(v) for k, v in sorted(value.items())) + b"e"


blob = b"".join(content(p) for p in PATHS)
info = {
    "name": "peer-task",
    "piece length": PIECE,
    "pieces": b"".join(hashlib.sha1(blob[i:i + PIECE]).digest() for i in range(0, len(blob), PIECE)),
    "files": [{"length": SIZE, "path": p.split("/")} for p in PATHS],
}
target = pathlib.Path(__file__).with_name("peer.torrent")
target.write_bytes(bencode({"announce": "http://127.0.0.1:8080/announce", "info": info}))
