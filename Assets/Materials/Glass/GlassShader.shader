Shader "URP/Glass_PBR"
{
    Properties
    {
        [Header(Main Properties)][Space(5)]
        _MainTex("Albedo", 2D) = "white" {}
        _Opacity("Opacity", Range( 0 , 1)) = 1
        _EmissionColor("Emission Color", Color) = (0,0,0,0)
        _EmissiveIntensity("Emissive Intensity", Range( 0 , 2)) = 1

        [Header(PBR)][Space(5)]
        _MetallicGlossMap("Metallic(RoughA)", 2D) = "white" {}
        _Metallic("Metallic", Range( 0 , 2)) = 0.2
        _Glossiness("Smoothness", Range( 0 , 1)) = 0.5
        
        [Header(Normal)][Space(5)]
        _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Scale", Float) = 0.3
        
        [Header(Refraction)][Space(5)]
        _Refraction("Refraction", Range( 0 , 2)) = 1.1


        [Header(Reflection)][Space(5)]
        _ColorCubemap("Color ", Color) = (1,1,1,1)
        _ReflectionIntensity("Reflection Intensity", Float) = 1
        [ToggleOff(_USECUBEMAP_OFF)] _UseCubemap("Use Cubemap", Float) = 1
        [HDR]_CubeMap("Cube Map", CUBE) = "black" {}
        _BlurReflection("Blur", Range( 0 , 8)) = 0
        
        [Header(Fresnel)][Space(5)]
        _ColorFresnel("Color Fresnel", Color) = (1,1,1,0)
        _FresnelStrength("Fresnel Strength", Float) = 0
        _PowerFresnel("Power", Range( -1 , 2)) = 1

        [Header(Grime)][Space(5)]
        _GrimeMap("Grime Map (RGB, A optional)", 2D) = "white" {}
        _GrimeColor("Grime Color (multiply)", Color) = (0.7, 0.7, 0.7, 1)
        _GrimeIntensity("Grime Intensity", Range(0,1)) = 1
        _GrimeSmoothnessLoss("Smoothness Loss by Grime", Range(0,1)) = 0.5
    }

    SubShader
    {
        Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Transparent" "Queue"="Transparent" }
        Cull Back

        Pass
        {
            Tags { "LightMode"="UniversalForward" }
            Blend SrcAlpha OneMinusSrcAlpha, One OneMinusSrcAlpha
            ZWrite Off
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            // #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            // #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            // #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            // #pragma multi_compile _ _SHADOWS_SOFT
            // #pragma multi_compile _ _MIXED_LIGHTING_SUBTRACTIVE

            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            //#pragma multi_compile _ DIRLIGHTMAP_COMBINED
            //#pragma multi_compile _ LIGHTMAP_ON
            
            #define REQUIRE_OPAQUE_TEXTURE 1
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/UnityInstancing.hlsl"
            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Texture.hlsl"

            
            #pragma shader_feature_local _USECUBEMAP_OFF
            #define TransformUV(uv, st) ((uv) * (st).xy + (st).zw)

            struct VertexInput
            {
                float4 vertex : POSITION;
                float3 ase_normal : NORMAL;
                float4 ase_tangent : TANGENT;
                float4 texcoord1 : TEXCOORD1;
                float4 texcoord : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            CBUFFER_START(UnityPerMaterial)
            float4 _EmissionColor;
            float _EmissiveIntensity;
            float _Opacity;
            
            float4 _ColorFresnel;
            float4 _ColorCubemap;
            float _Metallic;
            float _Glossiness;
            float _BumpScale;

            float4 _MainTex_ST;
            float4 _BumpMap_ST;
            float4 _MetallicGlossMap_ST;

            float _Refraction;

            float _ReflectionIntensity;
            float _BlurReflection;
            
            float _FresnelStrength;
            float _PowerFresnel;


            CBUFFER_END
            struct VertexOutput
            {
                float4 clipPos : SV_POSITION;
                float4 lightmapUVOrVertexSH : TEXCOORD0;
                half4 fogFactorAndVertexLight : TEXCOORD1;

                float4 tSpace0 : TEXCOORD3;
                float4 tSpace1 : TEXCOORD4;
                float4 tSpace2 : TEXCOORD5;
                
                float4 screenPos : TEXCOORD6;

                float2 uvMain : TEXCOORD8;
                float2 uvBump : TEXCOORD9;
                float2 uvMR   : TEXCOORD10;

            };

            TEXTURE2D(_MainTex);            SAMPLER(sampler_MainTex);
            TEXTURE2D(_BumpMap);            SAMPLER(sampler_BumpMap);
            TEXTURE2D(_MetallicGlossMap);   SAMPLER(sampler_MetallicGlossMap);
            TEXTURECUBE(_CubeMap);          SAMPLER(sampler_CubeMap);
            TEXTURE2D_X(_CameraOpaqueTexture); SAMPLER(sampler_CameraOpaqueTexture);
            
            struct RefractionModelResult { float dist; float3 positionWS; float3 rayWS; };


            // ----------------- Vertex -----------------
            VertexOutput VertexFunction(VertexInput v)
            {
                VertexOutput o = (VertexOutput)0;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                float2 baseUV = v.texcoord.xy;
                o.uvMain = TRANSFORM_TEX(baseUV, _MainTex);          
                o.uvBump = TRANSFORM_TEX(baseUV, _BumpMap);
                o.uvMR   = TRANSFORM_TEX(baseUV, _MetallicGlossMap);

                float3 positionWS = TransformObjectToWorld(v.vertex.xyz);
                float4 positionCS = TransformWorldToHClip(positionWS);

                VertexNormalInputs normalInput = GetVertexNormalInputs(v.ase_normal, v.ase_tangent);
                o.tSpace0 = float4(normalInput.normalWS, positionWS.x);
                o.tSpace1 = float4(normalInput.tangentWS, positionWS.y);
                o.tSpace2 = float4(normalInput.bitangentWS, positionWS.z);


                half3 vertexLight = VertexLighting(positionWS, normalInput.normalWS);
                half fogFactor = ComputeFogFactor(positionCS.z);

                o.fogFactorAndVertexLight = half4(fogFactor, vertexLight);
                
                o.clipPos = positionCS;

                o.screenPos = ComputeScreenPos(positionCS);

                return o;
            }

            VertexOutput vert (VertexInput v) { return VertexFunction(v); }


            // ----------------- Fragment -----------------
            half4 frag ( VertexOutput IN) : SV_Target
            {
                // World frames
                float3 WorldNormal = normalize(IN.tSpace0.xyz);
                float3 WorldTangent = IN.tSpace1.xyz;
                float3 WorldBiTangent = IN.tSpace2.xyz;
                float3 WorldPosition = float3(IN.tSpace0.w, IN.tSpace1.w, IN.tSpace2.w);
                float3 WorldViewDirection = SafeNormalize(_WorldSpaceCameraPos.xyz - WorldPosition);


                // Albedo

                float4 Albedo = SAMPLE_TEXTURE2D(_MainTex, sampler_MainTex, IN.uvMain);


                // Normal
                float2 uvBump = IN.uvBump;
                float3 tNormal = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, uvBump), _BumpScale);

                tNormal.z = lerp(1, tNormal.z, saturate(_BumpScale));
                float3x3 TBN = float3x3(WorldTangent, WorldBiTangent, WorldNormal);
                float3 worldNormalFromTS = normalize(mul(tNormal, TBN));

                // Fresnel
                float NdotV = dot(worldNormalFromTS, WorldViewDirection);
                float fresnelPow = pow(max(1.0 - NdotV, 0.0001), _PowerFresnel);
                float4 fresnelColored = clamp(_ColorFresnel * (-0.05 + fresnelPow), float4(0,0,0,0), float4(1,1,1,0));
                float4 fresnelOut = (_FresnelStrength > 0.0) ? fresnelColored : float4(0,0,0,0);
                float fresnelStrengthClamped = clamp(_FresnelStrength, -1.0, 75.0);

                // 反射
                float3 reflDir = reflect(-WorldViewDirection, worldNormalFromTS);
                float4 cubeColor = SAMPLE_TEXTURECUBE_LOD(_CubeMap, sampler_CubeMap, reflDir, _BlurReflection);

                #ifdef _USECUBEMAP_OFF
                    float4 cubeUsed = 1.0.xxxx;
                #else
                    float4 cubeUsed = cubeColor;
                #endif
                float4 reflectionColor =
                    (fresnelOut * fresnelStrengthClamped) * cubeUsed
                    + (cubeColor * (cubeColor.a * _ReflectionIntensity) * _ColorCubemap);

                // 透明度
                float Alpha = saturate(_Opacity);       // 1 = 更不透明；0 = 更透明
                float3 Emission = _EmissionColor.rgb * _EmissiveIntensity;
                // 屏幕空间折射
                float3 viewN = mul(float4(normalize(WorldNormal), 0.0), UNITY_MATRIX_V).xyz;
                float refractionScale = -0.5 + (_Refraction) * (1.0 / 2.0);

                float2 screenUV = IN.screenPos.xy / IN.screenPos.w;
                float2 refractUV = screenUV + (tNormal.xy + viewN.xy) * refractionScale;
                float3 sceneRefract = SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, refractUV).rgb;
                


                // 自发光
                float3 surfaceEmission = reflectionColor.rgb + Emission + sceneRefract * (1.0 - Alpha);

                // 金属/光滑度
                float4 mrTex =  SAMPLE_TEXTURE2D(_MetallicGlossMap, sampler_MetallicGlossMap, IN.uvMR);
                float Metallic   = _Metallic * mrTex.r;
                float Smoothness = _Glossiness * mrTex.a;

                // 送入 URP PBR
                InputData inputData;
                inputData.positionWS = WorldPosition;
                inputData.viewDirectionWS = WorldViewDirection;

                // Shadows
                inputData.shadowCoord = float4(0, 0, 0, 0);

                inputData.normalWS = NormalizeNormalPerPixel(worldNormalFromTS);

                inputData.fogCoord = IN.fogFactorAndVertexLight.x;

                inputData.vertexLighting = IN.fogFactorAndVertexLight.yzw;
;
                inputData.bakedGI = 0;

                half4 color = UniversalFragmentPBR(
                    inputData,
                    Albedo.rgb,
                    Metallic,
                    /*Specular*/ 0.5,
                    Smoothness,
                    /*Occlusion*/ 1.0,
                    /*Emission*/ surfaceEmission,
                    /*Alpha*/    Alpha
                );

                color.rgb = MixFog(color.rgb, IN.fogFactorAndVertexLight.x);
                color.a=1.0;
                return color;
                //return float4(SAMPLE_TEXTURE2D_X(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, uv).rgb, 1);
            }

            ENDHLSL
        }
    }

    Fallback "Hidden/InternalErrorShader"
}
