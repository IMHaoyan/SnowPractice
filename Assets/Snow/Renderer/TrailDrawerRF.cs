using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;
using System.Collections.Generic;

public class TrailDrawerRF : ScriptableRendererFeature
{
    public class TraceDepthPass1 : ScriptableRenderPass
    {
        private Material overrideMat;
        private FilteringSettings filtering;

        List<ShaderTagId> ShaderTagIdList = new List<ShaderTagId>();
        
      
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            ConfigureTarget(TrailsManager.RT_Current);
            ConfigureClear(ClearFlag.All, Color.black); //初始化渲染目标的状态
        }
        
        public TraceDepthPass1(LayerMask layerMask, Material mat)
        {
            overrideMat = mat;
            filtering = new FilteringSettings(RenderQueueRange.opaque, layerMask);

            ShaderTagIdList.Add(new ShaderTagId("UniversalForward"));
            ShaderTagIdList.Add(new ShaderTagId("SRPDefaultUnlit"));
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            DrawingSettings draw =
                CreateDrawingSettings(ShaderTagIdList, ref renderingData, SortingCriteria.CommonOpaque);
            draw.overrideMaterial = overrideMat;
            draw.overrideMaterialPassIndex = 0;
            context.DrawRenderers(renderingData.cullResults, ref draw, ref filtering);
        }
    }

    public class CombinePass1 : ScriptableRenderPass
    {
        private Material CombineMat;
        private static int TempTextureId = Shader.PropertyToID("_SnowTempTexture");

        public CombinePass1(Material mat)
        {
            CombineMat = mat;
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            var des = renderingData.cameraData.cameraTargetDescriptor;
            cmd.GetTemporaryRT(TempTextureId, des.width, des.height, 0, FilterMode.Bilinear,
                RenderTextureFormat.ARGBFloat);
        }

        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            var target = renderingData.cameraData.targetTexture;

            var cmd = CommandBufferPool.Get("Combine shader");
            cmd.Blit(target, TempTextureId, CombineMat, 0);
            cmd.Blit(TempTextureId, TrailsManager.RT_Trails, CombineMat, 1);

            context.ExecuteCommandBuffer(cmd);
            CommandBufferPool.Release(cmd);
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            cmd.ReleaseTemporaryRT(TempTextureId);
        }
    }

/*   
    public class TracePass : ScriptableRenderPass
    {
        private Material overrideMat;
        private FilteringSettings filtering;
        List<ShaderTagId> m_ShaderTagIdList = new List<ShaderTagId>();

        public TracePass(LayerMask layerMask, Material mat)
        {
            overrideMat = mat;
            filtering = new FilteringSettings(RenderQueueRange.opaque, layerMask);

            m_ShaderTagIdList.Add(new ShaderTagId("UniversalForward"));
            m_ShaderTagIdList.Add(new ShaderTagId("SRPDefaultUnlit"));
        }

        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            ConfigureClear(ClearFlag.All, Color.black); //初始化渲染目标的状态
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
*/
    private TraceDepthPass1 TraceDepthPass;
    private CombinePass1 CombinePass;
    private Material DepthMaterial;
    private Material CombineMaterial;
    public LayerMask layerMask;

    private static readonly string traceShaderName = "Trail/TrailDrawer";
    private static readonly string normalShaderName = "Trail/HistoryMerge";


    public override void Create()
    {
        
        var traceShader = Shader.Find(traceShaderName);
        if (traceShader == null)
        {
            Debug.LogWarning($"dont find shader: {traceShaderName}");
            return;
        }

        var normalShader = Shader.Find(normalShaderName);
        if (normalShader == null)
        {
            Debug.LogWarning($"dont find shader: {normalShaderName}");
            return;
        }
        
        DepthMaterial = new Material(traceShader);
        TraceDepthPass = new TraceDepthPass1(layerMask, DepthMaterial);
        CombineMaterial = new Material(normalShader);
        CombinePass = new CombinePass1(CombineMaterial);

        // Configures where the render pass should be injected.
        //TraceDepthPass.renderPassEvent = RenderPassEvent.AfterRenderingOpaques;
        //CombinePass.renderPassEvent= RenderPassEvent.AfterRenderingOpaques;
    }

    // Here you can inject one or multiple render passes in the renderer.
    // This method is called when setting up the renderer once per-camera.
    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        renderer.EnqueuePass(TraceDepthPass);
        renderer.EnqueuePass(CombinePass);
    }
    
    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(DepthMaterial);
        CoreUtils.Destroy(CombineMaterial);
    }
}