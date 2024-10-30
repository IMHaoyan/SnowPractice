using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;

public class CaptureHeightRF : ScriptableRendererFeature
{
    public class CaptureHeightPass : ScriptableRenderPass
    {
        private Material overrideMat;
        private FilteringSettings filtering;
        List<ShaderTagId> m_ShaderTagIdList = new List<ShaderTagId>();

        public CaptureHeightPass(LayerMask layerMask, Material mat)
        {
            overrideMat = mat;
            filtering = new FilteringSettings(RenderQueueRange.opaque, layerMask);

            m_ShaderTagIdList.Add(new ShaderTagId("UniversalForward"));
            m_ShaderTagIdList.Add(new ShaderTagId("SRPDefaultUnlit"));
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            DrawingSettings draw =
                CreateDrawingSettings(m_ShaderTagIdList, ref renderingData, SortingCriteria.CommonOpaque);
            draw.overrideMaterial = overrideMat;
            draw.overrideMaterialPassIndex = 0;
            context.DrawRenderers(renderingData.cullResults, ref draw, ref filtering);
        }
    }

    public LayerMask layerMask;
    CaptureHeightPass m_CaptureHeightPass;
    Material m_CaptureHeightMat;
    private static readonly string CaptureHeightShaderName = "Trace/CaptureHeight";

    public override void Create()
    {
        var CaptureHeightShader = Shader.Find(CaptureHeightShaderName);
        if (CaptureHeightShader == null)
        {
            Debug.LogWarning($"dont find shader: {CaptureHeightShaderName}");
            return;
        }

        m_CaptureHeightMat = new Material(CaptureHeightShader);
        m_CaptureHeightPass = new CaptureHeightPass(layerMask, m_CaptureHeightMat);

        // Configures where the render pass should be injected.
        //m_CaptureHeightPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(m_CaptureHeightPass);
    }
}