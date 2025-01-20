// UPR管线
// 带一个曲面细分着色器
Shader "Roystan/Grass"
{
    Properties
    {
		[Header(Color)]
        _TopColor("Top Color", Color) = (1,1,1,1)
		_BottomColor("Bottom Color", Color) = (1,1,1,1)
		_TranslucentGain("Translucent Gain", Range(0,1)) = 0.5

		[Header(Shape)]
		_BladeWidth("Width",Float) = 0.1
		_BladeWidthRandom("Width Random",Float) = 0.02

		_BladeHeight("Height",Float) = 0.5
		_BladeHeightRandom("Height Random",Float) = 0.3

		[Header(Tess)]
		_TessellationUniform("Tessellation Uniform",Range(1, 64)) = 1

		[Toggle(_FLAT_TOP)]_EnableFlatTop ("Enable Flat Top", Float) = 0
		_FlatAmount("FlatAmount", Range(0.1,1)) = 0.5

		[Header(Rotate)]
		[Toggle(_ROTATE)]_RandomRotate ("Random Rotate", Float) = 0

//		[Header(Shadow)]
//		[Toggle(_SHADOWCAST)]_ShadowCast ("Shadow Cast", Float) = 0

		[Header(Bend)]
		_BendRotationRandom("Bend Random",Range(-1, 1)) = 0.2
		_BladeForward("Blade Forward Amount", Float) = 0.38 // 控制偏移量
		_BladeCurve("Blade Curvature Amount", Range(1, 4)) = 2 // 控制曲线幂次

		[Header(Wind)]
		_WindDistortionMap("Wind Distortion Map", 2D) = "white" {}
		_WindFrequency("Wind Frequency", Vector) = (0.05, 0.05, 0, 0)
		_WindStrength("Wind Strength", Float) = 1
    }

	SubShader
    {
		HLSLINCLUDE

		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"


		#define BLADE_SEGMENTS 3 // 定义三角叶片片元分段数量
		#define UNITY_PI            3.14159265359f
		#define UNITY_TWO_PI        6.28318530718f

		float _BladeWidth;
		float _BladeWidthRandom;
		float _BladeHeight;
		float _BladeHeightRandom;
		float _FlatAmount;

		#pragma shader_feature _FLAT_TOP
		#pragma shader_feature _ROTATE



		float _BendRotationRandom;
		float _BladeForward;
		float _BladeCurve;
	
		//_TessellationUniform 已在CustomTessellation.cginc中声明

		sampler2D _WindDistortionMap;
		float4 _WindDistortionMap_ST;

		float2 _WindFrequency;
		float _WindStrength;

//CustomTessellation.cginc 已经包含 vertexInput 、vertexOutput 和顶点着色器（附在代码最后注释）
			
//#include "CustomTessellation.cginc"// 曲面细分着色器文件，通过和shader的相对路径引用
		struct vertexInput
		{
			float4 vertex : POSITION;
			float3 normal : NORMAL;
			float4 tangent : TANGENT;
		};

		struct vertexOutput
		{
			float4 vertex : SV_POSITION;
			float3 normal : NORMAL;
			float4 tangent : TANGENT;
		};

		// 顶点着色器vert只是将输入直接传递到曲面细分阶段
		// 创建vertexOutput结构体的工作由tessVert函数负责，该函数在domain shader内部调用
		// TESS的流程：Hull shader → Tessellation Primitive Generator → Domain shader
		vertexInput vert(vertexInput v)
		{
			return v;
		}

		vertexOutput tessVert(vertexInput v)
		{
			vertexOutput o;
			// Note that the vertex is NOT transformed to clip
			// space here; this is done in the grass geometry shader.
			o.vertex = v.vertex;
			o.normal = v.normal;
			o.tangent = v.tangent;
			return o;
		}


		struct TessellationFactors 
		{
			float edge[3] : SV_TessFactor;
			float inside : SV_InsideTessFactor;
		};

		float _TessellationUniform;
		TessellationFactors patchConstantFunction (InputPatch<vertexInput, 3> patch)
		{
			TessellationFactors f;
			f.edge[0] = _TessellationUniform;
			f.edge[1] = _TessellationUniform;
			f.edge[2] = _TessellationUniform;
			f.inside = _TessellationUniform;
			return f;
		}

		[domain("tri")]
		[outputcontrolpoints(3)]
		[outputtopology("triangle_cw")]
		[partitioning("integer")]
		[patchconstantfunc("patchConstantFunction")]
		vertexInput hull (InputPatch<vertexInput, 3> patch, uint id : SV_OutputControlPointID)
		{
			return patch[id];
		}

		[domain("tri")]
		vertexOutput domain(TessellationFactors factors, OutputPatch<vertexInput, 3> patch, float3 barycentricCoordinates : SV_DomainLocation)
		{
			vertexInput v;

			#define MY_DOMAIN_PROGRAM_INTERPOLATE(fieldName) v.fieldName = \
				patch[0].fieldName * barycentricCoordinates.x + \
				patch[1].fieldName * barycentricCoordinates.y + \
				patch[2].fieldName * barycentricCoordinates.z;

			MY_DOMAIN_PROGRAM_INTERPOLATE(vertex)
			MY_DOMAIN_PROGRAM_INTERPOLATE(normal)
			MY_DOMAIN_PROGRAM_INTERPOLATE(tangent)

			return tessVert(v);
		}

// 曲面细分部分结束
		// 基于位置的伪随机数生成函数，Returns a number in the 0...1 range.
		// 因为 GPU 着色器不支持传统的随机数生成器，所以需要通过数学操作来生成伪随机数
		float rand(float3 co)
		{
			return frac(sin(dot(co.xyz, float3(12.9898, 78.233, 53.539))) * 43758.5453);
			// Simple noise function, sourced from http://answers.unity.com/answers/624136/view.html
			// Extended discussion on this function can be found at the following link:
			// https://forum.unity.com/threads/am-i-over-complicating-this-random-function.454887/#post-2949326
		}
		// 用于生成绕轴旋转矩阵
		float3x3 AngleAxis3x3(float angle, float3 axis)
		{
			float c, s;
			sincos(angle, s, c);

			float t = 1 - c;
			float x = axis.x;
			float y = axis.y;
			float z = axis.z;

			return float3x3(
				t * x * x + c, t * x * y - s * z, t * x * z + s * y,
				t * x * y + s * z, t * y * y + c, t * y * z - s * x,
				t * x * z - s * y, t * y * z + s * x, t * z * z + c
				);
		// Construct a rotation matrix that rotates around the provided axis, sourced from:
		// https://gist.github.com/keijiro/ee439d5e7388f3aafc5296005c8c3f33
		}


		// 几何着色器输出结构体
		struct geometryOutput 
		{
			float4 pos : SV_POSITION;
			float2 uv : TEXCOORD0;// 用于颜色采样

//			unityShadowCoord4 _ShadowCoord : TEXCOORD1; // 阴影坐标，用来采样阴影贴图
			float3 worldPos : TEXCOORD2; // 世界空间位置
			float3 normal : NORMAL;

		};


        // 几何着色器输出内容，被几何着色器调用，包含了新生成顶点可以复用的函数
		geometryOutput GenerateGrassVertex(float3 vertexPosition, float width, float height, float forward, float2 uv, float3x3 transformMatrix)
		{
			geometryOutput o;
			float3 tangentPoint = float3(width, forward, height);
			// 切线，计算光照
			float3 tangentNormal = float3(0, -1, forward);// 按比例缩放法线的Z轴
			float3 localNormal = mul(transformMatrix, tangentNormal);
			float3 localPosition = vertexPosition + mul(transformMatrix, tangentPoint);

			o.pos = TransformObjectToHClip(localPosition); 	//几何着色器作用在顶点着色器进行裁剪变换之前，所以需要在几何着色器内进行变换
			o.uv = uv;// 要给新生成的三角面片赋予UV坐标，用于后续着色
			o.worldPos = TransformObjectToWorld(localPosition);
			o.normal = TransformObjectToWorldNormal(localNormal);
			return o;

		}

		
		// Geometry shader
		// 这里将顶点作为输入，输出一个三角形来表示一片草叶
		[maxvertexcount((BLADE_SEGMENTS+ 1) * 2 )] //是几何着色器中的一个属性，定义了几何着色器可以输出的最大顶点数。
		void geo(triangle vertexOutput IN[3] : SV_POSITION, inout TriangleStream<geometryOutput> triStream)
		{
			// 采用单个三角形作为输入（3个点），但是只取其中第一个顶点IN[0]生成草，避免冗余
			float3 pos = IN[0].vertex.xyz;

			// 构建从模型空间到切线空间的变换矩阵，用列向量表示（右乘）
			float3 vNormal = IN[0].normal;
			float4 vTangent = IN[0].tangent;
			float3 vBinormal = cross(vNormal, vTangent.xyz) * vTangent.w;// 不同的3D 工具或贴图流程可能默认生成不同的UV手性，切线的w分量被用来明确切线空间的手性

			float3x3 tangentToLocal = float3x3(
				vTangent.x, vBinormal.x, vNormal.x,
				vTangent.y, vBinormal.y, vNormal.y,
				vTangent.z, vBinormal.z, vNormal.z
				);

			// 添加随机朝向
				// 自定义函数AngleAxis3x3 接受一个弧度制角度和旋转轴，返回一个绕轴旋转该角度的旋转矩阵
				// 自定义伪随机数生成函数 rand 生成一个0-1的数，乘2pie，得到一个随机弧度值
				// 垂直方向（切线空间Z）
			#ifdef _ROTATE
				float3x3 facingRotationMatrix = AngleAxis3x3( rand(pos) * UNITY_TWO_PI, float3(0,0,1));
			#else
				float3x3 facingRotationMatrix =  float3x3(
					1, 0, 0,
					0, 1, 0,
					0, 0, 1
					);
			#endif
				// 水平方向（这里用X）
			float3x3 bendRotationMatrix = AngleAxis3x3( rand(pos.zzx) * _BendRotationRandom * UNITY_PI * 0.5, float3(-1,0,0));

			// 用于采样风纹理的uv，随时间变化
			float2 uv = pos.xz * _WindDistortionMap_ST.xy + _WindDistortionMap_ST.zw + _WindFrequency * _Time.y;
			// 将风纹理的采样值从 [0，1] 范围调整为 [-1，1] 
			float2 windSample = (tex2Dlod(_WindDistortionMap, float4(uv, 0, 0)).xy * 2 - 1) * _WindStrength;
			// 表示风向的归一化向量
			float3 wind = normalize(float3(windSample.x, windSample.y, 0));
			float3x3 windRotation = AngleAxis3x3(UNITY_PI * windSample, wind);

			// 添加随机的可调宽度和高度，以及前向偏移量
			float width = (rand(pos.zyx) * 2 - 1) * _BladeWidthRandom + _BladeWidth;
			float height = (rand(pos.xzy) * 2 - 1) * _BladeHeightRandom + _BladeHeight;
			float forward = rand(pos.yyz) * _BladeForward;

			// 变换矩阵
			// 左乘tangentToLocal，等于将偏移localToTargent（使用逆矩阵）
			// 偏移需要调换YZ轴 在切线空间中，惯例通常规定向上方向沿Z轴而不是Y轴
			// 切线空间偏移量，绕轴旋转
			float3x3 transformationMatrixFacing = mul(tangentToLocal, facingRotationMatrix);
			// 切线空间偏移量，轴旋转 + 叶片弯曲 + 风扰动
			float3x3 transformationMatrix =  mul(mul(mul(tangentToLocal, windRotation), facingRotationMatrix), bendRotationMatrix);// 列优先，右乘

			// 循环，变量t表示在叶片中的分段位置
			for (int i = 0; i < BLADE_SEGMENTS; i++)
			{
				float t = i / (float)BLADE_SEGMENTS;
				// 分段顶点的高度和宽度
				float segmentHeight = height * t;
				float segmentWidth = width * (1 - t);
				float segmentForward = pow(t, _BladeCurve) * forward;

				// 如果i = 0，说明是底边，使用只改变朝向的变换矩阵；如果i ≠ 0 , 使用完整的变换矩阵
				float3x3 transformMatrix = i == 0 ? transformationMatrixFacing : transformationMatrix;
				// 新顶点生成后调用 Append() 方法，将其添加到三角形流中
				triStream.Append( GenerateGrassVertex(pos, -segmentWidth, segmentHeight, segmentForward, float2(0, t), transformMatrix));
				triStream.Append( GenerateGrassVertex(pos, segmentWidth, segmentHeight, segmentForward, float2(1, t), transformMatrix));
			}
			#ifdef _FLAT_TOP
				// 顶点两个，平头
				float topWidth = (1/(float)BLADE_SEGMENTS) * _FlatAmount * width;
				triStream.Append(GenerateGrassVertex(pos, -topWidth, height, forward, float2(0.5, 1), transformationMatrix));    
				triStream.Append(GenerateGrassVertex(pos, topWidth, height, forward, float2(0.5, 1), transformationMatrix));    
			#else
				// 顶点一个，尖头
				triStream.Append(GenerateGrassVertex(pos, 0, height, forward, float2(0.5, 1), transformationMatrix));
			#endif

		}
	ENDHLSL

  
		

		// 用于着色的Pass
        Pass
        {
			Cull Off
			Tags
			{
				"RenderType" = "Opaque"
				"LightMode" = "UniversalForward"
			}

            HLSLPROGRAM 
			
            #pragma vertex vert
            #pragma fragment frag
			#pragma geometry geo
			#pragma target 4.6

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
			#pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _SHADOWS_SOFT

			// 曲面细分
			#pragma hull hull
			#pragma domain domain




			// 渐变色混合
			float4 _TopColor;
			float4 _BottomColor;
			float _TranslucentGain;

			float4 frag (geometryOutput i, half facing : VFACE) : SV_Target
			// 因为我们的着色器将Cull设置为Off ，所以草叶的两侧都会被渲染。为了确保法线面向正确的方向，我们使用片段着色器中包含的可选VFACE参数
            {	
					float4 SHADOW_COORDS = TransformWorldToShadowCoord(i.worldPos);
//					Light mainLight = GetMainLight(SHADOW_COORDS);
					half shadow = MainLightRealtimeShadow(SHADOW_COORDS);

					// 如果查看表面的正面， fixed facing参数将返回正数，如果查看背面，则返回负数。
					float3 normal = facing > 0 ? i.normal : -i.normal;
//					float3 lightDir = normalize(_MainLightPosition.xyz - i.worldPos.xyz);

					
					float NdotL = saturate(saturate(dot(normal, _MainLightPosition.xyz)) + _TranslucentGain) * shadow;

					
					half3 ambient = _GlossyEnvironmentColor.xyz;
					//float3 ambient = UNITY_LIGHTMODEL_AMBIENT.xyz;
					float4 lightIntensity = NdotL * _MainLightColor + float4( ambient, 1);

					float4 col = lerp(_BottomColor, _TopColor * lightIntensity, i.uv.y);

					return col;

	//			return lerp(_BottomColor, _TopColor, i.uv.y);
            }
            ENDHLSL
        }


		
		
		Pass
		{
			Tags
			{
				"LightMode" = "ShadowCaster"
			}
			HLSLPROGRAM
			#pragma vertex vert
			#pragma geometry geo
			#pragma fragment frag
			#pragma hull hull
			#pragma domain domain
			#pragma target 4.6
			#pragma multi_compile_shadowcaster
				
				float4 frag(geometryOutput i) : SV_Target
				{
					float4 color;
					color.xyz=float3(0.0,0.0,0.0);
					return color;
				}
				
			ENDHLSL
		}
		
    }
}


