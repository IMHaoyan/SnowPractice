Shader "Scene/FlashGround"
{
    Properties
    {
        [Header(Texture)]
        _MainTex ("主贴图", 2D) = "gray" {}
        [NoScaleOffset]_NormalMap ("法线图", 2D) = "bump" {}
        _FlashTex ("闪烁遮罩", 2D) = "black" {}

        [Space(20)]
        [Header(Color)]
        [HDR]_BrightCol ("亮部色", color) = (1.0, 1.0, 1.0, 1.0)
        _DarkCol ("暗部色", color) = (0.1, 0.1, 0.1, 1.0)
        [HDR]_SpecularCol ("高光色", color) = (1.0, 1.0, 1.0, 1.0)
        _AmbCol ("环境色", color) = (1.0, 1.0, 1.0, 1.0)

        [Space(20)]
        [Header(Material)]
        _NormalInt ("法线强度", range(0, 10)) = 1.0
        _Rough ("粗糙度", range(0.001, 1)) = 0.5
        _FresnelPow ("菲涅尔次幂", range(1, 10)) = 5.0

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
            "RenderPipeline" = "UniversalPipeline"
            "RenderType" = "Opaque"
            "Queue" = "Geometry"
        }

        Pass
        {
            Cull back
            ZWrite on

            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			CBUFFER_START(UnityPerMaterial)
                //贴图
                sampler2D _MainTex; float4 _MainTex_ST;
                sampler2D _NormalMap;
                sampler2D _FlashTex; float4 _FlashTex_ST;

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
            CBUFFER_END

            //重映射01
            float Remap(float min, float max, float input)
            {
                float k = 1.0 / (max - min);
                float b = -min * k;
                return saturate(k * input + b);
            }

            //计算任意平面交点
            float3 GetPosAnyPlaneCrossDir(float3 posPlane, float3 posRay, float3 nDirPlane, float3 nDirRay)
            {
                float3 deltaPos = posPlane - posRay;
                float temp = dot(nDirPlane, deltaPos) / dot(nDirPlane, nDirRay);
                return temp * nDirRay + posRay;
            }

            struct a2v
            {
                float4 posOS	: POSITION;
                float3 nDirOS : NORMAL;
                float4 tDirOS : TANGENT;
                float2 uv0  : TEXCOORD0;
            };
            struct v2f
            {
                float4 posCS	       : SV_POSITION;
                float3 posWS            : TEXCOORD6;
                float3 nDirWS       : TEXCOORD0;
                float3 tDirWS       : TEXCOORD1;
                float3 bDirWS       : TEXCOORD2;
                float3 vDirWS       : TEXCOORD3;
                float2 uv_Main     : TEXCOORD4;
                float4 uv_Flash    : TEXCOORD5;
                // float4 uv_Screen    : TEXCOORD7;
            };
            v2f vert(a2v i)
            {
                v2f o;

                //坐标
                o.posWS = TransformObjectToWorld(i.posOS.xyz);
                o.posCS = TransformWorldToHClip(o.posWS);

                //向量
                o.nDirWS = TransformObjectToWorldNormal(i.nDirOS);
                o.tDirWS = TransformObjectToWorldDir(i.tDirOS.xyz);
                o.bDirWS = cross(o.nDirWS, o.tDirWS) * i.tDirOS.w;
                o.vDirWS = GetCameraPositionWS() - o.posWS;

                //UV
                o.uv_Main = TRANSFORM_TEX(i.uv0, _MainTex);
                o.uv_Flash.xy = TRANSFORM_TEX(i.uv0, _FlashTex);
                // o.uv_Screen = ComputeScreenPos(o.posCS);

                //闪烁内层UV偏移
                float3x3 TBN = float3x3(normalize(o.tDirWS), normalize(o.bDirWS), normalize(o.nDirWS));
                float3 vDirTS = TransformWorldToTangent(o.vDirWS, TBN);
                // vDirTS = TransformWorldToTangent(UNITY_MATRIX_V[2].xyz, TBN);//统一采用相机朝向
                o.uv_Flash.zw = GetPosAnyPlaneCrossDir(float3(0, 0, _FlashOffset), float3(o.uv_Flash.xy, 0), float3(0,0,1), vDirTS).xy;

                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                //法线转换
                float3 nDirTS = UnpackNormal(tex2D(_NormalMap, i.uv_Main));
                nDirTS.xy *= _NormalInt;
                float3x3 TBN = float3x3(normalize(i.tDirWS), normalize(i.bDirWS), normalize(i.nDirWS));

                //向量
                Light light = GetMainLight(TransformWorldToShadowCoord(i.posWS));
                float3 nDirWS = normalize(mul(nDirTS, TBN));
                float3 lDirWS = light.direction;
                float3 vDirWS = normalize(i.vDirWS);
                float3 hDirWS = normalize(lDirWS + vDirWS);

                //光照
                float lambert = saturate(dot(nDirWS, lDirWS));
                float blinn = lambert * pow(saturate(dot(nDirWS, hDirWS)), 1.0 / (_Rough*_Rough));
                float3 baseCol = tex2D(_MainTex, i.uv_Main).rgb;
                float3 diffuseCol = baseCol * lerp(_DarkCol, _BrightCol, lambert);
                float3 specularCol = _SpecularCol * blinn;

                //环境光
                float nv = saturate(dot(nDirWS, vDirWS));
                float fresnel = pow(1.0 - nv, _FresnelPow);
                float3 ambCol = fresnel * _AmbCol;

                //闪烁
                float flashMask = Remap(_FlashRange_Max, _FlashRange_Min, length(i.vDirWS));
                float mask0 = tex2D(_FlashTex, i.uv_Flash.xy).r;
                float mask1 = tex2D(_FlashTex, i.uv_Flash.zw).r;
                // mask1 = tex2D(_FlashTex, _FlashTex_ST.zw * i.uv_Screen.xy / i.uv_Screen.w).r;//屏幕坐标
                float flashCol = _FlashInt * flashMask * mask0 * mask1;

                //混合
                float3 finalCol = (diffuseCol + specularCol + flashCol) * light.shadowAttenuation + ambCol * diffuseCol;
                return float4(finalCol, 1.0);
            }
            ENDHLSL
        }
    }
}