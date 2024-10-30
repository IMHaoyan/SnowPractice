Shader "Unlit/DrawTrack"
{
    Properties
    {

        [HideInInspector]_MainTex ("Texture", 2D) = "black" {}
        _Coordinate("Coordinate", vector) = (0,0,0,0)
        _Color("Color", Color) = (1,0,0,0)
        _DrawStength("Track Width", Range(10, 1000)) = 100
    }
    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
        }
        LOD 100

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _Color, _Coordinate;
                float _DrawStength;
            CBUFFER_END

            Texture2D _MainTex;
            float4 _MainTex_ST;

            #define smp SamplerState_Point_Repeat
            SAMPLER(smp);

            v2f vert(appdata v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.uv = TRANSFORM_TEX(v.uv, _MainTex);
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                float4 col = _MainTex.Sample(smp, i.uv);
                float draw = pow(saturate(1 - distance(i.uv, _Coordinate.xy)), _DrawStength);
                float4 drawCol = _Color * draw;
                return col + drawCol;
            }
            ENDHLSL
        }
    }
}