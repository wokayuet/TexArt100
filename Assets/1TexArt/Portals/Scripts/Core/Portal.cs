using System.Collections;
using System.Collections.Generic;
using UnityEngine;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class Portal : MonoBehaviour
{
    [Header("Main Settings")]
    public Portal linkedPortal;
    public MeshRenderer screen;

    // Private variables
    RenderTexture viewTexture;
    Camera portalCam;
    Camera playerCam;
    List<PortalTraveller> trackedTravellers;


    void OnEnable()
    {

    }
    void OnDisable()
    {
        if (viewTexture != null)
        {
            if (portalCam != null) portalCam.targetTexture = null;
            viewTexture.Release();
            DestroyImmediate(viewTexture);
            viewTexture = null;
        }
    }

    void Awake()
    {

        playerCam = Camera.main;

        portalCam = GetComponentInChildren<Camera>();
        portalCam.enabled = false; // 我们手动控制渲染

        trackedTravellers = new List<PortalTraveller>();
    }

    void LateUpdate()
    {
        HandleTravellers();
    }

    void HandleTravellers()
    {
        for (int i = 0; i < trackedTravellers.Count; i++)
        {
            PortalTraveller traveller = trackedTravellers[i];
            Transform travellerT = traveller.transform;
            var m = linkedPortal.transform.localToWorldMatrix * transform.worldToLocalMatrix * travellerT.localToWorldMatrix;

            Vector3 offsetFromPortal = travellerT.position - transform.position;
            int portalSide = System.Math.Sign(Vector3.Dot(offsetFromPortal, transform.forward));
            int portalSideOld = System.Math.Sign(Vector3.Dot(traveller.previousOffsetFromPortal, transform.forward));
            // Teleport the traveller if it has crossed from one side of the portal to the other
            if (portalSide != portalSideOld)
            {
                var positionOld = travellerT.position;
                var rotOld = travellerT.rotation;
                traveller.Teleport(transform, linkedPortal.transform, m.GetColumn(3), m.rotation);
                
                traveller.graphicsClone.transform.SetPositionAndRotation(positionOld, rotOld);
                
                // Can't rely on OnTriggerEnter/Exit to be called next frame since it depends on when FixedUpdate runs
                linkedPortal.OnTravellerEnterPortal(traveller);
                trackedTravellers.RemoveAt(i);
                i--;
            }
            else
            {
                traveller.graphicsClone.transform.SetPositionAndRotation(m.GetColumn(3), m.rotation);
                traveller.previousOffsetFromPortal = offsetFromPortal;
            }
        }
    }

    // —— URP：在管线开始渲染每个 Camera 时被调用 —— //


    // 在一次 beginCameraRendering 中，渲染“另一侧”的视图到 RT
    public void Render(ScriptableRenderContext context)
    {
        if (!CameraUtility.VisibleFromCamera(linkedPortal.screen, playerCam)) return;

        screen.enabled = false;

        CreateViewTextureURP();

        // 玩家相机在门B前面往里看
        // PortalCam 要在门A前面复制这种站位和方向
        // 这样 PortalCam 渲染的画面，就好像是从另一边的门看过来
        Matrix4x4 m =
            transform.localToWorldMatrix *                // 3 把“相对于门B的相机位置”复制到“相对于门A”的位置上
            linkedPortal.transform.worldToLocalMatrix *   // 2 把玩家相机的位置/旋转转到门B的参考系下
            playerCam.transform.localToWorldMatrix;       // 1 玩家相机在世界中的 TRS

        portalCam.transform.SetPositionAndRotation(m.GetColumn(3), m.rotation);

        // 用 URP 的单相机渲染接口渲染到 targetTexture
        UniversalRenderPipeline.RenderSingleCamera(context, portalCam);

        screen.enabled = true;

    }

    public void PostPortalRender()
    {
        if (playerCam != null)
            ProtectScreenFromClipping(playerCam.transform.position);
    }
    // 动态调整门厚度防止裁切
    float ProtectScreenFromClipping(Vector3 viewPoint)
    {
        float halfHeight = playerCam.nearClipPlane * Mathf.Tan(playerCam.fieldOfView * 0.5f * Mathf.Deg2Rad);
        float halfWidth = halfHeight * playerCam.aspect;
        float dstToNearClipPlaneCorner = new Vector3(halfWidth, halfHeight, playerCam.nearClipPlane).magnitude;
        float screenThickness = dstToNearClipPlaneCorner;

        Transform screenT = screen.transform;
        bool camFacingSameDirAsPortal = Vector3.Dot(transform.forward, transform.position - viewPoint) > 0;
        screenT.localScale = new Vector3(screenT.localScale.x, screenT.localScale.y, screenThickness);
        screenT.localPosition = Vector3.forward * screenThickness * ((camFacingSameDirAsPortal) ? 0.5f : -0.5f);
        return screenThickness;
    }

    #region 传送 & RT 创建（URP）
    // 仅替换 RT 的创建方式，其他逻辑不变
    void CreateViewTextureURP()
    {
        int w = Screen.width;
        int h = Screen.height;

        bool needRecreate = viewTexture == null || viewTexture.width != w || viewTexture.height != h;

        if (needRecreate)
        {
            if (viewTexture != null)
            {
                viewTexture.Release();
                DestroyImmediate(viewTexture);
            }

            // 用 URP 友好的描述符
            var desc = new RenderTextureDescriptor(w, h, RenderTextureFormat.ARGB32, 24);
            desc.msaaSamples = Mathf.Max(1, UniversalRenderPipeline.asset ? UniversalRenderPipeline.asset.msaaSampleCount : 1);
            desc.sRGB = (QualitySettings.activeColorSpace == ColorSpace.Linear);
            desc.useMipMap = false;
            desc.autoGenerateMips = false;

            viewTexture = new RenderTexture(desc);
            viewTexture.name = "[Portal_RT]";

            // 绑定到门相机 & 门屏幕材质
            portalCam.targetTexture = viewTexture;

            // Portal Shader 采样的是 _MainTex，这里保持一致
            linkedPortal.screen.material.SetTexture("_MainTex", viewTexture);

            // 基本相机能力：跟随项目设置
            portalCam.allowHDR = true;
#if UNITY_2021_2_OR_NEWER
            portalCam.allowMSAA = desc.msaaSamples > 1;
#endif
            // 关闭不必要的后期，避免重复开销
            var camData = portalCam.GetUniversalAdditionalCameraData();
            if (camData != null)
            {
                camData.renderPostProcessing = false;
                camData.antialiasing = AntialiasingMode.None; // 因为我们已经在 RT 上走 MSAA
            }
        }
    }

    void OnTravellerEnterPortal(PortalTraveller traveller)
    {
        if (!trackedTravellers.Contains(traveller))
        {
            traveller.EnterPortalThreshold();
            traveller.previousOffsetFromPortal = traveller.transform.position - transform.position;
            trackedTravellers.Add(traveller);
        }
    }

    void OnTriggerEnter(Collider other)
    {
        var traveller = other.GetComponent<PortalTraveller>();
        if (traveller)
        {
            OnTravellerEnterPortal(traveller);
        }
    }

    void OnTriggerExit(Collider other)
    {
        var traveller = other.GetComponent<PortalTraveller>();
        if (traveller && trackedTravellers.Contains(traveller))
        {
            traveller.ExitPortalThreshold();
            trackedTravellers.Remove(traveller);
        }
    }
    #endregion
}
