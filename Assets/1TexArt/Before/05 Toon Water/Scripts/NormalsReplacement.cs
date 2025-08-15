using UnityEngine;
[ExecuteInEditMode]// 使用RenderTexture/屏幕后处理效果都需要绑定在某个摄像机上，希望在编辑器状态下也可以执行脚本来查看效果
public class NormalsReplacement : MonoBehaviour
{
    private RenderTexture renderTexture;


    private void Start()
    {
        Camera camera = GetComponent<Camera>();

        // Create a render texture matching the main camera's current dimensions.
        renderTexture = new RenderTexture(camera.pixelWidth, camera.pixelHeight, 24);
        // Surface the render texture as a global variable, available to all shaders.
        Shader.SetGlobalTexture("_CameraNormalsTexture", renderTexture);
        // 渲染结果直接输出到之前创建的 "_CameraNormalsTexture"全局着色器纹理，而不是直接绘制到屏幕上。
        camera.targetTexture = renderTexture;
    }
        
}
