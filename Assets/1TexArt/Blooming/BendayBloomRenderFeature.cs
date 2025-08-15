using UnityEngine;
using UnityEngine.Experimental.Rendering;
using UnityEngine.Rendering;
using UnityEngine.Rendering.Universal;

public class BendayBloomRenderFeature : ScriptableRendererFeature
{
    [SerializeField]private Shader m_bloomShader;
    [SerializeField] private Shader m_compositeShader;

    private Material m_bloomMaterial;
    private Material m_compositeMaterial;

    class BendayBloomRenderPass : ScriptableRenderPass
    {

        private readonly Material m_bloom;
        private readonly Material m_composite;

        RenderTextureDescriptor m_Descriptor;
        RTHandle m_cameraColorTarget;
        RTHandle m_cameraDepthTarget;


        RTHandle[] m_BloomMipDown;
        RTHandle[] m_BloomMipUp;

        const int k_MaxPyramidSize = 16;
        private static int[] _BloomMipUp;
        private static int[] _BloomMipDown;
        private GraphicsFormat hdrFormat;

        BenDayBloomEffectComponent m_BloomEffect;


        // 构造函数
        public BendayBloomRenderPass(Material bloomMaterial, Material compositeMaterial)
        {
            m_bloom = bloomMaterial;
            m_composite = compositeMaterial;

            // 告诉 URP 需要哪些缓冲
            // 放在 构造函数 或 OnCameraSetup() 里都可以，但构造函数里写可以确保在整个生命周期都声明依赖。
            ConfigureInput(ScriptableRenderPassInput.Depth);
            ConfigureInput(ScriptableRenderPassInput.Color);

            
            /*这部分来自package中的PostProcessPass的bloom部分*/
            // Bloom pyramid shader ids - can't use a simple stackalloc in the bloom function as we
            // unfortunately need to allocate strings
            _BloomMipUp = new int[k_MaxPyramidSize];
            _BloomMipDown = new int[k_MaxPyramidSize];
            m_BloomMipUp = new RTHandle[k_MaxPyramidSize];
            m_BloomMipDown = new RTHandle[k_MaxPyramidSize];

            for (int i = 0; i < k_MaxPyramidSize; i++)
            {
                _BloomMipUp[i] = Shader.PropertyToID("_BloomMipUp" + i);
                _BloomMipDown[i] = Shader.PropertyToID("_BloomMipDown" + i);
                // Get name, will get Allocated with descriptor later
                m_BloomMipUp[i] = RTHandles.Alloc(_BloomMipUp[i], name: "_BloomMipUp" + i);
                m_BloomMipDown[i] = RTHandles.Alloc(_BloomMipDown[i], name: "_BloomMipDown" + i);
            }
            // Texture format pre-lookup
            const FormatUsage usage = FormatUsage.Linear | FormatUsage.Render;

            if (SystemInfo.IsFormatSupported(GraphicsFormat.B10G11R11_UFloatPack32, usage)) // HDR fallback
            {
                hdrFormat = GraphicsFormat.B10G11R11_UFloatPack32;
            }
            else
            {
                hdrFormat = QualitySettings.activeColorSpace == ColorSpace.Linear
                    ? GraphicsFormat.R8G8B8A8_SRGB
                    : GraphicsFormat.R8G8B8A8_UNorm;
            }

        }
        public override void OnCameraSetup(CommandBuffer cmd, ref RenderingData renderingData)
        {
            m_Descriptor = renderingData.cameraData.cameraTargetDescriptor;
            // 获取相机的颜色、深度目标句柄（RTHandle）
            m_cameraColorTarget = renderingData.cameraData.renderer.cameraColorTargetHandle;
            m_cameraDepthTarget = renderingData.cameraData.renderer.cameraDepthTargetHandle;
            // 绑定渲染目标
            ConfigureTarget(m_cameraColorTarget, m_cameraDepthTarget);

        }


        public override void Execute(ScriptableRenderContext context, ref RenderingData renderingData)
        {
            // 获取GlobalVolume中的 BenDayBloomEffectComponent
            if (m_bloom == null || m_composite == null) return;
            if (renderingData.cameraData.cameraType == CameraType.Game)
            {
                VolumeStack stack = VolumeManager.instance.stack;
                m_BloomEffect = stack.GetComponent<BenDayBloomEffectComponent>();

                CommandBuffer cmd = CommandBufferPool.Get("BendayBloomRenderPass");

                using(new ProfilingScope(cmd, new ProfilingSampler("Benday Bloom Effect")))
                {
                    // 改造一下 urp 后处理bloom 
                    // 在这个方法设置了
                    // m_composite 的材质：cmd.SetGlobalTexture("_Bloom_Texture", m_BloomMipUp[0]);
                    // m_composite 的强度：cmd.SetGlobalFloat("_Bloom_Intensity", m_BloomEffect.intensity.value);
                    m_composite.SetTexture("_SourceTex", m_cameraColorTarget);
                    SetupBloom(cmd, m_cameraColorTarget);

                    // 设置bloom合成shader
                    m_composite.SetFloat("_Cutoff",m_BloomEffect.dotsCutoff.value);
                    m_composite.SetFloat("_Density",m_BloomEffect.dotsDensity.value);   
                    m_composite.SetVector("_Direction",m_BloomEffect.scrollDirection.value);

                    // blit 拷贝纹理并通过合成材质处理

                    Blitter.BlitCameraTexture(cmd, m_cameraColorTarget, m_cameraColorTarget, m_composite, 0);

                }

                context.ExecuteCommandBuffer(cmd);
                CommandBufferPool.Release(cmd);
            }
        }

        public override void OnCameraCleanup(CommandBuffer cmd)
        {
            
        }

        #region HelpMethod
        private void SetupBloom(CommandBuffer cmd, RTHandle source)
        {
            // Start at half-res
            int downres = 1;
            int tw = m_Descriptor.width >> downres;
            int th = m_Descriptor.height >> downres;

            // 迭代数Determine the iteration count
            int maxSize = Mathf.Max(tw, th);
            int iterations = Mathf.FloorToInt(Mathf.Log(maxSize, 2f) - 1);
            int mipCount = Mathf.Clamp(iterations, 1, m_BloomEffect.maxIterations.value);

            // 预滤参数 Pre-filtering parameters
            float clamp = m_BloomEffect.clamp.value;
            float threshold = Mathf.GammaToLinearSpace(m_BloomEffect.threshold.value);
            float thresholdKnee = threshold * 0.5f; // Hardcoded soft knee

            // 材质常量 Material setup
            float scatter = Mathf.Lerp(0.05f, 0.95f, m_BloomEffect.scatter.value);
            var bloomMaterial = m_bloom;
            bloomMaterial.SetVector("_Params", new Vector4(scatter, clamp, threshold, thresholdKnee));

            // 分配金字塔 Prefilter
            var desc = GetCompatibleDescriptor(tw, th, hdrFormat);
            for (int i = 0; i < mipCount; i++)
            {
                RenderingUtils.ReAllocateIfNeeded(ref m_BloomMipUp[i], desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: m_BloomMipUp[i].name);
                RenderingUtils.ReAllocateIfNeeded(ref m_BloomMipDown[i], desc, FilterMode.Bilinear, TextureWrapMode.Clamp, name: m_BloomMipDown[i].name);
                desc.width = Mathf.Max(1, desc.width >> 1);
                desc.height = Mathf.Max(1, desc.height >> 1);
            }

            Blitter.BlitCameraTexture(cmd, source, m_BloomMipDown[0], RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store, bloomMaterial, 0);

            // Downsample - gaussian pyramid
            var lastDown = m_BloomMipDown[0];
            for (int i = 1; i < mipCount; i++)
            {
                // Classic two pass gaussian blur - use mipUp as a temporary target
                //   First pass does 2x downsampling + 9-tap gaussian
                //   Second pass does 9-tap gaussian using a 5-tap filter + bilinear filtering
                Blitter.BlitCameraTexture(cmd, lastDown, m_BloomMipUp[i], RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store, bloomMaterial, 1);
                Blitter.BlitCameraTexture(cmd, m_BloomMipUp[i], m_BloomMipDown[i], RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store, bloomMaterial, 2);

                lastDown = m_BloomMipDown[i];
            }

            // Upsample (bilinear by default, HQ filtering does bicubic instead
            for (int i = mipCount - 2; i >= 0; i--)
            {
                var lowMip = (i == mipCount - 2) ? m_BloomMipDown[i + 1] : m_BloomMipUp[i + 1];
                var highMip = m_BloomMipDown[i];
                var dst = m_BloomMipUp[i];

                cmd.SetGlobalTexture("_SourceTexLowMip", lowMip);
                Blitter.BlitCameraTexture(cmd, highMip, dst, RenderBufferLoadAction.DontCare, RenderBufferStoreAction.Store, bloomMaterial, 3);
            }

            cmd.SetGlobalTexture("_Bloom_Texture", m_BloomMipUp[0]);

            cmd.SetGlobalFloat("_Bloom_Intensity", m_BloomEffect.intensity.value);
        }

        RenderTextureDescriptor GetCompatibleDescriptor()
                => GetCompatibleDescriptor(m_Descriptor.width, m_Descriptor.height, m_Descriptor.graphicsFormat);

        RenderTextureDescriptor GetCompatibleDescriptor(int width, int height, GraphicsFormat format, DepthBits depthBufferBits = DepthBits.None)
            => GetCompatibleDescriptor(m_Descriptor, width, height, format, depthBufferBits);

        internal static RenderTextureDescriptor GetCompatibleDescriptor(RenderTextureDescriptor desc, int width, int height, GraphicsFormat format, DepthBits depthBufferBits = DepthBits.None)
        {
            desc.depthBufferBits = (int)depthBufferBits;
            desc.msaaSamples = 1;
            desc.width = width;
            desc.height = height;
            desc.graphicsFormat = format;
            return desc;
        }
        public void Dispose()
        {

            // 如果还有你在构造函数里 RTHandles.Alloc 的金字塔：
            if (m_BloomMipUp != null)
                for (int i = 0; i < m_BloomMipUp.Length; i++)
                    m_BloomMipUp[i]?.Release();
            if (m_BloomMipDown != null)
                for (int i = 0; i < m_BloomMipDown.Length; i++)
                    m_BloomMipDown[i]?.Release();
        }
        #endregion
    }
    BendayBloomRenderPass m_ScriptablePass;

    public override void Create()
    {
        // 根据shader创建材质
        m_bloomMaterial = CoreUtils.CreateEngineMaterial(m_bloomShader);
        m_compositeMaterial = CoreUtils.CreateEngineMaterial(m_compositeShader);

        m_ScriptablePass = new BendayBloomRenderPass(m_bloomMaterial,m_compositeMaterial);

        m_ScriptablePass.renderPassEvent = RenderPassEvent.BeforeRenderingPostProcessing;
    }

    // 销毁材质
    protected override void Dispose(bool disposing)
    {
        CoreUtils.Destroy(m_bloomMaterial);
        CoreUtils.Destroy(m_compositeMaterial);
        m_ScriptablePass?.Dispose();
    }

    public override void AddRenderPasses(ScriptableRenderer renderer, ref RenderingData renderingData)
    {
        if (m_bloomMaterial == null || m_compositeMaterial == null) return;
        renderer.EnqueuePass(m_ScriptablePass);
    }


}