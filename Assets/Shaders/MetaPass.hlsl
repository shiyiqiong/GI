#ifndef CUSTOM_META_PASS_INCLUDED
#define CUSTOM_META_PASS_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
#include "BRDF.hlsl"

float unity_OneOverOutputBoost;
float unity_MaxOutputValue;
bool4 unity_MetaFragmentControl;

struct Attributes {
	float3 positionOS : POSITION;
	float2 baseUV : TEXCOORD0;
	float2 lightMapUV : TEXCOORD1;
};

struct Varyings {
	float4 positionCS_SS : SV_POSITION;
	float2 baseUV : VAR_BASE_UV;
};

Varyings MetaPassVertex (Attributes input) {
	Varyings output;
	input.positionOS.xy = input.lightMapUV * unity_LightmapST.xy + unity_LightmapST.zw;
	input.positionOS.z = input.positionOS.z > 0.0 ? FLT_MIN : 0.0;
	output.positionCS_SS = TransformWorldToHClip(input.positionOS);
	float4 baseMapST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
	output.baseUV = input.baseUV * baseMapST.xy + baseMapST.zw; //纹理UV坐标：加上缩放和平移参数
	return output;
}

float4 MetaPassFragment (Varyings input) : SV_TARGET {
	float4 meta = 0.0;
	float4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, input.baseUV);
	float4 baseColor = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
	col = col * baseColor;
	float3 diffuse = DiffuseBRDF(col.rgb);//漫反射
	float metallic = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Metallic); //金属性
	float smoothness = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Smoothness);
	float perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);  //感知粗糙度
	float roughness = PerceptualRoughnessToRoughness(perceptualRoughness); //粗糙度
	float3 specularColor = lerp(MIN_REFLECTIVITY, col.rgb, metallic); //镜面反射颜色
	float3 specular = specularColor * roughness * 0.5; //直射光镜面反射产生间接光
	meta = float4(diffuse + specular, 1.0);
	meta.rgb = min(PositivePow(meta.rgb, unity_OneOverOutputBoost), unity_MaxOutputValue);
	return meta;
}

#endif