using UnityEngine;
using UnityEngine.Rendering;

using UnityEngine.Rendering.Universal;

public class MainCamera : MonoBehaviour
{

    Portal[] portals;
    Camera main;
    void OnEnable() => RenderPipelineManager.beginCameraRendering += OnBegin;
    void OnDisable() => RenderPipelineManager.beginCameraRendering -= OnBegin;
    void Awake()
    {
        portals = FindObjectsOfType<Portal>();
        main = Camera.main;
    }


    void OnBegin(ScriptableRenderContext ctx, Camera cam)
    {

        if (cam != main) return;
        //for (int i = 0; i < portals.Length; i++)
        //{
        //    portals[i].PrePortalRender();
        //}
        for (int i = 0; i < portals.Length; i++)
        {
            portals[i].Render(ctx);
        }

        for (int i = 0; i < portals.Length; i++)
        {
            portals[i].PostPortalRender();
        }

    }

}