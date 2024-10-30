using System.Collections;
using System.Collections.Generic;
using UnityEditor.TerrainTools;
using UnityEngine;
/// <summary>
/// 两张RenderTexture(m_rtDepth 1&2)都是物体的深度值
/// 交替传入cameraReceiveMat和snowRenderMat是为了保持深度图不刷新，并在cameraReceiveMat的shader中剔除了比雪面高的深度
/// </summary
public class ObjectDepthCam : MonoBehaviour
{
    public GameObject snowPlane;// 雪面plane主要
    public Material cameraReceiveMat;// 相机处理深度图shader
    public Material snowRenderMat;// 雪面渲染shader
    public Material snowEdgeDetectMat;// 第一层轮廓线检测
    public Material snowOutEdgeDetectMat;// 第二层轮廓线检测
    public Shader showDepthShader;// 替代物体shader 检测深度
    public Material Quad1;// 上面视频中左边的quad显示

    [Tooltip("动态生成的贴图大小")]
    public int renderTextureSize = 512;
    public float snowFarPlane = 10.0f;
    public float SnowMaxHeight = 0.3f;

    private RenderTexture m_rtDepth;
    private RenderTexture m_rtDepth2;

    private Camera cam;
    bool firstFrame = true;
    bool rtFlag = true;

    void Start()
    {
        TextureInitial();

        cam = GetComponent<Camera>();
        cam.depthTextureMode = DepthTextureMode.Depth;
        cam.farClipPlane = snowFarPlane;
        //scale ortho camera with snow plane assuming it's 1:1
        cam.orthographicSize *= snowPlane.transform.localScale.x;
        cam.nearClipPlane = 0.0f;
        cam.orthographic = true;
        cam.aspect = 1.0f;
        cam.clearFlags = CameraClearFlags.Color;
        cam.backgroundColor = Color.black;

        cameraReceiveMat.SetFloat("_SnowMaxHeight", SnowMaxHeight);
        snowRenderMat.SetFloat("_SnowMaxHeight", SnowMaxHeight);
    }

    /// <summary>
    /// 两张RenderTexture交替传送，保证物体的DepthTex能够不刷新
    /// </summary>
    void UpdateCamera()
    {
        // We apply the init height calculated in the Start() and pass the floor height to the receiveSnow shader
        if (!firstFrame)
        {
            cam.SetReplacementShader(showDepthShader, "TerrainEffect");
            if (rtFlag)
            {
                cameraReceiveMat.SetTexture("_MainTex", m_rtDepth);
                cameraReceiveMat.SetTexture("_DepthTex", m_rtDepth2);
                snowRenderMat.SetTexture("_ImprintTex", m_rtDepth2);
                Quad1.SetTexture("_MainTex", m_rtDepth2);
                cam.targetTexture = m_rtDepth2;
            }
            else
            {
                cameraReceiveMat.SetTexture("_MainTex", m_rtDepth2);
                cameraReceiveMat.SetTexture("_DepthTex", m_rtDepth);
                snowRenderMat.SetTexture("_ImprintTex", m_rtDepth);
                Quad1.SetTexture("_MainTex", m_rtDepth);
                cam.targetTexture = m_rtDepth;
            }
        }
    }

    void Update()
    {
        // Each frame we update the camera
        UpdateCamera();
    }

    /// <summary>
    /// 在android平台无法在OnPostRenderer里使用RenderTexture交换
    /// 只能在OnRenderImage中传到destination中
    /// </summary>
    /// <param name="source"></param>
    /// <param name="destination"></param>
    private void OnRenderImage(RenderTexture source, RenderTexture destination)
    {
        if (!firstFrame)
        {
            var temp = RenderTexture.GetTemporary(m_rtDepth.width, m_rtDepth.height, 0, m_rtDepth.format);
            var temp2 = RenderTexture.GetTemporary(m_rtDepth.width, m_rtDepth.height, 0, m_rtDepth.format);
            if (rtFlag)
            {
                Graphics.Blit(m_rtDepth, temp, cameraReceiveMat);
                Graphics.Blit(temp, temp2, snowOutEdgeDetectMat);
                Graphics.Blit(temp2, destination, snowEdgeDetectMat);
            }
            else
            {
                Graphics.Blit(m_rtDepth2, temp, cameraReceiveMat);
                Graphics.Blit(temp, temp2, snowOutEdgeDetectMat);
                Graphics.Blit(temp2, destination, snowEdgeDetectMat);
            }
            RenderTexture.ReleaseTemporary(temp);
            RenderTexture.ReleaseTemporary(temp2);
            rtFlag = !rtFlag;
        }
        firstFrame = false; // not the first frame anymore
    }

    void TextureInitial()
    {
        m_rtDepth = new RenderTexture(renderTextureSize, renderTextureSize, 0);
        m_rtDepth.antiAliasing = 2;
        m_rtDepth.format = RenderTextureFormat.ARGB64;
        m_rtDepth.useMipMap = false;

        m_rtDepth2 = new RenderTexture(renderTextureSize, renderTextureSize, 0);
        m_rtDepth2.antiAliasing = 2;
        m_rtDepth2.format = RenderTextureFormat.ARGB64;
        m_rtDepth2.useMipMap = false;
    }
}