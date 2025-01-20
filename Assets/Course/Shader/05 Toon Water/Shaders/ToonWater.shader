Shader "Roystan/Toon/Water"
{
    Properties
    {	
        _DepthGradientShallow("Depth Gradient Shallow", Color) = (0.325, 0.807, 0.971, 0.725)
        _DepthGradientDeep("Depth Gradient Deep", Color) = (0.086, 0.407, 1, 0.749)
        _DepthMaxDistance("Depth Maximum Distance", Float) = 1
    }
    SubShader
    {
        Tags { "RenderType" = "Opaque" "Queue" = "Transparent" }
        Pass
        {
 //           ZWrite Off
//			HLSLPROGRAM
           CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

          //  #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
          //  #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
          //  #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
          #include "UnityCG.cginc"
            

            float4 _DepthGradientShallow;
            float4 _DepthGradientDeep;
            float _DepthMaxDistance;

            // 相机的深度纹理,是一种灰度图像，根据对象与相机的距离对对象进行着色
            // 在 Unity 中，靠近相机的物体颜色更白，而距离相机更远的物体颜色更暗
            // 需要检查相机的 Depth texture 是否开启
            // 深度纹理是全屏纹理, full-screen texture
            // 需要在顶点着色器中计算顶点的屏幕空间位置，传送到片段着色器中采样
            sampler2D _CameraDepthTexture;
 //           TEXTURE2D_X_FLOAT(_CameraDepthTexture);
//            SAMPLER(sampler_CameraDepthTexture);
            struct appdata
            {
                float4 vertex : POSITION;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float4 screenPosition : TEXCOORD2;
            };

            v2f vert (appdata v)
            {
                v2f o;

 //               o.vertex = TransformObjectToHClip(v.vertex);
                o.vertex = UnityObjectToClipPos(v.vertex);
                // 计算顶点的屏幕空间坐标
                o.screenPosition = ComputeScreenPos(o.vertex);

                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                // tex2Dproj: 根据投影纹理坐标  (uv / w) 进行采样
                float existingDepth01 = tex2Dproj(_CameraDepthTexture, UNITY_PROJ_COORD(i.screenPosition)).r;
                float existingDepthLinear = LinearEyeDepth(existingDepth01);

                //float2 screenPos= i.screenPosition .xy / i.screenPosition .w;
                // 根据屏幕坐标位置对深度纹理进行采样
                //loat existingDepth01 = SAMPLE_TEXTURE2D_X(_CameraDepthTexture, sampler_CameraDepthTexture, screenPos).r;
                // 将非线性深度转换为线性深度
                //float existingDepthLinear = Linear01Depth(existingDepth01, _ZBufferParams);

				float depthDifference = existingDepthLinear - i.screenPosition.w;

                float waterDepthDifference01 = saturate(depthDifference / _DepthMaxDistance);
                float4 waterColor = lerp(_DepthGradientShallow, _DepthGradientDeep, waterDepthDifference01);

                return waterColor;
            }
            ENDCG
            //ENDHLSL

        }
    }
}