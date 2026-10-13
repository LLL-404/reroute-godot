extends SceneTree

# R2 验证探针：canon/rng 自检锚点（正对照）。exit 0 = 全过。
func _initialize() -> void:
	var ok := true
	var cr := Canon.selftest()
	print("canon.selftest = ", cr[0], " ", cr[1])
	if not cr[0]:
		ok = false
	var rr := Rng.selftest()
	print("rng.selftest = ", rr[0], " ", rr[1])
	if not rr[0]:
		ok = false
	# 追加核验：put_u64 大端字节序（0x0102030405060708 → 01..08）
	var b := Canon.buffer()
	b.put_u64(0x0102030405060708)
	var expect := [1, 2, 3, 4, 5, 6, 7, 8]
	var same := b.data.size() == 8
	for i in 8:
		if b.data[i] != expect[i]:
			same = false
	print("put_u64 big-endian = ", same)
	if not same:
		ok = false
	# 追加核验：put_i32(-2) → FF FF FF FE
	var b2 := Canon.buffer()
	b2.put_i32(-2)
	print("put_i32(-2) = ", b2.data, " 期望 [255,255,255,254]")
	if b2.data[0] != 255 or b2.data[1] != 255 or b2.data[2] != 255 or b2.data[3] != 254:
		ok = false
	# 追加核验：next_int 边界
	var r := Rng.new(7)
	print("next_int(1/0/-5) = ", r.next_int(1), " ", r.next_int(0), " ", r.next_int(-5))
	if r.next_int(1) != 0 or r.next_int(0) != 0 or r.next_int(-5) != 0:
		ok = false
	print("[R2-PROBE] ", "PASS" if ok else "FAIL")
	quit(0 if ok else 1)
