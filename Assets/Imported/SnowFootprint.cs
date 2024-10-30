using System.Collections;
using System.Collections.Generic;
using UnityEditor.TerrainTools;
using UnityEngine;
public class SnowFootprint : MonoBehaviour
{
    private RenderTexture s_SplatMap;
    private Vector3 m_LastPos;
    public Material m_DrawMaterial;
    
    void Awake()
    {
        if (s_SplatMap == null)
        {
            s_SplatMap = new RenderTexture(1024, 1024, 0, RenderTextureFormat.Default);
        }

        m_LastPos = transform.position;

    }

    // Update is called once per frame
    void Update()
    {
        if (Vector3.Distance(m_LastPos, transform.position) > 0.01f)
        {
            m_LastPos = transform.position;

            if (Physics.Raycast(transform.position, Vector3.down, out RaycastHit m_Hit, 2, ~(1 << LayerMask.NameToLayer("Character"))))
            {
               // Debug.Log(m_Hit.textureCoord.x + "," + m_Hit.textureCoord.y);
                m_DrawMaterial.SetVector("_Coordinate", new Vector4(m_Hit.textureCoord.x, m_Hit.textureCoord.y, 0, 0));
                RenderTexture tmp = RenderTexture.GetTemporary(s_SplatMap.width, s_SplatMap.height, 0, RenderTextureFormat.Default);
                Graphics.Blit(s_SplatMap, tmp);
                Graphics.Blit(tmp, s_SplatMap, m_DrawMaterial);
                RenderTexture.ReleaseTemporary(tmp);
            }
        }
    }
}
