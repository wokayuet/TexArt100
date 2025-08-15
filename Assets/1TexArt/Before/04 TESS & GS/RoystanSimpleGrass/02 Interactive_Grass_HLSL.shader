// UPR管线
// 带一个曲面细分着色器
Shader "Roystan/Grass_Interactive"
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

		_Rad("Blade Radius", Range(0,1)) = 0.6

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
//		_WindDistortionMap("Wind Distortion Map", 2D) = "black" {}
//		_WindFrequency("Wind Frequency", Vector) = (0.05, 0.05, 0, 0)
		_WindStrength("Wind Strength", Float) = 1
		_WindSpeed("Wind Speed", Float) = 100

		[Header(Interactor)]
		_InteractRadius("Interact Radius", Float) = 0.3
		_InteractStrength("Interact Strength", Float) = 5

		[Header(LOD)]
		_MinDist("Min Distance", Float) = 40
		_MaxDist("Max Distance", Float) = 60
    }

	SubShader
    {
		HLSLINCLUDE
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Input.hlsl"
		#pragma shader_feature _FLAT_TOP
		#pragma shader_feature _ROTATE

		#define GrassSegments 5 // 定义三角叶片片元分段数量
		#define GrassBlades 4 // 定义每簇草叶片数量
//		#define BLADE_SEGMENTS 5 // 
//		#define BLADE_NUMBER 4 // 

		#define UNITY_PI            3.14159265359f
		#define UNITY_TWO_PI        6.28318530718f

		float _BladeWidth;
		float _BladeWidthRandom;
		float _BladeHeight;
		float _BladeHeightRandom;
		float _Rad;
		float _FlatAmount;

		//_TessellationUniform 已在CustomTessellation.cginc中声明

		float _BendRotationRandom;
		float _BladeForward;
		float _BladeCurve;

//		sampler2D _WindDistortionMap;
//		float4 _WindDistortionMap_ST;
//		float2 _WindFrequency;
		half _WindSpeed;
		float _WindStrength;

		half _InteractRadius, _InteractStrength;
		uniform float3 _PositionMoving;
		float _MinDist, _MaxDist;

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

        // 几何着色器输出内容，接受新顶点信息传递到片元着色器
		geometryOutput GenerateGrassVertex(float3 vertexPosition, float width, float height, float forward, float2 uv, float3x3 transformMatrix)
		{
			geometryOutput o;
			// 切线，计算光照
			float3 tangentNormal = float3(0, -1, forward);// 按比例缩放法线的Z轴
			float3 localNormal = mul(transformMatrix, tangentNormal);

			float3 tangentPoint = float3(width, height, forward);
			float3 localPosition = vertexPosition + mul(transformMatrix, tangentPoint);
			o.pos = TransformObjectToHClip(localPosition); 	//几何着色器作用在顶点着色器进行裁剪变换之前，所以需要在几何着色器内进行变换

			o.uv = uv;// 要给新生成的三角面片赋予UV坐标，用于后续着色
			o.worldPos = TransformObjectToWorld(localPosition);
			o.normal = TransformObjectToWorldNormal(localNormal);
			return o;
		}
		
		// Geometry shader
		// 这里将顶点作为输入，输出一个三角形来表示一片草叶
		[maxvertexcount(51)] //是几何着色器中的一个属性，定义了几何着色器可以输出的最大顶点数。
		void geo(point vertexOutput IN[1] : SV_POSITION, inout TriangleStream<geometryOutput> triStream)
		{
			// 采用单个三角形作为输入（3个点），但是只取其中第一个顶点IN[0]生成草，避免冗余
			float3 pos = IN[0].vertex.xyz;

			// 添加随机的可调宽度和高度，以及前向偏移量
			float forward = rand(pos.yyz) * _BladeForward;
			float width = (rand(pos.zyx) * 2 - 1) * _BladeWidthRandom + _BladeWidth;
			float height = (rand(pos.xzy) * 2 - 1) * _BladeHeightRandom + _BladeHeight;

			//// set grass height// 不是很懂，之后看看效果
			//_GrassHeight *= IN[0].uv.y;
			//_GrassHeight *= clamp(rand(IN[0].pos.xyz), 1 - _RandomHeight, 1 + _RandomHeight);
			//_GrassWidth *= IN[0].uv.x;


			// camera distance for culling 
			// 计算摄影机和顶点距离，小于_MinDist不剔除，大于_MaxDist剔除，作用于每簇草的叶片数量
			float3 worldPos = TransformObjectToWorld(pos);
			float distanceFromCamera = distance(worldPos, _WorldSpaceCameraPos);
			//float distanceFade = 1 - saturate((distanceFromCamera - _MinDist) / (_MaxDist  - _MinDist));
			 float distanceFade = 1 - saturate((distanceFromCamera - _MinDist) / _MaxDist );

			// 使用函数模拟风
			float3 wind = float3(sin(_Time.x * _WindSpeed + pos.x) + sin(_Time.x * _WindSpeed + pos.z * 2) + sin(_Time.x * _WindSpeed * 0.1 + pos.x), 0,
			cos(_Time.x * _WindSpeed + pos.x * 2) + cos(_Time.x * _WindSpeed + pos.z));
			wind *= _WindStrength;

			// Interactivity 交互部分
			float dis = distance(_PositionMoving, worldPos); // distance for radius
			float3 radius = 1 - saturate(dis / _InteractRadius); // in world radius based on objects interaction radius
			float3 sphereDisp = worldPos - _PositionMoving; // position comparison
			sphereDisp *= radius; // position multiplied by radius for falloff//应该是以个先增后减的过程？
			// increase strength
			sphereDisp = clamp(sphereDisp.xyz * _InteractStrength, -0.8, 0.8);

			for (int j = 0; j < (GrassBlades * distanceFade); j++)// 每叶片
			{
				// set rotation and radius of the blades
				// 只添加水平方向的旋转，这里用(0, 1, 0)，并添加微妙的垂直变化
				float3x3 facingRotationMatrix = AngleAxis3x3(rand(pos.xyz) * UNITY_TWO_PI + j, float3(0, 1, -0.1));
				float3x3 transformationMatrix = facingRotationMatrix;// 这个shader只使用了水平旋转1个变换
				float radius = j / (float)GrassBlades;
				float offset = (1 - radius) * _Rad;// 分段会围绕中心逐段前后偏移
				for (int i = 0; i < GrassSegments; i++)// 每分段
				{
					// taper width, increase height;
					float t = i / (float)GrassSegments;
					float segmentHeight = height * t;
					float segmentWidth = width * (1 - t);

					// the first (0) grass segment is thinner
					segmentWidth = i == 0 ? width * 0.3 : segmentWidth;

					float segmentForward = pow(t, _BladeCurve) * forward + offset;

					// Add below the line declaring float segmentWidth.
					float3x3 transformMatrix = i == 0 ? facingRotationMatrix : transformationMatrix;

					// first grass (0) segment does not get displaced by interactivity
					float3 newPos = i == 0 ? pos : pos + ((float3(sphereDisp.x, sphereDisp.y, sphereDisp.z) + wind) * t);

					// every segment adds 2 new triangles
					//               GenerateGrassVertex(float3 vertexPosition, float width, float height, float forward, float2 uv, float3x3 transformMatrix)
					triStream.Append(GenerateGrassVertex(newPos, -segmentWidth, segmentHeight, segmentForward, float2(0, t), transformMatrix));
					triStream.Append(GenerateGrassVertex(newPos, segmentWidth, segmentHeight, segmentForward, float2(1, t), transformMatrix));
				}
				// Add just below the loop to insert the vertex at the tip of the blade.
				triStream.Append(GenerateGrassVertex(pos + float3(sphereDisp.x * 1.5, sphereDisp.y, sphereDisp.z * 1.5) + wind, 0, height, forward + offset, float2(0.5, 1), transformationMatrix));
				// restart the strip to start another grass blade
				triStream.RestartStrip();
			}
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


