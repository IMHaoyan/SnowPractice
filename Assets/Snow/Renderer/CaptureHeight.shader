Shader "Trace/CaptureHeight"
{
    Properties {}
    SubShader
    {
        Pass
        {

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct appdata_t
            {
                float4 vertex : POSITION;
                half2 texcoord : TEXCOORD0;
            };

            struct v2f
            {
                float4 vertex : SV_POSITION;
                float depth : TEXCOORD0;
            };

            v2f vert(appdata_t v)
            {
                v2f o;
                o.vertex = TransformObjectToHClip(v.vertex);
                o.depth = mul(unity_ObjectToWorld, v.vertex).y;
                return o;
            }

            float4 frag(v2f i) : SV_Target
            {
                //将255米的高度压缩到0-1写入r，每一米内的高度写入g，复原时r*255+g就是实际高度
                float4 heightValue = float4(floor(i.depth) / 255, frac(i.depth), 0, 1);
                return heightValue;
            }
            ENDHLSL
        }
    }
}