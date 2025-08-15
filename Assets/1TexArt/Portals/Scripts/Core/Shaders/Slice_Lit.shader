Shader "URP/Custom/Slice_Lit_Min"
{
    Properties
    {
        _Color      ("Color", Color) = (1,1,1,1)
        _MainTex    ("Albedo (RGB)", 2D) = "white" {}
        _Glossiness ("Smoothness", Range(0,1)) = 0.5
        _Metallic   ("Metallic", Range(0,1)) = 0.0

        sliceNormal   ("normal", Vector) = (0,0,0,0)
        sliceCentre   ("centre", Vector) = (0,0,0,0)
        sliceOffsetDst("offset", Float)  = 0
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "Queue"="Geometry"
            "RenderType"="Opaque"
            "UniversalMaterialType"="Lit"
        }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        float4 _MainTex_ST;

        float4 _Color;
        float  _Glossiness;
        float  _Metallic;

        float3 sliceNormal;
        float3 sliceCentre;
        float  sliceOffsetDst;

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS   : NORMAL;
            float4 tangentOS  : TANGENT;
            float2 uv         : TEXCOORD0;
        };

        struct Varyings
        {
            float4 positionCS : SV_POSITION;
            float3 positionWS : TEXCOORD0;
            float3 normalWS   : TEXCOORD1;
            float2 uv         : TEXCOORD2;
            float3 viewDirWS  : TEXCOORD3;
            float4 shadowCoord: TEXCOORD4;
        };

        Varyings vert (Attributes v)
        {
            Varyings o;
            VertexPositionInputs posInputs = GetVertexPositionInputs(v.positionOS.xyz);
            VertexNormalInputs   nrmInputs = GetVertexNormalInputs(v.normalOS, v.tangentOS);

            o.positionCS = posInputs.positionCS;
            o.positionWS = posInputs.positionWS;
            o.normalWS   = NormalizeNormalPerVertex(nrmInputs.normalWS);
            o.viewDirWS  = GetWorldSpaceViewDir(o.positionWS);
            o.uv         = TRANSFORM_TEX(v.uv, _MainTex);
            o.shadowCoord = GetShadowCoord(posInputs);
            return o;
        }

        half4 frag (Varyings i) : SV_Target
        {
            // Slice 裁剪
            float3 n = normalize(sliceNormal);
            float3 adjustedCentre = sliceCentre + n * sliceOffsetDst;
            float3 offsetToCentre = adjustedCentre - i.positionWS;
            clip(dot(offsetToCentre, n));

            float4 baseSample = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, i.uv) * _Color;

            // ---- 完整初始化 SurfaceData（注意 normalTS / specular/emission 为 float3）----
            SurfaceData surfaceData;
            surfaceData.albedo               = baseSample.rgb;
            surfaceData.metallic             = saturate(_Metallic);
            surfaceData.specular             = float3(0,0,0);     // 金属度工作流下忽略
            surfaceData.smoothness           = saturate(_Glossiness);
            surfaceData.normalTS             = float3(0,0,1);     // 无法线贴图时用默认切线空间法线
            surfaceData.emission             = float3(0,0,0);
            surfaceData.occlusion            = 1;
            surfaceData.alpha                = baseSample.a;
            surfaceData.clearCoatMask        = 0;
            surfaceData.clearCoatSmoothness  = 0;

            // InputData 仍用世界空间法线
            InputData inputData;
            inputData.positionWS      = i.positionWS;
            inputData.normalWS        = normalize(i.normalWS);
            inputData.viewDirectionWS = normalize(i.viewDirWS);
            inputData.shadowCoord     = i.shadowCoord;
            inputData.fogCoord        = 0;
            inputData.vertexLighting  = 0;
            inputData.bakedGI         = 0;

            return UniversalFragmentPBR(inputData, surfaceData);
        }
        ENDHLSL

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }
            Blend Off
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag
            #pragma target 3.0
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog
            ENDHLSL
        }
    }

    FallBack Off
}
