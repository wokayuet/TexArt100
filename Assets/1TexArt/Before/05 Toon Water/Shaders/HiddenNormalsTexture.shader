Shader "Hidden/Roystan/Normals Texture"
{
    Properties
    {
    }
    SubShader
    {
        Tags 
		{ 
			"RenderType" = "Opaque" 
            "LightMode" = "UniversalForward"
		}

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "HLSLsupport.cginc"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
				float3 normal : NORMAL;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
				float3 viewNormal : NORMAL;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.viewNormal = normalize(mul((float3x3)UNITY_MATRIX_IT_MV, v.normal));
                //  o.viewNormal = COMPUTE_VIEW_NORMAL;
                return o;
            }

            float4 frag (v2f i) : SV_Target
            {
                return float4(i.viewNormal, 0);
            }
            ENDHLSL
        }
    }
}
