Shader "URPCustom/BumpMap" {
    Properties {
        _TintColor ("TintColor", Color) = (1, 1, 1, 1)
        _MainTex ("BaseMap", 2D) = "white" { }
        _NormalMap ("NormalMap", 2D) = "bump" { }
        _NormalScale ("NormalScale", Range(-1, 1)) = 1.0
        _Gloss ("Gloss", Range(8, 32)) = 20
    }
    SubShader {
        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
        
        CBUFFER_START(UnityPerMaterial)
            half4 _TintColor;
            float4 _MainTex_ST;
            float _NormalScale;
            float _Gloss;
            float3 _snowCameraSet;
        CBUFFER_END
        
        TEXTURE2D(_MainTex);
        SAMPLER(sampler_MainTex);
        TEXTURE2D(_NormalMap);
        SAMPLER(sampler_NormalMap);
        
        TEXTURE2D(_RT_Trails); SAMPLER(sampler_RT_Trails);
            TEXTURE2D(_RT_Current);
            SAMPLER(sampler_RT_Current);
            TEXTURE2D(_HeightRT);
            SAMPLER(sampler_HeightRT);

        struct a2v {
            float3 positionOS : POSITION;
            float2 texcoord : TEXCOORD0;
            float3 normalOS : NORMAL;
            float4 tangentOS : TANGENT;
        };
        
        struct v2f {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD0;
            float4 tangentWS : TEXCOORD1;
            float4 bitangentWS : TEXCOORD2;
            float4 normalWS : TEXCOORD3;
        };

        ENDHLSL

        Pass {
            //ZWrite Off
            //Blend One One
            Tags
            {
                "LightMode" = "UniversalForward"
            }
            
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            
            v2f vert(a2v i) {
                v2f o;
                VertexPositionInputs positionInputs = GetVertexPositionInputs(i.positionOS.xyz);
                o.positionCS = positionInputs.positionCS;
                float3 positionWS = positionInputs.positionWS;

                o.uv = TRANSFORM_TEX(i.texcoord, _MainTex);

                VertexNormalInputs normalInputs = GetVertexNormalInputs(i.normalOS, i.tangentOS);
                o.tangentWS.xyz = normalInputs.tangentWS;// TransformObjectToWorldDir(i.tangentOS.xyz);
                o.normalWS.xyz = normalInputs.normalWS; // TransformObjectToWorldNormal(i.normalOS);
                o.bitangentWS.xyz = normalInputs.bitangentWS; //cross(o.normalWS.xyz, o.tangentWS.xyz) * i.tangentOS.w * unity_WorldTransformParams.w;
                
                o.tangentWS.w = positionWS.x;
                o.bitangentWS.w = positionWS.y;
                o.normalWS.w = positionWS.z;
                
                return o;
            }

            half4 frag(v2f i) : SV_Target {
                float3x3 TBN = {
                    i.tangentWS.xyz, i.bitangentWS.xyz, i.normalWS.xyz
                };
                float3 normalTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, i.uv), _NormalScale);
                normalTS.z = sqrt(1 - dot(normalTS.xy, normalTS.xy));//normalize after scaled by _NormalScale
                float3 normalWS = normalize(mul(normalTS, TBN));
                
                float3 positionWS = float3(i.tangentWS.w, i.bitangentWS.w, i.normalWS.w);
                
                half3 albedo = _TintColor * 0.25;
                Light mainLight = GetMainLight();
                half3 ambient = 0;
               // ambient +=SampleSH(normalWS) * albedo * 0.3;
                
                float diff = saturate(dot(normalWS, mainLight.direction));
                half3 diffuse = diff * albedo.rgb * mainLight.color;
                
                float3 viewDir = normalize(_WorldSpaceCameraPos - positionWS);
                float3 halfDir = normalize(mainLight.direction + viewDir);
                float spec = pow(saturate(dot(halfDir, normalWS)), _Gloss);
                half3 specular = spec * albedo.rgb  * mainLight.color;
                
                half3 col = ambient + diffuse + specular;

                
                 
                float snowDTSize = _snowCameraSet.y * 2;
                float2 FootDepthUV = (positionWS.xz- _snowCameraSet.xz) / snowDTSize + 0.5;
                float2 trailUV = FootDepthUV / 5 + 0.4;
                float4 footprint = SAMPLE_TEXTURE2D(_RT_Trails, sampler_RT_Trails, trailUV);
                
                FootDepthUV.y = 1 - FootDepthUV.y;
                footprint = SAMPLE_TEXTURE2D(_RT_Current, sampler_RT_Current, FootDepthUV);


               footprint = SAMPLE_TEXTURE2D_LOD(_HeightRT, sampler_HeightRT, FootDepthUV, 0);
               
                // !!!!unity貌似没有wrap模式为solid的，我们想要_RT_Trails的环绕模式为solid
                float width = 0.01;
                //FootDepthUV = trailUV;
                if(FootDepthUV.x < 0||FootDepthUV.y <0 ||FootDepthUV.x > 1||FootDepthUV.y > 1)
                   footprint = half4(1,1,0,1)*0;
                else if(FootDepthUV.x < width||FootDepthUV.y <width ||FootDepthUV.x > 1-width||FootDepthUV.y > 1-width)
                   footprint = half4(1,1,0,1);



                
                if(dot(normalWS, half3(0,1,0))<0.1)
                {
                    footprint = 0;
                }
                
                return half4(footprint.rgb, 1);
            }
            ENDHLSL
        }

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
        UsePass "Universal Render Pipeline/Lit/DepthNormals"
    }
}
