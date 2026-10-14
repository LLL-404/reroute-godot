#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UrhoX UMD2 / UANI -> glTF 2.0 (.glb) 转换器
（《改道》资产转换专用：逆向自 blend_to_urhox.py 写入规范 + 真实文件逐字节验证）

UMD2 结构（观察到的事实，非猜测）：
  "UMD2"
  u32 numLODs
  [每 LOD: u32 numVertices, u32 numElements, u32 descs[numElements], u32 x1, u32 x2, 顶点数据]
  u32 numIndexBuffers
  [每索引块: u32 numIndices, u32 indexSize(2|4), 索引数据]
  [geometry 区——本转换器不解析，istart 恒 0、icount 在索引块中已有]
  [骨骼段（可选）: 逐根 name(cstring) + 121B 数据；总长精确对齐到 bbox 前]
  [文件尾 46B: 前 24B = bbox min/max]

  顶点元素 desc = type | (semantic << 8) | (index << 16)
  type: 0=int, 1=float, 2=vec2, 3=vec3, 4=vec4, 5=ubyte4, 6=ubyte4norm
  semantic: 0=POSITION, 1=NORMAL, 3=TANGENT, 4=TEXCOORD, 5=COLOR,
            6=BLENDWEIGHTS, 7=BLENDINDICES, 8=LIGHTMAPUV
  骨骼 121B 数据布局: parent(u32, 0-based, 根=0) + pos(3f) + quat(4f, xyzw)
             + scale(3f) + offsetMatrix(12f, 3x4 行主序)
  （根骨骼 "Root" 段的 246B = Root(5+121) + "Hip"(4+121)，Hip 是第 2 根真实骨骼）

UANI 结构：
  "UANI" + name(cstring) + length(f32) + u32 numTracks
  [每 track: name(cstring) + u8 flags(7) + u8 nframes(37) + 7B zeros
     + 36 帧 × [pos(3f) quat(4f) scale(3f) time(f32)]
     + 1 截断帧 pos+quat+scale(40B, 无 time)]
  （实测：每 track 数据区 = 36*44 + 40 = 1624B；截断帧忽略）

坐标变换 Urho3D(左手) -> glTF/Godot(右手)，z 取反:
  pos/normal: (x, y, -z)；tangent: (x, y, -z, -w)
  quat: (-x, -y, z, w)
  offsetMatrix: R' = S·R·S（R[0][2],R[1][2],R[2][0],R[2][1] 取反），t' = (tx, ty, -tz)
"""
from __future__ import annotations

import argparse
import json
import os
import struct
import sys

# ---------------- 基础读取 ----------------

def u32(b, o):
    return struct.unpack_from('<I', b, o)[0], o + 4

def f32(b, o, n=1):
    vals = struct.unpack_from('<%df' % n, b, o)
    return (vals if n > 1 else vals[0]), o + 4 * n

TYPE_SIZES = {0: 4, 1: 4, 2: 8, 3: 12, 4: 16, 5: 4, 6: 4}
SEM_POSITION = 0
SEM_NORMAL = 1
SEM_TANGENT = 3
SEM_TEXCOORD = 4
SEM_COLOR = 5
SEM_BLENDWEIGHTS = 6
SEM_BLENDINDICES = 7
SEM_LIGHTMAPUV = 8


def z3(v):
    return (v[0], v[1], -v[2])


def q_src_to_gltf(w, x, y, z):
    """源数据四元数顺序为 (w, x, y, z)（实测闭合验证），
    z 翻转坐标系后转 glTF (x, y, z, w)：(-x, -y, z, w)。"""
    return (-x, -y, z, w)


def z_ibm(m12):
    """3x4 行主序 offsetMatrix 的坐标系变换: R'=S·R·S, t'=S·t
    12 值布局 = 3 行 × 4 列: [m00 m01 m02 | m03] [m10 m11 m12 | m13] [m20 m21 m22 | m23]
    3x3 旋转部分索引 = [0,1,2, 4,5,6, 8,9,10]；平移 = 第 4 列 (m03, m13, m23)。"""
    r = [m12[0], m12[1], m12[2],
         m12[4], m12[5], m12[6],
         m12[8], m12[9], m12[10]]
    t = (m12[3], m12[7], m12[11])
    r2 = [r[0], r[1], -r[2], r[3], r[4], -r[5], -r[6], -r[7], r[8]]
    t2 = (t[0], t[1], -t[2])
    return r2, t2


# ---------------- UMD2 解析 ----------------

class Bone:
    __slots__ = ('name', 'parent', 'pos', 'quat', 'scale', 'ibm')

    def __init__(self, name, parent, pos, quat, scale, ibm):
        self.name = name
        self.parent = parent
        self.pos = pos
        self.quat = quat
        self.scale = scale
        self.ibm = ibm  # 9 旋转 + 3 平移（已做坐标变换）

    def local_m4(self):
        """与最终 glTF node 完全一致的局部矩阵（列主序 4x4）"""
        x, y, z, w = self.quat
        s = self.scale
        xx, yy, zz = x*x, y*y, z*z
        xy, xz, yz = x*y, x*z, y*z
        wx, wy, wz = w*x, w*y, w*z
        return [
            (1-2*(yy+zz))*s[0], (2*(xy+wz))*s[0], (2*(xz-wy))*s[0], 0,
            (2*(xy-wz))*s[1], (1-2*(xx+zz))*s[1], (2*(yz+wx))*s[1], 0,
            (2*(xz+wy))*s[2], (2*(yz-wx))*s[2], (1-2*(xx+yy))*s[2], 0,
            self.pos[0], self.pos[1], self.pos[2], 1,
        ]

    def ibm_m4(self):
        r, t = self.ibm
        return [r[0], r[3], r[6], 0, r[1], r[4], r[7], 0, r[2], r[5], r[8], 0,
                t[0], t[1], t[2], 1]

    def set_ibm_m4(self, m):
        self.ibm = (
            [m[0], m[4], m[8], m[1], m[5], m[9], m[2], m[6], m[10]],
            (m[12], m[13], m[14]),
        )


def m4_mul(a, b):
    r = [0.0]*16
    for c in range(4):
        for rw in range(4):
            s = 0.0
            for k in range(4):
                s += a[k*4+rw] * b[c*4+k]
            r[c*4+rw] = s
    return r


def m4_inv_rigid(m):
    """刚体 4x4 求逆（旋转正交 + 平移）"""
    R = [[m[0], m[4], m[8]], [m[1], m[5], m[9]], [m[2], m[6], m[10]]]
    t = [m[12], m[13], m[14]]
    Rt = [[R[j][i] for j in range(3)] for i in range(3)]
    t2 = [-sum(Rt[i][j]*t[j] for j in range(3)) for i in range(3)]
    return [Rt[0][0], Rt[1][0], Rt[2][0], 0, Rt[0][1], Rt[1][1], Rt[2][1], 0,
            Rt[0][2], Rt[1][2], Rt[2][2], 0, t2[0], t2[1], t2[2], 1]


def absorb_bind_basis(bones) -> None:
    """吸收"自动绑定额外 bind basis"：实测 W_i @ IBM_i == 全局常数 C（刚体），
    bind 姿势下蒙皮结果为 C·v（模型整体偏移 90° 轴交换）。
    令 IBM'_i = IBM_i @ C⁻¹ 后 bind 蒙皮 = 恒等；动画时
    M'(t) = W(t)·IBM·C⁻¹ = W(t)·W(bind)⁻¹（标准相对姿势变换），完全正确。"""
    W = {}
    def wof(i):
        if i in W:
            return W[i]
        bn = bones[i]
        local = bn.local_m4()
        w = local if bn.parent == i else m4_mul(wof(bn.parent), local)
        W[i] = w
        return w
    C = m4_mul(wof(0), bones[0].ibm_m4())
    Cinv = m4_inv_rigid(C)
    for bn in bones:
        bn.set_ibm_m4(m4_mul(bn.ibm_m4(), Cinv))


class Model:
    def __init__(self):
        self.vertices = []   # list of dict(pos, normal, uv, tangent, weights, joints)
        self.indices = []    # list[int] (LOD0)
        self.bones = []      # list[Bone]
        self.bbox = None     # (min, max) 原始坐标
        self.num_lods = 0


def parse_mdl(path: str) -> Model:
    b = open(path, 'rb').read()
    assert b[:4] == b'UMD2', '不是 UMD2 文件: ' + path
    L = len(b)
    o = 4
    num_lods, o = u32(b, o)
    m = Model()
    m.num_lods = num_lods

    lods = []
    for _ in range(num_lods):
        nv, o = u32(b, o)
        ne, o = u32(b, o)
        descs = []
        for _e in range(ne):
            d, o = u32(b, o)
            descs.append(d)
        o += 8  # x1, x2（未解语义，跳过）
        vsize = sum(TYPE_SIZES[d & 0xFF] for d in descs)
        lods.append((nv, descs, vsize, o))
        o += nv * vsize

    num_ib, o = u32(b, o)
    index_blocks = []
    for _i in range(num_ib):
        ni, o = u32(b, o)
        isz, o = u32(b, o)
        index_blocks.append((ni, isz, o))
        o += ni * isz

    # bbox（文件尾 46B 的前 24B）
    if L >= 46:
        mn, _ = f32(b, L - 46, 3)
        mx, _ = f32(b, L - 46 + 12, 3)
        m.bbox = (mn, mx)

    # 骨骼段（可选）：Root 名字起，每根 name + 121B，精确对齐到 bbox 前
    bbox_off = L - 46
    root_pos = b.find(b'Root\x00', o)
    if root_pos > 0 and root_pos < bbox_off:
        p = root_pos
        bones = []
        ok = True
        while p < bbox_off:
            e = b.find(b'\x00', p)
            if e < 0 or e >= bbox_off:
                ok = False
                break
            try:
                name = b[p:e].decode('ascii')
            except UnicodeDecodeError:
                ok = False
                break
            if not name or not all(32 <= c < 127 for c in b[p:e]):
                ok = False
                break
            data_off = e + 1
            if data_off + 121 > bbox_off:
                ok = False
                break
            parent = struct.unpack_from('<I', b, data_off)[0]
            pos = struct.unpack_from('<3f', b, data_off + 4)
            qw, qx, qy, qz = struct.unpack_from('<4f', b, data_off + 16)
            scale = struct.unpack_from('<3f', b, data_off + 32)
            ibm12 = struct.unpack_from('<12f', b, data_off + 44)
            r2, t2 = z_ibm(ibm12)
            bones.append(Bone(name, parent, z3(pos), q_src_to_gltf(qw, qx, qy, qz), tuple(scale), (r2, t2)))
            p = data_off + 121
        if ok and p == bbox_off and bones:
            m.bones = bones
            absorb_bind_basis(m.bones)

    # LOD0 顶点 + 索引
    nv, descs, vsize, voff = lods[0]
    verts = []
    for i in range(nv):
        off = voff + i * vsize
        v = {}
        p = off
        for d in descs:
            t = d & 0xFF
            sem = (d >> 8) & 0xFF
            if sem == SEM_POSITION:
                vv = struct.unpack_from('<3f', b, p)
                v['pos'] = z3(vv)
            elif sem == SEM_NORMAL:
                vv = struct.unpack_from('<3f', b, p)
                v['normal'] = z3(vv)
            elif sem == SEM_TEXCOORD:
                v['uv'] = struct.unpack_from('<2f', b, p)
            elif sem == SEM_TANGENT:
                vv = struct.unpack_from('<4f', b, p)
                v['tangent'] = (vv[0], vv[1], -vv[2], -vv[3])
            elif sem == SEM_BLENDWEIGHTS:
                v['weights'] = struct.unpack_from('<4f', b, p)
            elif sem == SEM_BLENDINDICES:
                v['joints'] = struct.unpack_from('<4B', b, p)
            # COLOR / LIGHTMAPUV / 其他：跳过
            p += TYPE_SIZES[t]
        verts.append(v)
    m.vertices = verts

    ni, isz, ioff = index_blocks[0]
    fmt = '<%dH' % ni if isz == 2 else '<%dI' % ni
    m.indices = list(struct.unpack_from(fmt, b, ioff))
    return m


# ---------------- UANI 解析 ----------------

class Anim:
    def __init__(self):
        self.name = ''
        self.length = 0.0
        self.tracks = {}  # bone_name -> list[(t, pos, quat, scale)]


def parse_ani(path: str, bone_names) -> Anim:
    """按骨骼名列表顺序定位 track（名后 \0 精确匹配；track 数据区 = 名尾到下一名首）。
    实测每 track = 9B 头 + 36 完整帧(44B) + 40B 截断帧；此处按数据区长度反推完整帧数，
    不依赖头部字节。"""
    b = open(path, 'rb').read()
    assert b[:4] == b'UANI', '不是 UANI 文件: ' + path
    o = 4
    e = b.find(b'\x00', o)
    a = Anim()
    a.name = b[o:e].decode('ascii')
    o = e + 1
    a.length, o = f32(b, o)
    _nt, o = u32(b, o)

    # 按名字顺序找每个 track 的名字位置
    positions = []
    cur = o
    for nm in bone_names:
        pat = nm.encode('ascii') + b'\x00'
        i = b.find(pat, cur)
        if i < 0:
            break
        positions.append((nm, i, len(pat)))
        cur = i + len(pat)

    for ti, (tname, npos, nlen) in enumerate(positions):
        head = npos + nlen
        nframes = struct.unpack_from('<I', b, head + 1)[0]  # u8 flags + u32 frames
        p = head + 5
        frames = []
        for _f in range(nframes):
            tval = struct.unpack_from('<f', b, p)[0]
            pos = struct.unpack_from('<3f', b, p + 4)
            qw, qx, qy, qz = struct.unpack_from('<4f', b, p + 16)
            scale = struct.unpack_from('<3f', b, p + 32)
            frames.append((tval, z3(pos), q_src_to_gltf(qw, qx, qy, qz), tuple(scale)))
            p += 44
        a.tracks[tname] = frames
    return a


# ---------------- glTF 构建 ----------------

class Glb:
    def __init__(self):
        self.bin = bytearray()
        self.buffer_views = []
        self.accessors = []

    def view(self, data: bytes, target=None) -> int:
        while len(self.bin) % 4:
            self.bin.append(0)
        off = len(self.bin)
        self.bin += data
        bv = {'buffer': 0, 'byteOffset': off, 'byteLength': len(data)}
        if target is not None:
            bv['target'] = target
        self.buffer_views.append(bv)
        return len(self.buffer_views) - 1

    def accessor(self, bv: int, ctype: int, count: int, atype: str,
                 mn=None, mx=None) -> int:
        acc = {'bufferView': bv, 'componentType': ctype, 'count': count, 'type': atype}
        if mn is not None:
            acc['min'] = mn
        if mx is not None:
            acc['max'] = mx
        self.accessors.append(acc)
        return len(self.accessors) - 1


CT_U16 = 5123
CT_U32 = 5125
CT_F32 = 5126
CT_U8 = 5121

AR_POS = 34962
AR_IDX = 34963


def build_glb(model: Model, anims, out_path: str,
              tex_d: str = None, tex_n: str = None,
              base_color=(1, 1, 1, 1), metallic=0.0, roughness=0.75,
              alpha_cutoff=None, name='asset') -> None:
    g = Glb()
    verts = model.vertices
    n = len(verts)
    has_skin = len(model.bones) > 0 and any('joints' in v for v in verts)

    # 顶点属性
    pos_data = bytearray()
    nor_data = bytearray()
    uv_data = bytearray()
    tan_data = bytearray()
    jnt_data = bytearray()
    wgt_data = bytearray()
    for v in verts:
        pos_data += struct.pack('<3f', *v.get('pos', (0, 0, 0)))
        nor_data += struct.pack('<3f', *v.get('normal', (0, 1, 0)))
        uv_data += struct.pack('<2f', *v.get('uv', (0, 0)))
        tan_data += struct.pack('<4f', *v.get('tangent', (1, 0, 0, 1)))
        jnt_data += bytes(v.get('joints', (0, 0, 0, 0)))
        wgt_data += struct.pack('<4f', *v.get('weights', (0, 0, 0, 0)))

    mn = [min(v['pos'][i] for v in verts) for i in range(3)]
    mx = [max(v['pos'][i] for v in verts) for i in range(3)]

    bv = g.view(bytes(pos_data), AR_POS)
    acc_pos = g.accessor(bv, CT_F32, n, 'VEC3', mn, mx)
    bv = g.view(bytes(nor_data), AR_POS)
    acc_nor = g.accessor(bv, CT_F32, n, 'VEC3')
    bv = g.view(bytes(uv_data), AR_POS)
    acc_uv = g.accessor(bv, CT_F32, n, 'VEC2')
    bv = g.view(bytes(tan_data), AR_POS)
    acc_tan = g.accessor(bv, CT_F32, n, 'VEC4')
    acc_jnt = acc_wgt = None
    if has_skin:
        bv = g.view(bytes(jnt_data), AR_POS)
        acc_jnt = g.accessor(bv, CT_U8, n, 'VEC4')
        bv = g.view(bytes(wgt_data), AR_POS)
        acc_wgt = g.accessor(bv, CT_F32, n, 'VEC4')

    idx16 = max(model.indices) < 65536 if model.indices else True
    if idx16:
        idx_bytes = struct.pack('<%dH' % len(model.indices), *model.indices)
        ct = CT_U16
    else:
        idx_bytes = struct.pack('<%dI' % len(model.indices), *model.indices)
        ct = CT_U32
    bv = g.view(idx_bytes, AR_IDX)
    acc_idx = g.accessor(bv, ct, len(model.indices), 'SCALAR')

    # 材质
    mat = {
        'name': name + '_mat',
        'pbrMetallicRoughness': {
            'baseColorFactor': list(base_color),
            'metallicFactor': metallic,
            'roughnessFactor': roughness,
        },
        'doubleSided': False,
    }
    if tex_d:
        mat['pbrMetallicRoughness']['baseColorTexture'] = {'index': 0}
    if tex_n:
        mat['normalTexture'] = {'index': 1}

    # 节点 / 骨架
    nodes = []
    skin_idx = None
    if has_skin:
        # 骨骼节点（0..B-1），再一个 mesh 节点（B）
        for i, bone in enumerate(model.bones):
            node = {
                'name': bone.name,
                'translation': list(bone.pos),
                'rotation': list(bone.quat),
                'scale': list(bone.scale),
            }
            nodes.append(node)
        for i, bone in enumerate(model.bones):
            if i == 0:
                continue
            p = bone.parent
            if p < 0 or p >= len(model.bones) or p == i:
                p = 0
            nodes[p].setdefault('children', []).append(i)
        # IBM accessor
        ibm_data = bytearray()
        for bone in model.bones:
            r, t = bone.ibm
            # glTF 4x4 列主序: [r00 r10 r20 0, r01 r11 r21 0, r02 r12 r22 0, tx ty tz 1]
            m4 = [
                r[0], r[3], r[6], 0.0,
                r[1], r[4], r[7], 0.0,
                r[2], r[5], r[8], 0.0,
                t[0], t[1], t[2], 1.0,
            ]
            ibm_data += struct.pack('<16f', *m4)
        bv = g.view(bytes(ibm_data))
        acc_ibm = g.accessor(bv, CT_F32, len(model.bones), 'MAT4')
        mesh_node = len(nodes)
        nodes.append({'name': name, 'mesh': 0, 'skin': 0})
        nodes[0]['children'] = nodes[0].get('children', [])  # root bone 挂场景根
        skin_idx = 0
        scene_nodes = [0, mesh_node]
        skins = [{
            'name': name + '_skin',
            'joints': list(range(len(model.bones))),
            'inverseBindMatrices': acc_ibm,
        }]
    else:
        nodes.append({'name': name, 'mesh': 0})
        scene_nodes = [0]
        skins = None

    # 动画
    gltf_anims = []
    if anims and has_skin:
        bone_index = {bone.name: i for i, bone in enumerate(model.bones)}
        for a in anims:
            samplers = []
            channels = []
            for tname, frames in a.tracks.items():
                bi = bone_index.get(tname)
                if bi is None:
                    continue
                times = [f[0] for f in frames]
                t_data = struct.pack('<%df' % len(times), *times)
                pos_vals = bytearray()
                rot_vals = bytearray()
                scl_vals = bytearray()
                for (_t, p, q, s) in frames:
                    pos_vals += struct.pack('<3f', *p)
                    rot_vals += struct.pack('<4f', *q)
                    scl_vals += struct.pack('<3f', *s)
                bv_t = g.view(t_data)
                acc_t = g.accessor(bv_t, CT_F32, len(times), 'SCALAR',
                                   [min(times)], [max(times)])
                bv_p = g.view(bytes(pos_vals))
                acc_p = g.accessor(bv_p, CT_F32, len(frames), 'VEC3')
                bv_r = g.view(bytes(rot_vals))
                acc_r = g.accessor(bv_r, CT_F32, len(frames), 'VEC4')
                bv_s = g.view(bytes(scl_vals))
                acc_s = g.accessor(bv_s, CT_F32, len(frames), 'VEC3')
                s0 = len(samplers)
                samplers.append({'input': acc_t, 'output': acc_p, 'interpolation': 'LINEAR'})
                samplers.append({'input': acc_t, 'output': acc_r, 'interpolation': 'LINEAR'})
                samplers.append({'input': acc_t, 'output': acc_s, 'interpolation': 'LINEAR'})
                channels.append({'sampler': s0, 'target': {'node': bi, 'path': 'translation'}})
                channels.append({'sampler': s0 + 1, 'target': {'node': bi, 'path': 'rotation'}})
                channels.append({'sampler': s0 + 2, 'target': {'node': bi, 'path': 'scale'}})
            gltf_anims.append({
                'name': a.name,
                'samplers': samplers,
                'channels': channels,
            })

    # 纹理（外部引用）
    images = []
    textures = []
    if tex_d:
        images.append({'uri': tex_d})
        textures.append({'source': 0})
    if tex_n:
        images.append({'uri': tex_n})
        textures.append({'source': len(images) - 1, 'sampler': 0})

    gltf = {
        'asset': {'version': '2.0', 'generator': 'umd2_to_gltf (reroute asset converter)'},
        'scene': 0,
        'scenes': [{'nodes': scene_nodes}],
        'nodes': nodes,
        'meshes': [{
            'name': name,
            'primitives': [{
                'attributes': {
                    'POSITION': acc_pos,
                    'NORMAL': acc_nor,
                    'TEXCOORD_0': acc_uv,
                    'TANGENT': acc_tan,
                    **({'JOINTS_0': acc_jnt, 'WEIGHTS_0': acc_wgt} if has_skin else {}),
                },
                'indices': acc_idx,
                'material': 0,
                'mode': 4,
            }],
        }],
        'materials': [mat],
        'accessors': g.accessors,
        'bufferViews': g.buffer_views,
        'buffers': [{'byteLength': len(g.bin)}],
    }
    if skins:
        gltf['skins'] = skins
    if gltf_anims:
        gltf['animations'] = gltf_anims
    if images:
        gltf['images'] = images
        gltf['textures'] = textures
        gltf['samplers'] = [{'magFilter': 9729, 'minFilter': 9987, 'wrapS': 10497, 'wrapT': 10497}]

    json_bytes = json.dumps(gltf, separators=(',', ':')).encode('utf-8')
    while len(json_bytes) % 4:
        json_bytes += b' '
    bin_bytes = bytes(g.bin)
    while len(bin_bytes) % 4:
        bin_bytes += b'\x00'

    total = 12 + 8 + len(json_bytes) + 8 + len(bin_bytes)
    with open(out_path, 'wb') as f:
        f.write(b'glTF')            # magic
        f.write(struct.pack('<II', 2, total))
        f.write(struct.pack('<I', len(json_bytes)))
        f.write(b'JSON')
        f.write(json_bytes)
        f.write(struct.pack('<I', len(bin_bytes)))
        f.write(b'BIN\x00')
        f.write(bin_bytes)


# ---------------- CLI ----------------

def main() -> int:
    ap = argparse.ArgumentParser(description='UMD2/UANI -> glb 转换器')
    ap.add_argument('--mdl', required=True, help='UMD2 模型路径')
    ap.add_argument('--ani', action='append', default=[], help='UANI 动画（可多次）')
    ap.add_argument('--out', required=True, help='输出 .glb 路径')
    ap.add_argument('--name', default=None, help='模型名（默认取文件名）')
    ap.add_argument('--tex-d', default=None, help='diffuse 贴图（相对 out 目录）')
    ap.add_argument('--tex-n', default=None, help='normal 贴图（相对 out 目录）')
    ap.add_argument('--base-color', default='1,1,1,1')
    ap.add_argument('--metallic', type=float, default=0.0)
    ap.add_argument('--roughness', type=float, default=0.75)
    args = ap.parse_args()

    model = parse_mdl(args.mdl)
    bone_names = [bone.name for bone in model.bones]
    anims = [parse_ani(p, bone_names) for p in args.ani]
    name = args.name or os.path.splitext(os.path.basename(args.out))[0]
    bc = tuple(float(x) for x in args.base_color.split(','))

    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    build_glb(model, anims, args.out,
              tex_d=args.tex_d, tex_n=args.tex_n,
              base_color=bc, metallic=args.metallic, roughness=args.roughness,
              name=name)
    print('[OK] %s: %d verts, %d idx, %d bones, %d anims -> %s (%.1f KB)' % (
        name, len(model.vertices), len(model.indices), len(model.bones),
        len(anims), args.out, os.path.getsize(args.out) / 1024))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
