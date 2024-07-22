#ifndef CUSTOM_GI_INCLUDED
#define CUSTOM_GI_INCLUDED

#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/ImageBasedLighting.hlsl"

struct GI {
	float3 diffuse; //间接光漫反射
	float3 specular; //间接光镜面反射
};

//采样烘焙光照贴图
float3 SampleLightMap (float2 lightMapUV) {
	#if defined(LIGHTMAP_ON)
		return SampleSingleLightmap(
			TEXTURE2D_ARGS(unity_Lightmap, samplerunity_Lightmap), 
			lightMapUV,
			float4(1.0, 1.0, 0.0, 0.0),
			#if defined(UNITY_LIGHTMAP_FULL_HDR)
				false,
			#else
				true,
			#endif
			float4(LIGHTMAP_HDR_MULTIPLIER, LIGHTMAP_HDR_EXPONENT, 0.0, 0.0)
		);
	#else
		return 0.0;
	#endif
}

//采样光照探针
float3 SampleLightProbe(half3 normalWS)
{
    #if defined(LIGHTMAP_ON)
        return 0.0;
    #else
        float4 coefficients[7];
        coefficients[0] = unity_SHAr;
        coefficients[1] = unity_SHAg;
        coefficients[2] = unity_SHAb;
        coefficients[3] = unity_SHBr;
        coefficients[4] = unity_SHBg;
        coefficients[5] = unity_SHBb;
        coefficients[6] = unity_SHC;
        return max(0.0, SampleSH9(coefficients, normalWS));
    #endif
}

//采样反射探针
float3 SampleEnvironment (half3 normalWS, float3 positionWS) {
	half3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS); //视角向量
	float smoothness = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Smoothness);
	float perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);  //感知粗糙度
	float roughness = PerceptualRoughnessToRoughness(perceptualRoughness); //粗糙度
	float mip = PerceptualRoughnessToMipmapLevel(roughness); //通过多级渐远纹理，实现不同粗糙度，环境贴图不同模糊效果
	float3 uvw = reflect(-viewDirWS, normalWS); //采样方向：摄像机到表面的反射方向
	float4 environment = SAMPLE_TEXTURECUBE_LOD( //采样反射探针：立方体贴图，立方体贴图采样器，
		unity_SpecCube0, samplerunity_SpecCube0, uvw, mip
	);
	return DecodeHDREnvironment(environment, unity_SpecCube0_HDR); //解码HDR环境光信息
}

//采样（烘焙光照贴图、光照探针、反射探针）获得间接漫反射和间接镜面反射
GI GetGI (float2 lightMapUV, half3 normalWS, float3 positionWS) {
	GI gi;
	gi.diffuse = SampleLightMap(lightMapUV) + SampleLightProbe(normalWS);
	gi.specular = SampleEnvironment(normalWS, positionWS);
	return gi;
}

//菲涅尔反射
float3 Fresnel(float3 specular, float3 specularColor, half3 normalWS, float3 positionWS)
{
	float smoothness = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Smoothness);
	float metallic = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Metallic);
	float oneMinusReflectivity = OneMinusReflectivity(metallic);
	half3 viewDirWS = GetWorldSpaceNormalizeViewDir(positionWS); //视角向量

	float fresnelColor = saturate(smoothness + 1.0 - oneMinusReflectivity); //菲涅尔反射颜色，反射率+光滑度，取值范围[0, 1]
	float fresnelValue = GetFresnel(); //菲涅尔强度参数
	float fresnelStrength = fresnelValue * Pow4(1.0 - saturate(dot(normalWS, viewDirWS))); //菲涅尔强度：1-视角向量投射到法线（掠视角度越大，强度越高），进行4次方进行指数衰减
	float3 reflection = specular * lerp(specularColor, fresnelColor, fresnelStrength); //镜面反射颜色，通过菲涅尔强度，从镜面反射颜色插值到菲涅尔颜色
	return reflection;
}

//间接光漫反射
float3 IndirectDiffuse(float3 diffuse, float3 color)
{
	float3 diffuseBRDF = DiffuseBRDF(color);
	return diffuse * diffuseBRDF;
}

//间接光镜面反射
float3 IndirectSpecular(float3 giSpecular, float3 color, half3 normalWS, float3 positionWS)
{
	float metallic = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Metallic); //金属性
	float3 specularColor = lerp(MIN_REFLECTIVITY, color, metallic); //镜面反射颜色
	float smoothness = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _Smoothness);
	float perceptualRoughness = PerceptualSmoothnessToPerceptualRoughness(smoothness);  //感知粗糙度
	float roughness = PerceptualRoughnessToRoughness(perceptualRoughness); //粗糙度
	float3 reflection = Fresnel(giSpecular, specularColor, normalWS, positionWS); //间接镜面反射菲涅尔效应
	reflection = reflection/(roughness * roughness + 1.0); //粗糙度会减少反射
    return reflection;
}

//间接光：间接光漫反射 + 间接光镜面反射
float3 IndirectLight(GI gi, float3 color, half3 normalWS, float3 positionWS)
{
	float3 indirectDiffuse = IndirectDiffuse(gi.diffuse, color);
	float3 indirectSpecular = IndirectSpecular(gi.specular, color, normalWS, positionWS);
	return indirectDiffuse + indirectSpecular;
}

#endif