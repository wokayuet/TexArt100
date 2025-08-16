using UnityEngine;

public class ThirdPersonCamera : MonoBehaviour
{
    [Header("Target")]
    public Transform targetPivot;       // ★ 指向 FPSController 上的 cameraPivot
    public Vector3 pivotOffset = new Vector3(0f, 0.2f, 0f);

    [Header("Orbit")]
    public float distance = 3.5f;       // 默认相机距离
    public float minDistance = 1.0f;
    public float maxDistance = 4.5f;
    public float zoomSpeed = 3f;        // 滚轮缩放

    [Header("Collision")]
    public LayerMask obstacleMask = ~0; // 与哪些层碰撞（默认所有）
    public float collisionRadius = 0.2f;
    public float collisionLerp = 20f;

    float currentDistance;

    void Start()
    {
        currentDistance = distance;
        if (targetPivot == null)
        {
            var player = FindObjectOfType<FPSController>();
            if (player != null) targetPivot = player.cameraPivot;
        }
    }

    void LateUpdate()
    {
        if (targetPivot == null) return;

        // —— 鼠标滚轮缩放 —— 
        float scroll = Input.mouseScrollDelta.y;
        if (Mathf.Abs(scroll) > 0.0001f)
        {
            distance = Mathf.Clamp(distance - scroll * zoomSpeed, minDistance, maxDistance);
        }

        // —— 以 targetPivot 的旋转为相机朝向 —— 
        Quaternion orbitRot = targetPivot.rotation;
        Vector3 desiredCamPos = targetPivot.position + pivotOffset - (orbitRot * Vector3.forward) * distance;

        // —— 基础防穿模（从 pivot 向理想位发射线/球体，命中则拉近）——
        Vector3 pivotPos = targetPivot.position + pivotOffset;
        Vector3 dir = (desiredCamPos - pivotPos);
        float dst = dir.magnitude;
        Vector3 camPos = desiredCamPos;

        if (dst > 0.001f)
        {
            dir /= dst;
            // 用 SphereCast 更“包容”；如嫌贵可换 Linecast
            if (Physics.SphereCast(pivotPos, collisionRadius, dir, out RaycastHit hit, dst, obstacleMask, QueryTriggerInteraction.Ignore))
            {
                float safeDst = Mathf.Max(hit.distance - 0.05f, minDistance);
                currentDistance = Mathf.Lerp(currentDistance, safeDst, Time.deltaTime * collisionLerp);
            }
            else
            {
                currentDistance = Mathf.Lerp(currentDistance, distance, Time.deltaTime * collisionLerp);
            }
            camPos = pivotPos - (orbitRot * Vector3.forward) * currentDistance;
        }

        transform.position = camPos;
        transform.rotation = orbitRot;
    }
}
