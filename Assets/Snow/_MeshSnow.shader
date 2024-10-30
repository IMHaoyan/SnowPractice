Shader "Test"
{
    Properties
    {
        _TopTex("Top Map",2D) = "white"{}
        _NormalMap("Normal Map", 2D) = "bump"{}

        [Header(Tessellation)]
        _Tess("Tessellation", Range(1, 64)) = 64
        _MaxTessDistance("Max Tess Distance", Range(1, 128)) = 20
        _MinTessDistance("Min Tess Distance", Range(1, 128)) = 1

        [Space(20)]
        [Header(Color)]
        [HDR]_BrightCol ("亮部色", color) = (1.0, 1.0, 1.0, 1.0)
        _DarkCol ("暗部色", color) = (0.1, 0.1, 0.1, 1.0)
        [HDR]_SpecularCol ("高光色", color) = (1.0, 1.0, 1.0, 1.0)

        [Space(20)]
        [Header(Material)]
        _NormalInt ("法线强度", range(0, 10)) = 1.0
        _Rough ("粗糙度", range(0.001, 1)) = 0.5
        _FresnelPow ("菲涅尔次幂", range(1, 10)) = 5.0
        
        _planeWidth("planeWidth", Range(0.01,20)) = 20
        _TrailNormalScale("_TrailNormalScale", Range(0.01,1)) = 0.5
        _NormalBlend("_NormalBlend", Range(0.01,1)) = 0.5
        
        
        [Space(20)]
        [Header(Flash)]
        _FlashInt ("闪烁强度", float) = 10
        _FlashOffset ("闪烁偏移", float) = -0.1
        _FlashRange_Min ("闪烁最小衰减半径", float) = 5.0
        _FlashRange_Max ("闪烁最大衰减半径", float) = 10.0

    }
    SubShader
    {
        Tags
        {
            "RenderPipeline"="UniversalPipeline"
            "RenderType"="Opaque"
            "Queue"="Geometry+0"
        }

        Pass
        {
            Name "Pass"
            Tags
            {
                "LightMode"="UniversalForward"
            }

            HLSLPROGRAM
            #pragma require tessellation
            #pragma require geometry

            #pragma vertex BeforeTessVertProgram
            #pragma hull HullProgram
            #pragma domain DomainProgram
            #pragma fragment FragmentProgram

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma prefer_hlslcc gles
            #pragma exclude_renderers d3d11_9x
            #pragma target 4.6

            // Includes
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            
            CBUFFER_START(UnityPerMaterial)
                float _Tess;
                float _MaxTessDistance;
                float _MinTessDistance;

                //颜色
                float3 _BrightCol;
                float3 _DarkCol;
                float3 _SpecularCol;
                float3 _AmbCol;

                //质感
                float _NormalInt;
                float _Rough;
                float _FresnelPow;

                //闪烁
                float _FlashInt;
                float _FlashOffset;
                float _FlashRange_Min;
                float _FlashRange_Max;

                float _planeWidth;
                float _TrailNormalScale;
            float _NormalBlend;
            CBUFFER_END

            TEXTURE2D(_TopTex);
            SAMPLER(sampler_TopTex);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);
            TEXTURE2D(_RT_Trails);
            SAMPLER(sampler_RT_Trails);
            TEXTURE2D(_FlashTex);
            SAMPLER(sampler_FlashTex);

            float4 _TopTex_ST;
            float4 _RT_Trails_TexelSize;
            float _SnowThickness;
            float3 _snowCameraSet;
            float3 _PlayerPosWS;

            // 顶点着色器的输入
            struct Attributes
            {
                float4 vertex : POSITION;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            // 片段着色器的输入
            struct Varyings
            {
                float4 vertex : SV_POSITION;
                float4 color : COLOR;
                float2 uv : TEXCOORD0;
                float3 posWS : TEXCOORD1;
                float4 normalWS : TEXCOORD2;
                float4 tangentWS : TEXCOORD3;
                float4 bitangentWS : TEXCOORD4;
            };

            // 为了确定如何细分三角形，GPU使用了四个细分因子。三角形面片的每个边缘都有一个因数。
            // 三角形的内部也有一个因素。三个边缘向量必须作为具有SV_TessFactor语义的float数组传递。
            // 内部因素使用SV_InsideTessFactor语义
            struct TessellationFactors
            {
                float edge[3] : SV_TessFactor;
                float inside : SV_InsideTessFactor;
            };

            // 该结构的其余部分与Attributes相同，只是使用INTERNALTESSPOS代替POSITION语意，否则编译器会报位置语义的重用
            struct ControlPoint
            {
                float4 vertex : INTERNALTESSPOS;
                float3 normal : NORMAL;
                float4 tangent : TANGENT;
                float2 uv : TEXCOORD0;
                float4 color : COLOR;
            };

            // 顶点着色器，此时只是将Attributes里的数据递交给曲面细分阶段
            ControlPoint BeforeTessVertProgram(Attributes v)
            {
                ControlPoint p;

                p.vertex = v.vertex;
                p.uv = v.uv;
                p.normal = v.normal;
                p.tangent = v.tangent;
                p.color = v.color;

                return p;
            }

            // 随着距相机的距离减少细分数
            float CalcDistanceTessFactor(float4 vertex, float minDist, float maxDist, float tess)
            {
                float3 worldPosition = TransformObjectToWorld(vertex.xyz);
                float dist = distance(worldPosition, _PlayerPosWS);
                float f = clamp(1.0 - (dist - minDist) / (maxDist - minDist), 0.01, 1.0) * tess;
                return (f);
            }

            // Patch Constant Function决定Patch的属性是如何细分的。这意味着它每个Patch仅被调用一次，
            // 而不是每个控制点被调用一次。这就是为什么它被称为常量函数，在整个Patch中都是常量的原因。
            // 实际上，此功能是与HullProgram并行运行的子阶段。
            // 三角形面片的细分方式由其细分因子控制。我们在MyPatchConstantFunction中确定这些因素。
            // 当前，我们根据其距离相机的位置来设置细分因子
            TessellationFactors MyPatchConstantFunction(InputPatch<ControlPoint, 3> patch)
            {
                float minDist = _MinTessDistance;
                float maxDist = _MaxTessDistance;

                TessellationFactors f;

                float edge0 = CalcDistanceTessFactor(patch[0].vertex, minDist, maxDist, _Tess);
                float edge1 = CalcDistanceTessFactor(patch[1].vertex, minDist, maxDist, _Tess);
                float edge2 = CalcDistanceTessFactor(patch[2].vertex, minDist, maxDist, _Tess);

                // make sure there are no gaps between different tessellated distances, by averaging the edges out.
                f.edge[0] = (edge1 + edge2) / 2;
                f.edge[1] = (edge2 + edge0) / 2;
                f.edge[2] = (edge0 + edge1) / 2;
                f.inside = (edge0 + edge1 + edge2) / 3;
                return f;
            }

            //细分阶段非常灵活，可以处理三角形，四边形或等值线。我们必须告诉它必须使用什么表面并提供必要的数据。
            //这是 hull 程序的工作。Hull 程序在曲面patch上运行，该曲面patch作为参数传递给它。
            //我们必须添加一个InputPatch参数才能实现这一点。Patch是网格顶点的集合。必须指定顶点的数据格式。
            //现在，我们将使用ControlPoint结构。在处理三角形时，每个patch将包含三个顶点。此数量必须指定为InputPatch的第二个模板参数
            //Hull程序的工作是将所需的顶点数据传递到细分阶段。尽管向其提供了整个patch，
            //但该函数一次仅应输出一个顶点。patch中的每个顶点都会调用一次它，并带有一个附加参数，
            //该参数指定应该使用哪个控制点（顶点）。该参数是具有SV_OutputControlPointID语义的无符号整数。
            [domain("tri")] //明确地告诉编译器正在处理三角形，其他选项：
            [outputcontrolpoints(3)] //明确地告诉编译器每个patch输出三个控制点
            [outputtopology("triangle_cw")] //当GPU创建新三角形时，它需要知道我们是否要按顺时针或逆时针定义它们
            [partitioning("fractional_odd")] //告知GPU应该如何分割patch，现在，仅使用整数模式
            [patchconstantfunc("MyPatchConstantFunction")]
            //GPU还必须知道应将patch切成多少部分。这不是一个恒定值，每个patch可能有所不同。必须提供一个评估此值的函数，称为patch常数函数（Patch Constant Functions）
            ControlPoint HullProgram(InputPatch<ControlPoint, 3> patch, uint id : SV_OutputControlPointID)
            {
                return patch[id];
            }

            Varyings AfterTessVertProgram(Attributes v)
            {
                Varyings o;

                o.posWS = TransformObjectToWorld(v.vertex.xyz);
                o.posWS.y += _SnowThickness;


                float snowDTSize = _snowCameraSet.y * 2;
                float2 FootDepthUV = (o.posWS.xz - _snowCameraSet.xz) / snowDTSize + 0.5;
                float2 trailUV = FootDepthUV / 5 + 0.4;

                float4 traceTex = SAMPLE_TEXTURE2D_LOD(_RT_Trails, sampler_RT_Trails, trailUV, 0);

                o.posWS.y -= traceTex.r;

                o.vertex = TransformWorldToHClip(o.posWS.xyz);

                o.uv = TRANSFORM_TEX(v.uv, _TopTex);

                VertexNormalInputs normalInput = GetVertexNormalInputs(v.normal, v.tangent);
                half3 viewDirWS = GetWorldSpaceViewDir(o.posWS);
                o.normalWS = half4(normalInput.normalWS, viewDirWS.x);
                o.tangentWS = half4(normalInput.tangentWS, viewDirWS.y);
                o.bitangentWS = half4(normalInput.bitangentWS, viewDirWS.z);

                o.color = 0;

                return o;
            }

            //HUll着色器只是使曲面细分工作所需的一部分。一旦细分阶段确定了应如何细分patch，
            //则由Domain着色器来评估结果并生成最终三角形的顶点。
            //Domain程序将获得使用的细分因子以及原始patch的信息，原始patch在这种情况下为OutputPatch类型。
            //细分阶段确定patch的细分方式时，不会产生任何新的顶点。相反，它会为这些顶点提供重心坐标。
            //使用这些坐标来导出最终顶点取决于域着色器。为了使之成为可能，每个顶点都会调用一次域函数，并为其提供重心坐标。
            //它们具有SV_DomainLocation语义。
            //在Demain函数里面，我们必须生成最终的顶点数据。
            [domain("tri")] //Hull着色器和Domain着色器都作用于相同的域，即三角形。我们通过domain属性再次发出信号
            Varyings DomainProgram(TessellationFactors factors, OutputPatch<ControlPoint, 3> patch,
                       float3 barycentricCoordinates : SV_DomainLocation)
            {
                Attributes v;

                //为了找到该顶点的位置，我们必须使用重心坐标在原始三角形范围内进行插值。
                //X，Y和Z坐标确定第一，第二和第三控制点的权重。
                //以相同的方式插值所有顶点数据。让我们为此定义一个方便的宏，该宏可用于所有矢量大小。
                #define DomainInterpolate(fieldName) v.fieldName = \
                        patch[0].fieldName * barycentricCoordinates.x + \
                        patch[1].fieldName * barycentricCoordinates.y + \
                        patch[2].fieldName * barycentricCoordinates.z;

                //对位置、颜色、UV、法线等进行插值
                DomainInterpolate(vertex)
                DomainInterpolate(uv)
                DomainInterpolate(color)
                DomainInterpolate(normal)
                    DomainInterpolate(tangent)

                //现在，我们有了一个新的顶点，该顶点将在此阶段之后发送到几何程序或插值器。
                //但是这些程序需要Varyings数据，而不是Attributes。为了解决这个问题，
                //我们让域着色器接管了原始顶点程序的职责。
                //这是通过调用其中的AfterTessVertProgram（与其他任何函数一样）并返回其结果来完成的。
                return AfterTessVertProgram(v);
            }
            
            #define planeWidth 20
            float3 FindNormal(float2 uv)
            {
                
                float u = _RT_Trails_TexelSize.x * _planeWidth;

                float2 offsets[4];
                offsets[0] = uv + float2(u, 0);
                offsets[1] = uv + float2(-u, 0);
                offsets[2] = uv + float2(0, -u);
                offsets[3] = uv + float2(0, u);

                float hts[4];
                for (int j = 0; j < 4; j++)
                {
                    hts[j] = SAMPLE_TEXTURE2D(_RT_Trails, sampler_RT_Trails,
                        float2(offsets[j].x, offsets[j].y)).r;
                }
                
		        float2 _step = float2(1.0, 0.0);
		        float3 va = normalize(float3(_step.xy, hts[1] - hts[0]));
		        float3 vb = normalize(float3(_step.yx, -hts[3] + hts[2]));

		        return cross(va, vb).rbg; 
            }
            
            // 片段着色器
            half4 FragmentProgram(Varyings i) : SV_TARGET
            {
                half3 albedo = SAMPLE_TEXTURE2D(_TopTex, sampler_TopTex, i.posWS.xz/10).rgb;
                
                float4 normalTex = SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.posWS.xz/10);
                float3 normalTS = UnpackNormalScale(normalTex, _NormalInt);
                float3x3 tangentToWorld = float3x3(i.tangentWS.xyz, i.bitangentWS.xyz, i.normalWS.xyz);
                float3 localNormalWS = TransformTangentToWorld(normalTS, tangentToWorld);

                
                float2 FootDepthUV = (i.posWS.xz - _snowCameraSet.xz) / (_snowCameraSet.y * 2) + 0.5;
                float2 trailUV = FootDepthUV / 5 + 0.4;

                float3 traceNormalWS = FindNormal(trailUV);
                traceNormalWS = normalize(float3(traceNormalWS.r,traceNormalWS.g * _TrailNormalScale, traceNormalWS.b));
               // traceNormalWS =  mul(tangentToWorld, traceNormalWS);
               // return half4(traceNormalWS, 1.0);
                //return half4(traceNormalWS.r,0,traceNormalWS.b, 1.0);
                float4 traceTex = SAMPLE_TEXTURE2D(_RT_Trails, sampler_RT_Trails, trailUV);
                traceNormalWS = normalize(lerp(localNormalWS,traceNormalWS, _NormalBlend)) ;
                //return half4(traceTex.r,0,0, 1.0);
                float3 normalWS = traceTex.r == 0 ? localNormalWS : traceNormalWS;
               // normalWS = localNormalWS;
               // return half4(normalWS, 1.0);
                
                if (dot(i.normalWS.rgb, half3(0, 1, 0)) < 0.05)
                {
                    albedo = half3(0.3, 0.1, 0.5);
                    normalWS = i.normalWS.rgb;
                }
                
                Light light = GetMainLight(TransformWorldToShadowCoord(i.posWS));
                float3 nDirWS = normalWS;
                float3 lDirWS = light.direction;
                float3 vDirWS = normalize(_WorldSpaceCameraPos - i.posWS);
                float3 hDirWS = normalize(lDirWS + vDirWS);
                
                float lambert = 0.5 * dot(nDirWS, lDirWS) + 0.5;
                lambert = saturate(dot(nDirWS, lDirWS));
                float blinn = lambert * pow(saturate(dot(normalWS, hDirWS)), 1.0 / (_Rough * _Rough));
                float3 diffuseCol = lerp(albedo * 0.1, albedo, lambert);
                float3 specularCol = _SpecularCol * blinn;

                float nv = saturate(dot(nDirWS, vDirWS));
                float fresnel = pow(1.0 - nv, _FresnelPow);
                float3 _AmbCol = SampleSH(normalWS);
                float3 ambCol = fresnel * _AmbCol;

                float3 finalCol = (diffuseCol + specularCol) *
                    (light.color * light.shadowAttenuation*0.5+0.5)
                + ambCol * diffuseCol;
               // return half4(1,1,1,1)* light.shadowAttenuation;
                return half4(finalCol, 1.0);
            }
            ENDHLSL
        }
    }
}