using System;
using Unity.Mathematics;
using UnityEngine;
using UnityEngine.Rendering;
[ExecuteAlways]
[DisallowMultipleComponent]
public class TrailsManager : MonoBehaviour
{
    public Camera HeightCamera;
    public Camera TraceCamera;
    public Transform characterTransform;
    
    public float TrailCameraSize = 5.0f;
    int RT_Resolution = 500;
    
    public float SnowThickness;
    [Range(0,15.0f)]
    public float snowRestoreSpeed = 0;
    
    private RenderTexture HeightRT;
    
    public static RenderTexture RT_Trails;
    public static RenderTexture RT_Current;
    private RenderTexture RT_History;
    private Vector4 LastSnowCameraSet;
    
    private void OnEnable()
    {
        TraceCamera.enabled = true;
        HeightCamera.enabled = true;

        TextureWrapMode twm = TextureWrapMode.Clamp; //没有border？，需要手动处理

        RT_Current = RenderTexture.GetTemporary(RT_Resolution, RT_Resolution, 0, RenderTextureFormat.R16);
        RT_Current.filterMode = FilterMode.Point;
        RT_Current.wrapMode = twm;
        RT_Current.name = "RT_Current";
        RT_Current.useMipMap = true;
        
        RT_History = RenderTexture.GetTemporary(RT_Resolution*5, RT_Resolution*5, 0, RenderTextureFormat.R16);
        RT_History.filterMode = FilterMode.Point;
        RT_History.wrapMode = twm;
        RT_History.name = "RT_History";
        RT_History.useMipMap = true;
        
        RT_Trails = RenderTexture.GetTemporary(RT_Resolution*5, RT_Resolution*5, 0, RenderTextureFormat.R16);
        RT_Trails.filterMode = FilterMode.Bilinear;
        RT_Trails.wrapMode = twm;
        RT_Trails.name = "RT_Trails";
        RT_Trails.useMipMap = true;
        
        HeightRT = RenderTexture.GetTemporary(RT_Resolution, RT_Resolution, 0, RenderTextureFormat.ARGB32);
        HeightRT.filterMode = FilterMode.Point;
        HeightRT.wrapMode = twm;
        HeightRT.name = "HeightRT";
        HeightRT.useMipMap = true;
        

        CommandBuffer cmd = CommandBufferPool.Get();
        
        cmd.SetRenderTarget(RT_Current);
        cmd.ClearRenderTarget(RTClearFlags.All, Color.black, 1, 0);
        cmd.SetRenderTarget(RT_History);
        cmd.ClearRenderTarget(RTClearFlags.All, Color.black, 1, 0);
        cmd.SetRenderTarget(RT_Trails);
        cmd.ClearRenderTarget(RTClearFlags.All, Color.black, 1, 0);
        cmd.SetRenderTarget(HeightRT);
        cmd.ClearRenderTarget(RTClearFlags.All, Color.black, 1, 0);
        
        Graphics.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
        
        TraceCamera.targetTexture = RT_Current;
        HeightCamera.targetTexture = HeightRT;
        Shader.SetGlobalTexture("_HeightRT", HeightRT);
        Shader.SetGlobalTexture("_RT_Current", RT_Current);
        Shader.SetGlobalTexture("_RT_History", RT_History);
        Shader.SetGlobalTexture("_RT_Trails", RT_Trails);
    }

    private void OnDisable()
    {
        if (TraceCamera)
        {
            TraceCamera.targetTexture = null;
            TraceCamera.enabled = false;
            HeightCamera.targetTexture = null;
            HeightCamera.enabled = false;
        }
        
        RenderTexture.ReleaseTemporary(HeightRT);
        RenderTexture.ReleaseTemporary(RT_Current);
        RenderTexture.ReleaseTemporary(RT_History);
        RenderTexture.ReleaseTemporary(RT_Trails);
    }

    private void Start()
    {
        LastSnowCameraSet = new Vector4(HeightCamera.transform.position.x,
            HeightCamera.orthographicSize, HeightCamera.transform.position.z);
    }

    private void Update()
    {
        Shader.SetGlobalFloat("_SnowThickness", SnowThickness);
        Shader.SetGlobalFloat("_snowRestoreSpeed", snowRestoreSpeed);
        TraceCamera.orthographicSize = TrailCameraSize;
        HeightCamera.orthographicSize = TrailCameraSize;
        
        if (!true)
        {
            float RtSize = 1.0f;
            TraceCamera.transform.position =
                new Vector3(
                    (characterTransform.position.x * RtSize)  / RtSize, 
                    TraceCamera.transform.position.y, 
                    (characterTransform.position.z * RtSize)  / RtSize
                );
            HeightCamera.transform.position =
                new Vector3(
                    (characterTransform.position.x * RtSize)  / RtSize,  
                    HeightCamera.transform.position.y, 
                    (characterTransform.position.z * RtSize)  / RtSize
                );
        }
        else
        {
            float RtSize = RT_Resolution / (2 * TrailCameraSize); //1m to ? pixels
            TraceCamera.transform.position =
                new Vector3(
                    Mathf.Floor(characterTransform.position.x * RtSize)  / RtSize, 
                    TraceCamera.transform.position.y, 
                    Mathf.Floor(characterTransform.position.z * RtSize)  / RtSize
                );
            HeightCamera.transform.position =
                new Vector3(
                    Mathf.Floor(characterTransform.position.x * RtSize)  / RtSize,  
                    HeightCamera.transform.position.y, 
                    Mathf.Floor(characterTransform.position.z * RtSize)  / RtSize
                );
        }
        
        
        Vector4 SnowCameraSet = new Vector4(TraceCamera.transform.position.x,
            TraceCamera.orthographicSize, TraceCamera.transform.position.z);
        Shader.SetGlobalVector("_snowCameraSet", SnowCameraSet);
        Shader.SetGlobalVector("_LastSnowCameraSet", LastSnowCameraSet);
        
        LastSnowCameraSet = SnowCameraSet;
        
        //HistoryCopy
        //Graphics.Blit(RT_Trails, RT_History);
        CommandBuffer cmd = CommandBufferPool.Get("Update RT_History");
        cmd.Blit(RT_Trails, RT_History);
        //cmd.CopyTexture(RT_Trails, RT_History);//格式不一样不能使用
        Graphics.ExecuteCommandBuffer(cmd);
        CommandBufferPool.Release(cmd);
        
    }
}