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

uniform sampler2D sand_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_col : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_nrm : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

uniform vec3 sand_gain = vec3(1.26, 1.39, 1.74); // 1/µ(Ground093C 0.796,0.722,0.576)
uniform vec3 rock_gain = vec3(3.60, 3.90, 4.20); // Rock061 偏暗（µ 0.33）：两轮标定后定值（陡崖面 = 全帧最大暗源，专攻）
uniform float tex_m_sand = 3.4; // 地面纹理：1 平铺的世界米数（1K 砖，标定斜视无平铺感）
uniform float tex_m_rock = 3.6;
uniform float rough_sand = 0.62;
uniform float rough_rock = 0.66; // 暗面粗糙度回收（0.74 实测发闷）
uniform float nrm_sand = 0.75; // 法线强度（0=平，1=贴图全量）
uniform float nrm_rock = 0.75; // 岩面法线回收（1.30 时暗面自遮蔽过重）
uniform float rock_soft_up = 1.05; // 岩面风格化顶光补偿（陡壁面世界法线向上偏 a×此值：借顶光/天光，消北侧阴影面死黑；2026-10-17 自然化调色）

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

// 平面法线图 → 世界空间：各平面 T/B 取世界正轴（u/v 与采样面同向），N=该平面法线轴。
vec3 tri_n(sampler2D t, vec3 uv, vec3 w, float s) {
	vec3 nX = vec3(texture(t, uv.zy).xyz * 2.0 - 1.0) * vec3(s, s, 1.0); // X 面（法线 +x，u=+z，v=+y）
	vec3 nY = vec3(texture(t, uv.xz).xyz * 2.0 - 1.0) * vec3(s, s, 1.0); // Y 面（法线 +y，u=+x，v=+z）
	vec3 nZ = vec3(texture(t, uv.xy).xyz * 2.0 - 1.0) * vec3(s, s, 1.0); // Z 面（法线 +z，u=+x，v=+y）
	vec3 wx = (nX.x * vec3(0.0, 0.0, 1.0) + nX.y * vec3(0.0, 1.0, 0.0) + nX.z * vec3(1.0, 0.0, 0.0)) * w.x;
	vec3 wy = (nY.x * vec3(1.0, 0.0, 0.0) + nY.y * vec3(0.0, 0.0, 1.0) + nY.z * vec3(0.0, 1.0, 0.0)) * w.y;
	vec3 wz = (nZ.x * vec3(1.0, 0.0, 0.0) + nZ.y * vec3(0.0, 1.0, 0.0) + nZ.z * vec3(0.0, 0.0, 1.0)) * w.z;
	return normalize(wx + wy + wz);
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
	ALBEDO = mix(sand_c, rock_c, a) * COLOR.rgb;
	vec3 wn3 = normalize(mix(tri_n(sand_nrm, suv, w, nrm_sand), tri_n(rock_nrm, ruv, w, nrm_rock), a));
	wn3 = normalize(wn3 + vec3(0.0, rock_soft_up * a, 0.0)); // 岩面顶光补偿（风格化：陡壁借顶光）
	NORMAL = normalize((VIEW_MATRIX * vec4(wn3, 0.0)).xyz);
	ROUGHNESS = mix(rough_sand, rough_rock, a);
}
