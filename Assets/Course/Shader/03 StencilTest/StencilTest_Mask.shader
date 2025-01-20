Shader "Lit/StencilTest/Mask"  
{
	Properties
	{
		_ID("Mask ID", Int) = 1
	}
	SubShader
	{
		Tags{ "RenderType" = "Opaque" "Queue" = "Geometry+1" }// 模板测试的顺序在AlphaTest之前，在不透明物体渲染之后
		ColorMask 0 // 不输出颜色
		ZWrite off			
		Stencil{
			Ref[_ID]
			Comp always // 比较操作，默认always，总是通过
			Pass replace // 默认keep，将参考值写入缓冲
			//Fail Keep
			//Zfail keep
		}

		Pass{
			CGINCLUDE

			struct appdata 
			{
			float4 vertex : POSITION;
		    };
			struct v2f 
			{
				float4 pos : SV_POSITION;
			};
 
 
			v2f vert(appdata v) 
			{
				v2f o;
				o.pos = UnityObjectToClipPos(v.vertex);
				return o;
			}
			half4 frag(v2f i) : SV_Target
			{
				return half4(1,1,1,1);
			}
		ENDCG
		}
	}
}