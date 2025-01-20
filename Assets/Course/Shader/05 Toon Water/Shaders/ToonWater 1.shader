Shader "Roystan/Toon/Water2"
{
    Properties
    {	
        _DepthGradientShallow("Depth Gradient Shallow", Color) = (0.325, 0.807, 0.971, 0.725)
        _DepthGradientDeep("Depth Gradient Deep", Color) = (0.086, 0.407, 1, 0.749)
        _DepthMaxDistance("Depth Maximum Distance", Float) = 1

        _SurfaceNoise("Surface Noise", 2D) = "white" {}
        _SurfaceNoiseScroll("Surface Noise Scroll Amount", Vector) = (0.03, 0.03, 0, 0)

        _SurfaceNoiseCutoff("Surface Noise Cutoff", Range(0, 1)) = 0.777
        _FoamMinDistance("Foam Minimum Distance", Float) = 0.04
        _FoamMaxDistance("Foam Maximum Distance", Float) = 0.4
        _FoamColor("Foam Color", Color) = (1,1,1,1)

        // FlowMap, Two channel distortion texture.
        _SurfaceDistortion("Surface Distortion", 2D) = "white" {}	
        _SurfaceDistortionAmount("Surface Distortion Amount", Range(0, 1)) = 0.27

    }
    SubShader
    {
        
        Tags { "RenderType" = "Transparent" "Queue" = "Transparent" }

        Pass{
        Blend SrcAlpha OneMinusSrcAlpha
        ZWrite Off

			HLSLPROGRAM
          // CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "HLSLsupport.cginc"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            
            #define SMOOTHSTEP_AA 0.01

            float4 _DepthGradientShallow;
            float4 _DepthGradientDeep;
            float _DepthMaxDistance;

            // 相机的深度纹理,是一种灰度图像，根据对象与相机的距离对对象进行着色
            // 在 Unity 中，靠近相机的物体颜色更白，而距离相机更远的物体颜色更暗
            // 需要检查相机的 Depth texture 是否开启
            // 深度纹理是全屏纹理, full-screen texture
            // 需要在顶点着色器中计算顶点的屏幕空间位置，传送到片段着色器中采样
            sampler2D _CameraDepthTexture;
            sampler2D _CameraNormalsTexture;

            sampler2D _SurfaceNoise;
            float4 _SurfaceNoise_ST;

            float _SurfaceNoiseCutoff;
            float _FoamMaxDistance;
            float _FoamMinDistance;
            float4 _FoamColor;

            sampler2D _SurfaceDistortion;
            float4 _SurfaceDistortion_ST;
            float _SurfaceDistortionAmount;

            float2 _SurfaceNoiseScroll;

            struct appdata
            {
                float4 vertex : POSITION;
                float4 uv : TEXCOORD0;
                float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float2 distortUV : TEXCOORD1;
                float2 noiseUV : TEXCOORD0;
                float4 screenPosition : TEXCOORD2;
                float3 viewNormal : NORMAL;
            };
            // 透明度混合函数，用于混合水体和泡沫颜色
            float4 alphaBlend(float4 top, float4 bottom)
            {
	            float3 color = (top.rgb * top.a) + (bottom.rgb * (1 - top.a));
	            float alpha = top.a + bottom.a * (1 - top.a);

	            return float4(color, alpha);
            }

            v2f vert (appdata v)
            {
                v2f o;

               o.vertex = TransformObjectToHClip(v.vertex);
                //o.vertex = UnityObjectToClipPos(v.vertex);
                // 计算顶点的屏幕空间坐标
                o.screenPosition = ComputeScreenPos(o.vertex);
                o.distortUV = TRANSFORM_TEX(v.uv, _SurfaceDistortion);
                o.noiseUV = TRANSFORM_TEX(v.uv, _SurfaceNoise);
                o.viewNormal = normalize(mul((float3x3)UNITY_MATRIX_IT_MV, v.normal));
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                // 根据屏幕坐标位置对深度纹理进行采样
                // tex2Dproj: 根据投影纹理坐标  (uv / w) 进行采样
               float existingDepth01 = tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPosition)).r;

                // 将非线性深度转换为线性深度
                float existingDepthLinear = LinearEyeDepth(existingDepth01, _ZBufferParams);
                // 相对水面深度
                // i.screenPosition.w 代表了深度的投影部分，也就是裁剪空间的深度信息，它与实际的物体距离有关
				float depthDifference = existingDepthLinear - i.screenPosition.w;

                // 水面深度渐变色
                float waterDepthDifference01 = saturate(depthDifference / _DepthMaxDistance);
                float4 waterColor = lerp(_DepthGradientShallow, _DepthGradientDeep, waterDepthDifference01);

                // UV动画
                float2 distortSample = (tex2D(_SurfaceDistortion, i.distortUV).xy * 2 - 1) * _SurfaceDistortionAmount;// 调整方向向量到[-1,1]
                float2 noiseUV = float2((i.noiseUV.x + _Time.y * _SurfaceNoiseScroll.x) + distortSample.x, 
                (i.noiseUV.y + _Time.y * _SurfaceNoiseScroll.y) + distortSample.y);
                //float2 noiseUV = float2(i.noiseUV.x + _Time.y * _SurfaceNoiseScroll.x, i.noiseUV.y + _Time.y * _SurfaceNoiseScroll.y);
                // 水面波动
                float surfaceNoiseSample = tex2D(_SurfaceNoise, noiseUV).r;
                
                // 通过摄像机渲染到纹理的法线采样，获得水面下对象法线
                float3 existingNormal = tex2Dproj(_CameraNormalsTexture, UNITY_PROJ_COORD(i.screenPosition));
                float3 normalDot = saturate(dot(existingNormal, i.viewNormal));
                // 点积越小（接近 0），水面水底法线差异越大，foamDistance越大
                float foamDistance = lerp(_FoamMaxDistance, _FoamMinDistance, normalDot);
                // 岸边泡沫
                float foamDepthDifference01 = saturate(depthDifference / foamDistance);
                // depthDifference越小=水越浅；foamDistance越大=交界处；留白越多
                float surfaceNoiseCutoff = foamDepthDifference01 * _SurfaceNoiseCutoff;// Cutoff越小，保留的白色概率越多

                // 类似曲线，调整噪声的显示区域
                // 任何比截止阈值暗的值都会被忽略，而任何高于截止阈值的值都会被完全绘制为白色
                // float surfaceNoise = surfaceNoiseSample > surfaceNoiseCutoff ? 1 : 0;
                float surfaceNoise = smoothstep(surfaceNoiseCutoff - SMOOTHSTEP_AA, surfaceNoiseCutoff + SMOOTHSTEP_AA, surfaceNoiseSample);

                float4 surfaceNoiseColor = _FoamColor* surfaceNoise;
                //float4 surfaceNoiseColor = _FoamColor;
              //  surfaceNoiseColor.a *= surfaceNoise;不懂为什么要分开

                return alphaBlend(surfaceNoiseColor, waterColor);

            }
            //ENDCG
            ENDHLSL

        }
    }
}