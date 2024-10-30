Shader "Trail/HistoryMerge"
{
    Properties
    {
        _MainTex ("Texture", 2D) = "white" {}
    }
    SubShader
    {
        Pass // pass 0
        {
            Name "BlurDepth"

            CGPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            struct a2v
            {
                float4 vertex : POSITION;
                float2 uv : TEXCOORD0;
            };

            struct v2f
            {
                float2 uv : TEXCOORD0;
                float4 vertex : SV_POSITION;
            };

            v2f vert(a2v v)
            {
                v2f o;
                o.vertex = UnityObjectToClipPos(v.vertex);
                o.uv = v.uv;
                return o;
            }

            sampler2D _MainTex;
            float4 _MainTex_TexelSize;

            float4 frag(v2f input) : SV_Target
            {
                //反转y轴：因为相机是从下向上拍的，所以要翻转成从上向下
                input.uv.y = 1 - input.uv.y;
                
                float4 depth = tex2D(_MainTex, input.uv);
                float offset = _MainTex_TexelSize.x;
                float4 d = depth;
                d += tex2D(_MainTex, input.uv + float2(0, offset));
                d += tex2D(_MainTex, input.uv + float2(offset, offset));
                d += tex2D(_MainTex, input.uv + float2(offset, 0));
                d += tex2D(_MainTex, input.uv + float2(offset, -offset));
                d += tex2D(_MainTex, input.uv + float2(0, -offset));
                d += tex2D(_MainTex, input.uv + float2(-offset, -offset));
                d += tex2D(_MainTex, input.uv + float2(-offset, 0));
                d += tex2D(_MainTex, input.uv + float2(-offset, offset));

                return d / 9;
            }
            ENDCG
        }

        Pass // pass 1
        {
            Name "CombineNoise"

            HLSLPROGRAM
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_MainTex);
            SAMPLER(sampler_MainTex);
            TEXTURE2D(_RT_History);
            SAMPLER(sampler_RT_History);
            float4 _LastSnowCameraSet;
            float4 _snowCameraSet;
            float _snowRestoreSpeed;

            #pragma vertex vert
            #pragma fragment frag

            struct a2v
            {
                float3 positionOS : POSITION;
                float2 texcoord : TEXCOORD0;
            };

            struct v2f
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
            };


            v2f vert(a2v i)
            {
                v2f o;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(i.positionOS.xyz);
                o.positionCS = positionInputs.positionCS;
                o.uv = i.texcoord;
                return o;
            }


            float4 frag(v2f i) : SV_Target
            {
                float2 currCamUV = i.uv;//(i.uv - 0.4) * 5;
                currCamUV = (i.uv - 0.4) * 5;
                float depth_RT_Current = SAMPLE_TEXTURE2D_LOD(_MainTex, sampler_MainTex, currCamUV, 0).r;
                if((currCamUV).x < 0||(currCamUV).y <0 ||(currCamUV).x > 1||(currCamUV).y > 1)
                   depth_RT_Current = 0;
                
                float snowDTSize = _snowCameraSet.y * 2;
                //  float2 currCamUV = (positionWS.xz - _snowCameraSet.xz) / snowDTSize + 0.5;
                float2 positionWSxz = (currCamUV - 0.5) * snowDTSize + _snowCameraSet.xz;
                float2 lastCamUV = (positionWSxz - _LastSnowCameraSet.xz) / snowDTSize + 0.5;
                float2 last_uv = lastCamUV;//*5 + 0.4;
                last_uv = lastCamUV / 5 + 0.4;
                float depth_RT_History = SAMPLE_TEXTURE2D_LOD(_RT_History, sampler_RT_History, last_uv, 0).r;
                
                float fadeSpeed = 0.0001*_snowRestoreSpeed;   //雪凹陷恢复速度(R16最小单位 0.0000153)
                depth_RT_History -= fadeSpeed;
                
                float depth = max(max(depth_RT_Current, depth_RT_History), 0);
                depth *= smoothstep(0.5, 0.4, length(i.uv - 0.5));
                return depth ;
            }
            ENDHLSL
        }
    }
}