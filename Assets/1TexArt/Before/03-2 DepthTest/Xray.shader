Shader "Unlit/Xray"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
        _XRayColor("Xray Color",Color) = (1,1,1,1)
    }
    SubShader
    {
        CGINCLUDE // 多Pass shader 方便复用着色器
        #include "UnityCG.cginc"
        
        sampler2D _MainTex;
        float4 _MainTex_ST;
        fixed4 _XRayColor;

        struct v2f
        {
            float4 vertex : SV_POSITION;
            fixed4 color : COLOR ; 
        };
// 使用顶点着色器计算，需要物体形状比较精细
        v2f vertXray (appdata_base v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);

                float3 normal = normalize(v.normal);
                float3 viewDir = normalize(ObjSpaceViewDir(v.vertex));//在模型空间上计算夹角
                float rim = 1 - dot(normal, viewDir);//边缘得到的数值大
                o.color = _XRayColor * rim ;
                return o;
            }

         fixed4 fragXray (v2f i) : SV_Target
             {
                 return i.color;
             }

        struct v2f2
        {
            float2 uv : TEXCOORD0;
            float4 vertex : SV_POSITION;
        };



        v2f2 vertBase (appdata_base v)
        {
            v2f2 o;
            o.vertex = UnityObjectToClipPos(v.vertex);
            o.uv = TRANSFORM_TEX(v.texcoord, _MainTex);
            return o;
        }

         fixed4 fragBase (v2f2 i) : SV_Target
             {
                 return tex2D(_MainTex, i.uv);
             }
         ENDCG

        // 顺序从上到下执行
        Pass //Xray
        {  
//            NAME "XRAY"
            // 用CGINCLUDE 写多个Pass但是只执行了第一个的原因可能是：urp管线下默认只渲染一个pass,
            // 给不同的pass加上不同"LightMode"的tag就可以同时渲染
            Tags { "RenderType" = "Transparent" "Queue" = "Transparent" "LightMode" = "SRPDefaultUnlit" }
            Blend OneMinusSrcAlpha One  //？
            ZTest Greater
            ZWrite Off
//           Cull Off
            CGPROGRAM
            #pragma vertex vertXray
            #pragma fragment fragXray 
            ENDCG
        }
        Pass //正常
        {
//           NAME "BASE"
            Tags { "RenderType" = "Opaque" "Queue" = "Geometry""LightMode" = "UniversalForward" }
            ZTest LEqual
            ZWrite On

            CGPROGRAM
            #pragma vertex vertBase
            #pragma fragment fragBase 
            ENDCG
        }
    }

}
