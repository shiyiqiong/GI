Shader "Custom/Lit"
{
    Properties
    {
        _BaseMap("Texture", 2D) = "white" {} //基础颜色贴图
        _BaseColor("Color", Color) = (0.5, 0.5, 0.5, 1.0) //基础颜色
        _Metallic("Metallic", Range(0, 1)) = 0 //金属性
        _Smoothness("Smoothness", Range(0, 1)) = 0.5 //光滑度
        _Fresnel ("Fresnel", Range(0, 1)) = 1 //菲涅尔反射强度
    }
    SubShader
    {
        Tags { "RenderType"="Opaque" }

        Pass
        {
            Name "ForwardLit"
            Tags
            {
                "LightMode" = "UniversalForward"
            }
            HLSLPROGRAM
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile_instancing
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/CommonMaterial.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/EntityLighting.hlsl"
            #include "BRDF.hlsl"
            #include "GI.hlsl"

            #if defined(LIGHTMAP_ON) //开启烘焙光照贴图的，需要将烘焙光照贴图从顶点传递到片元
                #define GI_ATTRIBUTE_DATA float2 lightMapUV : TEXCOORD1;
                #define GI_VARYINGS_DATA float2 lightMapUV : VAR_LIGHT_MAP_UV;
                #define TRANSFER_GI_DATA(input, output) output.lightMapUV = input.lightMapUV * unity_LightmapST.xy + unity_LightmapST.zw;
                #define GI_FRAGMENT_DATA(input) input.lightMapUV
            #else //未开启烘焙光照贴图的，不做处理
                #define GI_ATTRIBUTE_DATA
                #define GI_VARYINGS_DATA
                #define TRANSFER_GI_DATA(input, output)
                #define GI_FRAGMENT_DATA(input) 0.0
            #endif

            struct appdata
            {
                float3 vertex : POSITION;
                float3 normalOS : NORMAL;
                float2 uv : TEXCOORD0;
                GI_ATTRIBUTE_DATA
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
                float3 positionWS : VAR_POSITION;
                half3 normalWS : VAR_NORMAL;
                GI_VARYINGS_DATA
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            v2f vert (appdata v)
            {
                v2f o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                TRANSFER_GI_DATA(v, o);
                //顶点计算
                o.positionWS = TransformObjectToWorld(v.vertex); //顶点：模型空间转世界空间
                o.vertex = TransformWorldToHClip(o.positionWS); //顶点：世界空间转齐次裁剪空间
                //法线计算
                o.normalWS = TransformObjectToWorldNormal(v.normalOS); //法线向量：模型空间转世界空间
                //UV坐标计算
                float4 baseMapST = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseMap_ST);
                o.uv = v.uv * baseMapST.xy + baseMapST.zw; //纹理UV坐标：加上缩放和平移参数
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                float4 col = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                float4 baseColor = UNITY_ACCESS_INSTANCED_PROP(UnityPerMaterial, _BaseColor);
                col = col * baseColor;
                //全局光照
                GI gi = GetGI(GI_FRAGMENT_DATA(i), i.normalWS, i.positionWS);
                //间接光
                float3 indirectLight = IndirectLight(gi, col.rgb, i.normalWS, i.positionWS);
                //直接光
                float3 directLight = DirectLight(i.normalWS, i.positionWS, col.rgb);
                //最终光照
                return float4(indirectLight + directLight, col.a);
            }

            ENDHLSL
        }
        Pass
        {
			Tags {
				"LightMode" = "Meta" //unity使用Mate通道来确定烘焙时的反射光（默认通道显示为白色）
			}

			Cull Off

			HLSLPROGRAM
			#pragma target 3.5
			#pragma vertex MetaPassVertex
			#pragma fragment MetaPassFragment
			#include "MetaPass.hlsl"
			ENDHLSL
		}
    }
}
