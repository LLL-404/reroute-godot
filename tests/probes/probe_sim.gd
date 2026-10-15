extends ProbeKit

# R2 验证探针：canon/rng 自检锚点（正对照）。
# 判定：exit 0 + stdout 含 `[SIM] PASS`。
func _initialize() -> void:
	var cr := Canon.selftest()
	print("[SIM] canon.selftest = ", cr[0], " ", cr[1])
	check(cr[0], "canon.selftest")
	var rr := Rng.selftest()
	print("[SIM] rng.selftest = ", rr[0], " ", rr[1])
	check(rr[0], "rng.selftest")
	# 追加核验：put_u64 大端字节序（0x0102030405060708 → 01..08）
	var b := Canon.buffer()
	b.put_u64(0x0102030405060708)
	var expect := [1, 2, 3, 4, 5, 6, 7, 8]
	var same := b.data.size() == 8
	for i in 8:
		if b.data[i] != expect[i]:
			same = false
	print("[SIM] put_u64 big-endian = ", same)
	check(same, "put_u64 big-endian")
	# 追加核验：put_i32(-2) → FF FF FF FE
	var b2 := Canon.buffer()
	b2.put_i32(-2)
	print("[SIM] put_i32(-2) = ", b2.data, " 期望 [255,255,255,254]")
	check(b2.data[0] == 255 and b2.data[1] == 255 and b2.data[2] == 255 and b2.data[3] == 254, "put_i32(-2)")
	# 追加核验：next_int 边界
	var r := Rng.new(7)
	var got1 := r.next_int(1)
	var got0 := r.next_int(0)
	var gotn := r.next_int(-5)
	print("[SIM] next_int(1/0/-5) = ", got1, " ", got0, " ", gotn)
	check(got1 == 0 and got0 == 0 and gotn == 0, "next_int 边界全 0")
	finish("SIM")
