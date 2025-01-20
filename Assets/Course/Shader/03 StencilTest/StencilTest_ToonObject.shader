Shader "Lit/StencilTest/Object" 
{
	Properties {
		_Color ("ColorTint", Color) = (0.5,0.5,0.5,1)
		_MainTex ("Base (RGB)", 2D) = "white" {}
		_Ramp ("Toon Ramp (RGB)", 2D) = "gray" {} 
		_ID("Mask ID", Int) = 1
        _Specular ("Specular", Color) = (1, 1, 1, 1)
		_Gloss ("Gloss", Range(8.0, 256)) = 20
	}

	SubShader {
		Tags { "RenderType"="Opaque" "Queue" = "Geometry+2"}// Mask 的 队列是Geometry+1，Object在Mask之后渲染
		LOD 200
		
		Stencil {
			Ref [_ID]
			Comp equal
		}

		// 后面是光照模型部分--半罗伯特RampTex	
        Pass {

            CGPROGRAM

            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"
            #include "Lighting.cginc"

            sampler2D _MainTex;
            sampler2D _Ramp;
            fixed4 _Color;
            float4 _MainTex_ST;
			fixed4 _Specular;
			float _Gloss;
            

            struct appdata {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float2 uv : TEXCOORD0;
            };

            struct v2f {
                float4 pos : SV_POSITION;
                float3 worldNormal : TEXCOORD0;
                float3 worldPos : TEXCOORD1;
                float2 uv : TEXCOORD2;
            };

            v2f vert (appdata v) {
                v2f o;
                o.pos = UnityObjectToClipPos(v.vertex);
                o.worldNormal = UnityObjectToWorldNormal(v.normal);
                o.worldPos = mul(unity_ObjectToWorld, v.vertex).xyz;
                o.uv = v.uv * _MainTex_ST.xy + _MainTex_ST.zw;
                return o;
            }

            float4 frag (v2f i) : SV_Target {

                // Compute lighting
                fixed3 lightDir = normalize(UnityWorldSpaceLightDir(i.worldPos));
                fixed3 worldNormal = normalize(i.worldNormal);
                
                fixed3 ambient = UNITY_LIGHTMODEL_AMBIENT.xyz;

                // Half-Lambert for softer shadow transitions
                float lambert = dot(worldNormal, lightDir) * 0.5 + 0.5;
                fixed3 baseColor = tex2D(_MainTex, i.uv).rgb * _Color.rgb;
                float3 rampColor = tex2D(_Ramp, float2(lambert, lambert)).rgb;
                fixed3 diffuse = baseColor * rampColor * _LightColor0.rgb;

                fixed3 viewDir = normalize(UnityWorldSpaceViewDir(i.worldPos));
				fixed3 halfDir = normalize(lightDir + viewDir);
				fixed3 specular = _LightColor0.rgb * _Specular.rgb * pow(max(0, dot(worldNormal, halfDir)), _Gloss);

                return float4(ambient + diffuse + specular, 1.0);


            }
            ENDCG
        }
    }
    Fallback "Diffuse"
}                                                                                 
