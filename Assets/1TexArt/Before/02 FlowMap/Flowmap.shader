Shader "Unlit/FlowMap"
{
    Properties
    {
        _MainTex ("FlowTex", 2D) = "white" {}
        _Color("Tint",Color) = (1,1,1,1)

        _FlowMap("FlowMap", 2D) = "white" {}
        _FlowSpeed("FlowSpeed",float) = 0.1
        _TimeSpeed("TimeSpeed",float) = 1.0
        [Toggle]_REVERSE_FLOW("ReverseFlow",Int) = 0
    }
    SubShader
    {
        Tags { 
            "IgnoreProjector" = "True" 
            "RenderType" = "Opaque" 
            "RenderType"="Opaque" }// 透明"RenderType"="Transparent"
        LOD 100

        Cull Off
        Lighting Off
        ZWrite On
        // 混合模式
        // Blend One OneMinusSrcAlpha

        Pass
        {
            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            // make fog work
            #pragma multi_compile_fog

            #pragma shader_feature _REVERSE_FLOW_ON

            #include "UnityCG.cginc"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                UNITY_FOG_COORDS(1)
                float4 vertex : SV_POSITION;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            fixed4 _Color;
            sampler2D _FlowMap;
            float _FlowSpeed;
            float _TimeSpeed;


            v2f vert (appdata v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                UNITY_TRANSFER_FOG(o,o.vertex);
                return o;
            }

            fixed4 frag (v2f i) : SV_Target
            {
                // 从Flowmap中获取向量场信息并映射到[-1, 1] 
                float2 flowDir = tex2D(_FlowMap, i.uv).rg * 2.0 - 1.0;
                
                flowDir *= _FlowSpeed;
                // 如果勾选则反转流向
                #ifdef _REVERSE_FLOW_ON
                flowDir *= -1;
                #endif

                // 构造周期相同，相位相差半个周期的函数
                float phase0 = frac(_Time * 0.1 * _TimeSpeed);
                float phase1 = frac(_Time * 0.1 * _TimeSpeed + 0.5);

                // 偏移UV后两次采样
                float2 tiling_uv = i.uv * _MainTex_ST.xy + _MainTex_ST.zw;
                half3 tex0 = tex2D(_MainTex, tiling_uv - flowDir * phase0);
                half3 tex1 = tex2D(_MainTex, tiling_uv - flowDir * phase1);

                // 构造函数计算随波形函数变化的权重（变化到最夸张的时候权重刚好变化到0），混合两次采样，构建比较平滑的循环
                float flowLerp = abs((0.5 - phase0) / 0.5);
                half3 finalColor = lerp(tex0, tex1, flowLerp);

                fixed4 col = float4(finalColor,1.0) * _Color;
                // apply fog
                UNITY_APPLY_FOG(i.fogCoord, col);
                return col;
            }
            ENDCG
        }
    }
}
