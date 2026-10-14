#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""glb 验证：结构自洽 + bind pose 数学自证（worldBind @ IBM ≈ 单位矩阵）"""
import json
import struct
import sys

def read_glb(path):
    b = open(path, 'rb').read()
    assert b[:4] == b'glTF', 'not glb'
    ver, total = struct.unpack_from('<II', b, 4)
    off = 12
    js = None
    bin_data = None
    while off < total:
        clen, ctype = struct.unpack_from('<II', b, off)
        chunk = b[off+8:off+8+clen]
        if ctype == 0x4E4F534A:
            js = json.loads(chunk.decode('utf-8'))
        elif ctype == 0x004E4942:
            bin_data = chunk
        off += 8 + clen
    return js, bin_data

def acc_read(js, bin_data, acc_idx):
    acc = js['accessors'][acc_idx]
    bv = js['bufferViews'][acc['bufferView']]
    off = bv.get('byteOffset', 0)
    comp = acc['componentType']
    n = acc['count']
    t = acc['type']
    ncomp = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}[t]
    fmt = {5126: 'f', 5125: 'I', 5123: 'H', 5121: 'B'}[comp]
    size = struct.calcsize(fmt)
    vals = struct.unpack_from('<%d%s' % (n*ncomp, fmt), bin_data, off)
    return vals

def mat_identity():
    return [1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1]

def mat_mul(a, b):
    """列主序 4x4: a @ b"""
    r = [0.0]*16
    for c in range(4):
        for rw in range(4):
            s = 0.0
            for k in range(4):
                s += a[k*4+rw] * b[c*4+k]
            r[c*4+rw] = s
    return r

def trs_to_mat(t, q, s):
    x, y, z, w = q
    xx, yy, zz = x*x, y*y, z*z
    xy, xz, yz = x*y, x*z, y*z
    wx, wy, wz = w*x, w*y, w*z
    m = [
        (1-2*(yy+zz))*s[0], (2*(xy+wz))*s[0], (2*(xz-wy))*s[0], 0,
        (2*(xy-wz))*s[1], (1-2*(xx+zz))*s[1], (2*(yz+wx))*s[1], 0,
        (2*(xz+wy))*s[2], (2*(yz-wx))*s[2], (1-2*(xx+yy))*s[2], 0,
        t[0], t[1], t[2], 1,
    ]
    return m

def main(path):
    js, bin_data = read_glb(path)
    print('=== %s ===' % path)
    print('nodes=%d meshes=%d materials=%d accessors=%d views=%d' % (
        len(js.get('nodes', [])), len(js.get('meshes', [])),
        len(js.get('materials', [])), len(js['accessors']), len(js['bufferViews'])))
    if 'skins' in js:
        print('skins=%d joints=%d anims=%d' % (
            len(js['skins']), len(js['skins'][0]['joints']), len(js.get('animations', []))))

    mesh = js['meshes'][0]
    prim = mesh['primitives'][0]
    nv = js['accessors'][prim['attributes']['POSITION']]['count']
    ni = js['accessors'][prim['indices']]['count']
    print('mesh %r: verts=%d indices=%d tris=%d attrs=%s' % (
        mesh.get('name'), nv, ni, ni // 3, sorted(prim['attributes'].keys())))
    # bbox
    pos_acc = js['accessors'][prim['attributes']['POSITION']]
    print('bbox min=%s max=%s' % (
        [round(v,3) for v in pos_acc['min']], [round(v,3) for v in pos_acc['max']]))

    ok = True
    # bind pose 数学自证
    if 'skins' in js:
        skin = js['skins'][0]
        joints = skin['joints']
        # 求每 joint 的 parent（从 nodes.children 反查）
        parent = {}
        for ni2, node in enumerate(js['nodes']):
            for c in node.get('children', []):
                parent[c] = ni2
        # 计算 world bind
        world_cache = {}
        def world(ni3):
            if ni3 in world_cache:
                return world_cache[ni3]
            node = js['nodes'][ni3]
            t = node.get('translation', [0,0,0])
            q = node.get('rotation', [0,0,0,1])
            s = node.get('scale', [1,1,1])
            local = trs_to_mat(t, q, s)
            p = parent.get(ni3)
            if p is None:
                w = local
            else:
                w = mat_mul(world(p), local)
            world_cache[ni3] = w
            return w
        ibm_vals = acc_read(js, bin_data, skin['inverseBindMatrices'])
        max_err = 0.0
        for i, jn in enumerate(joints):
            w = world(jn)
            ibm = list(ibm_vals[i*16:(i+1)*16])
            prod = mat_mul(w, ibm)
            ident = mat_identity()
            err = max(abs(prod[k] - ident[k]) for k in range(16))
            max_err = max(max_err, err)
        print('bind pose 自证: max |worldBind@IBM - I| = %.6f %s' % (
            max_err, 'PASS' if max_err < 0.01 else 'FAIL'))
        if max_err >= 0.01:
            ok = False
        # 抽查动画
        for anim in js.get('animations', [])[:2]:
            nch = len(anim['channels'])
            s0 = anim['samplers'][0]
            tin = acc_read(js, bin_data, s0['input'])
            print('anim %r: channels=%d, track0 times %d: %.3f..%.3f' % (
                anim.get('name'), nch, len(tin), tin[0], tin[-1]))
        # 权重抽查
        wv = acc_read(js, bin_data, prim['attributes']['WEIGHTS_0'])
        jv = acc_read(js, bin_data, prim['attributes']['JOINTS_0'])
        bad_w = sum(1 for i in range(0, min(len(wv), 4000), 4)
                    if abs(sum(wv[i:i+4]) - 1.0) > 0.01)
        max_j = max(jv[:4000])
        print('weights: bad_sum=%d/1000, max joint idx=%d (bones=%d)' % (
            bad_w, max_j, len(joints)))
        if bad_w > 0 or max_j >= len(joints):
            ok = False
    print('VERDICT:', 'PASS' if ok else 'FAIL')
    return 0 if ok else 1

if __name__ == '__main__':
    rc = 0
    for p in sys.argv[1:]:
        rc |= main(p)
        print()
    raise SystemExit(rc)
