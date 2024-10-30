Shader "Trail/TrailDrawer"
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

            struct Attributes
            {
                float4 positionOS : POSITION;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
            };

            
            TEXTURE2D(_RT_History);
            SAMPLER(sampler_RT_History);
            TEXTURE2D(_HeightRT);
            SAMPLER(sampler_HeightRT);

            Varyings vert(Attributes input)
            {
                Varyings output;
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                return output;
            }

            float _SnowThickness;
            float3 _snowCameraSet;

            float4 frag(Varyings input) : SV_Target
            {
                // 读取深度
                float snowDTSize = _snowCameraSet.y * 2;
                float2 HeightCamUV = (input.positionWS.xz- _snowCameraSet.xz) / snowDTSize + 0.5;
                float4 Height = SAMPLE_TEXTURE2D_LOD(_HeightRT, sampler_HeightRT, HeightCamUV, 0);
                float TerrainHeight = Height.r * 255.0 + Height.g;

                // 计算 RT_Current 数据
                float depth_RT_Current = TerrainHeight + _SnowThickness - input.positionWS.y;
                //防止因为上层建筑遮挡住了导致仍然认为上层建筑被凹陷，暂时加个0.1的offset防止因为碰撞陷入穿插造成没有凹陷
                depth_RT_Current = depth_RT_Current > _SnowThickness + 0.1 ? 0 : depth_RT_Current;
                return float4(depth_RT_Current, 0, 0, 1);
            }
            ENDHLSL
        }
    }
}