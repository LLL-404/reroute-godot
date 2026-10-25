extends RefCounted

# canon 单测（移植自 reroute/tests/test_canon.lua）：大端序、位型回绕、FNV 锚点与负对照。


func _bytes_of(fn: Callable) -> Array:
	var b := Canon.buffer()
	fn.call(b)
	return Array(b.data)


func register(kit: TestKit) -> void:
	kit.module("canon")

	kit.test("schema", func():
		kit.eq(Canon.STATE_SCHEMA, 10, "STATE_SCHEMA"))

	kit.test("put-u8-wrap", func():
		kit.seq(_bytes_of(func(b): b.put_u8(0x34)), [0x34], "put_u8 原值")
		kit.seq(_bytes_of(func(b): b.put_u8(0x1234)), [0x34], "put_u8 超宽取低 8 位")
		kit.seq(_bytes_of(func(b): b.put_u8(-1)), [0xFF], "put_u8 负值取位型")
		kit.seq(_bytes_of(func(b): b.put_u8(256 + 7)), [7], "put_u8 256 进制回绕"))

	kit.test("put-u32-big-endian", func():
		kit.seq(_bytes_of(func(b): b.put_u32(0x01020304)), [0x01, 0x02, 0x03, 0x04], "put_u32 大端序")
		kit.seq(_bytes_of(func(b): b.put_u32(0xFFFFFFFF)), [0xFF, 0xFF, 0xFF, 0xFF], "put_u32 全 1"))

	kit.test("put-i32-negative", func():
		kit.seq(_bytes_of(func(b): b.put_i32(-1)), [0xFF, 0xFF, 0xFF, 0xFF], "put_i32(-1)")
		kit.seq(_bytes_of(func(b): b.put_i32(-2)), [0xFF, 0xFF, 0xFF, 0xFE], "put_i32(-2)"))

	kit.test("put-u64-big-endian", func():
		kit.seq(_bytes_of(func(b): b.put_u64(0x0102030405060708)), [1, 2, 3, 4, 5, 6, 7, 8], "put_u64 大端序"))

	kit.test("fnv-anchors", func():
		var b := Canon.buffer()
		kit.eq(b.fingerprint(), Canon.FNV_OFFSET, "FNV 空串锚点")
		var fb := Canon.buffer()
		for i in "foobar".length():
			fb.put_u8("foobar".unicode_at(i))
		kit.eq(fb.fingerprint(), 3214735720, "FNV foobar 锚点"))

	kit.test("fnv-partial-n", func():
		var b := PackedByteArray([65, 66, 67])
		kit.eq(Canon.fnv1a32(b, 2), Canon.fnv1a32(PackedByteArray([65, 66]), 2), "fnv1a32 应只哈希前 n 字节"))

	kit.test("fingerprint-negative-control", func():
		var a := Canon.buffer()
		a.put_u32(123456)
		var c := Canon.buffer()
		c.put_u32(123457)
		kit.ok(a.fingerprint() != c.fingerprint(), "不同内容指纹相同 = 哈希失效"))

	kit.test("buffer-fingerprint-matches-fnv", func():
		var b := Canon.buffer()
		b.put_u8(1)
		b.put_u8(2)
		b.put_u8(3)
		kit.eq(b.fingerprint(), Canon.fnv1a32(b.data, b.data.size()), "Buf:fingerprint 与 fnv1a32(b, n) 不一致"))
