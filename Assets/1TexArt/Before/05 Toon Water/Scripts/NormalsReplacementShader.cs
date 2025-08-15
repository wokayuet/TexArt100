using UnityEngine;

public class NormalsReplacementShader : MonoBehaviour
{
    [SerializeField]
    Shader normalsShader;

    private RenderTexture renderTexture;
    private new Camera camera;

    private void Start()
    {
        Camera thisCamera = GetComponent<Camera>();

        // Create a render texture matching the main camera's current dimensions.
        renderTexture = new RenderTexture(thisCamera.pixelWidth, thisCamera.pixelHeight, 24);
        // Surface the render texture as a global variable, available to all shaders.
        Shader.SetGlobalTexture("_CameraNormalsTexture", renderTexture);

        // Setup a copy of the camera to render the scene using the normals shader.
        GameObject copy = new GameObject("Normals camera");
        camera = copy.AddComponent<Camera>();
        camera.CopyFrom(thisCamera);
        camera.transform.SetParent(transform);
        // 渲染结果直接输出到之前创建的 RenderTexture，而不是直接绘制到屏幕上。
        camera.targetTexture = renderTexture;
        camera.SetReplacementShader(normalsShader, "UniversalForward");
        // 确保法线摄像机在主摄像机之前渲染。这样，法线纹理在主摄像机渲染时已准备好。
        camera.depth = thisCamera.depth - 1;
    }
}
