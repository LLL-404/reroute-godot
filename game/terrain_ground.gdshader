shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// 《改道》地面材质（2026-10-17 · 峡谷化第 2.5 步贴图落地）：
// 世界空间三平面双向纹理——沙（Ground093C CC0，× Program Palette 暖色调制）与
// 岩（Rock061 CC0）。两者按顶点色 a 位（岩石权值，CPU 在 view_terrain.gd
// _field_color / _outside_color 编码：场内坡度岩化 rock_mix / 场外沙→岩过渡 mix）混合。
// rgb 维持现行程序化色（校过 check_shots 的色 landscape），乘纹理不换基调：
// 每张纹理带增益 uniform（纹理均色 × 增益 ≈ 1），ALBEDO = 纹理 × rgb ≈ 今日色板 × 图案。
// 法线：各平面按主导世界轴展开（T/B 取正轴，地面俯视语境近似），再视图变换。
// 移动端预算：col+nrm 两种纹理 ×3 平面 =6 采样/片；roughness 走常量（rough 贴图未入库）。
//
// 2026-10-22 A8 地面画风：在既有纹理上叠三层「大尺度」细节，解决远看拼板感：
//  ① 世界空间 2D 值噪声（尺度约 10m）调明度 → 相邻地块/大平面不再是一整块单色；
//  ② 同一噪声的梯度做低频法线扰动 → 平顶也有缓丘感（几何微起伏在 CPU 侧另做）；
//  ③ 顶点 UV.x = 贴墙接触阴影 AO（CPU 在 view_terrain._rebuild_hex 烘焙）→ 台缘压暗。
// 移动端仍是低成本：噪声 2 octave × 3 次（法线差分），无额外纹理采样。

uniform sampler2D sand_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 sand_gain = vec3(0.95, 1.04, 1.31); // 1/µ(Ground093C) × 0.75（2026-10-21 法线修复后地面吃满主光，原增益过曝）
uniform vec3 rock_gain = vec3(2.70, 2.93, 3.15); // Rock061 偏暗（µ 0.33）：两轮标定后定值，同步 ×0.75
uniform float tex_m_sand = 3.4; // 地面纹理：1 平铺的世界米数（1K 砖，标定斜视无平铺感）
uniform float tex_m_rock = 3.6;
uniform float rough_sand = 0.62;
uniform float rough_rock = 0.66; // 暗面粗糙度回收（0.74 实测发闷）
uniform float nrm_sand = 0.75; // 法线强度（0=平，1=贴图全量）
uniform float nrm_rock = 0.75; // 岩面法线回收（1.30 时暗面自遮蔽过重）
uniform float rock_soft_up = 0.65; // 岩面风格化顶光补偿（2026-10-22 A8：0.20 → 0.65。崖壁背光面借顶光，不再压成黑墙）

// A8 大尺度细节参数
uniform float macro_scale = 0.085; // 色斑/缓丘频率（1/m；0.085 ≈ 12m 波长）
uniform float macro_amt = 0.22; // 明度摆动（±11%）
uniform float macro_nrm = 1.35; // 低频法线扰动幅度（配合 0.55m 差分步长）
uniform float macro_nrm_min_y = 0.35; // 只有较水平的面吃低频法线（崖壁交给贴图）
uniform float ao_strength = 0.55; // 顶点 AO 对 albedo 的压暗比例（其余交给 AO 输出）

varying vec3 v_wpos;
varying vec3 v_wnrm;

// 顶点：世界空间位置 + 世界法线（三平面采样与顶光补偿的输入）
void vertex() {
	v_wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

// 三平面采样：X 面取 (z,y)，Y 面取 (x,z)，Z 面取 (x,y)；权重按世界法线三轴分布。
vec3 tri3(sampler2D t, vec3 uv, vec3 w) {
	return texture(t, uv.zy).rgb * w.x + texture(t, uv.xz).rgb * w.y + texture(t, uv.xy).rgb * w.z;
}

// 法线图采样 → 切空间法线。
// 2026-10-21 定位：源 jpg（ground093c_nrm / rock061_nrm）**只存了 RG，B 通道全 0**。
// 原写法 n.z*2-1 恒为 -1 → 世界法线永远朝下 → 地形完全不吃直射光（只有 ambient），
// 这才是「光影发闷、无方向感、无投影」的根因。改由 RG 重建 Z，保证朝外半球。
vec3 tri_ng(sampler2D t, vec2 uv) {
	vec2 g = texture(t, uv).xy * 2.0 - 1.0;
	return vec3(g, sqrt(max(0.0, 1.0 - dot(g, g))));
}

// 平面法线图 → 世界空间：各平面 T/B 取世界正轴（u/v 与采样面同向），N=该平面法线轴。
vec3 tri_n(sampler2D t, vec3 uv, vec3 w, float s) {
	vec3 tX = tri_ng(t, uv.zy);
	vec3 tY = tri_ng(t, uv.xz);
	vec3 tZ = tri_ng(t, uv.xy);
	tX.xy *= s;
	tY.xy *= s;
	tZ.xy *= s;
	vec3 wx = (tX.x * vec3(0.0, 0.0, 1.0) + tX.y * vec3(0.0, 1.0, 0.0) + tX.z * vec3(1.0, 0.0, 0.0)) * w.x;
	vec3 wy = (tY.x * vec3(1.0, 0.0, 0.0) + tY.y * vec3(0.0, 0.0, 1.0) + tY.z * vec3(0.0, 1.0, 0.0)) * w.y;
	vec3 wz = (tZ.x * vec3(1.0, 0.0, 0.0) + tZ.y * vec3(0.0, 1.0, 0.0) + tZ.z * vec3(0.0, 0.0, 1.0)) * w.z;
	return normalize(wx + wy + wz);
}

// —— 大尺度噪声（二维值噪声；用于色斑与缓丘法线）——
float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 两 octave：大波定走势，小波打碎边界（避免噪声看起来像云团）
float fbm2(vec2 p) {
	return vnoise(p) * 0.65 + vnoise(p * 2.13 + vec2(17.0, 31.0)) * 0.35;
}

// 片元：沙/岩三平面采样按顶点色 a 混合；法线经顶光补偿后转视图空间
void fragment() {
	vec3 n = normalize(v_wnrm);
	vec3 w = pow(abs(n), vec3(6.0));
	w /= (w.x + w.y + w.z);
	float a = clamp(COLOR.a, 0.0, 1.0); // 岩石权值（顶点色 a 位）
	vec3 suv = v_wpos / tex_m_sand;
	vec3 ruv = v_wpos / tex_m_rock;
	vec3 sand_c = tri3(sand_col, suv, w) * sand_gain;
	vec3 rock_c = tri3(rock_col, ruv, w) * rock_gain;

	// ① 大尺度明度色斑（水平面权重；崖壁仍以贴图为主）
	float horiz = smoothstep(0.10, 0.70, abs(n.y));
	vec2 mp = v_wpos.xz * macro_scale;
	float macro = fbm2(mp);
	vec3 alb = mix(sand_c, rock_c, a) * COLOR.rgb;
	alb *= 1.0 + (macro - 0.5) * macro_amt * horiz;
	// 低频色温：亮处略暖、暗处略冷（避免整片同色温）
	alb = mix(alb, alb * vec3(0.94, 1.00, 1.06), (0.5 - macro) * 0.30 * horiz);

	// ③ 顶点 AO（贴墙接触阴影；未写 UV 的网格 UV=0 → 当作无遮挡）
	float ao = UV.x > 0.001 ? clamp(UV.x, 0.35, 1.0) : 1.0;
	ALBEDO = alb * mix(1.0, ao, ao_strength);
	AO = ao;

	vec3 wn3 = normalize(mix(tri_n(sand_nrm, suv, w, nrm_sand), tri_n(rock_nrm, ruv, w, nrm_rock), a));
	wn3 = normalize(wn3 + vec3(0.0, rock_soft_up * a, 0.0)); // 岩面顶光补偿（风格化：陡壁借顶光）

	// ② 低频法线扰动（缓丘感）：用时域差分求噪声梯度；只在近水平面上生效
	if (n.y > macro_nrm_min_y) {
		float e = 0.55;
		float m0 = macro;
		float mx = fbm2(mp + vec2(e, 0.0) * macro_scale);
		float mz = fbm2(mp + vec2(0.0, e) * macro_scale);
		wn3 = normalize(wn3 + vec3(-(mx - m0), 0.0, -(mz - m0)) * macro_nrm * horiz);
	}

	// 兜底：任何情况下法线不得翻到几何法线背面（贴图异常/极端切向值）
	if (dot(wn3, n) < 0.0) {
		wn3 -= 2.0 * dot(wn3, n) * n;
	}
	NORMAL = normalize((VIEW_MATRIX * vec4(wn3, 0.0)).xyz);
	// 粗糙度随色斑轻微起伏，远处高光不再是一整片同值
	ROUGHNESS = clamp(mix(rough_sand, rough_rock, a) + (macro - 0.5) * 0.14 * horiz, 0.35, 0.95);
}
