using System.Collections;
using System.Collections.Generic;
using UnityEngine;

public class FPSController : PortalTraveller
{
    [Header("Movement")]
    public float walkSpeed = 3f;
    public float runSpeed = 6f;
    public float smoothMoveTime = 0.1f;
    public float jumpForce = 8f;
    public float gravity = 18f;
    public float turnSpeed = 10f; // ★ 新增：角色朝向插值速度（度/秒）

    [Header("Mouse/Camera")]
    public bool lockCursor = true;
    public float mouseSensitivity = 150f; // ★ 新增：鼠标灵敏度（度/秒）
    public Vector2 pitchMinMax = new Vector2(-40f, 85f);
    public float rotationSmoothTime = 0.05f;
    public Transform cameraPivot; // ★ 新增：角色身上的相机枢轴（通常在角色头顶稍上）

    CharacterController controller;

    // yaw/pitch 基于相机的水平/垂直旋转
    public float yaw;   // 水平角（绕Y）
    public float pitch; // 俯仰角（绕X）
    float smoothYaw;
    float smoothPitch;
    float yawSmoothV;
    float pitchSmoothV;

    float verticalVelocity;
    Vector3 velocity;
    Vector3 smoothV;

    bool jumping;
    float lastGroundedTime;
    bool disabled;

    void Start()
    {
        if (lockCursor)
        {
            Cursor.lockState = CursorLockMode.Locked;
            Cursor.visible = false;
        }

        controller = GetComponent<CharacterController>();

        // 初始 yaw/pitch
        yaw = transform.eulerAngles.y;
        smoothYaw = yaw;
        // pitch 可保持 0 或自定义初始值
        smoothPitch = pitch;

        // 如果没指定 cameraPivot，就在角色上创建一个
        if (cameraPivot == null)
        {
            GameObject pivot = new GameObject("CameraPivot");
            cameraPivot = pivot.transform;
            cameraPivot.SetParent(transform, false);
            cameraPivot.localPosition = new Vector3(0, 1.6f, 0); // 大致头顶
        }
    }

    void Update()
    {
        if (Input.GetKeyDown(KeyCode.P))
        {
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
            Debug.Break();
        }
        if (Input.GetKeyDown(KeyCode.O))
        {
            Cursor.lockState = CursorLockMode.None;
            Cursor.visible = true;
            disabled = !disabled;
        }
        if (disabled) return;

        // —— 处理相机旋转（右键按住才旋转视角）——
        bool rotatingView = Input.GetMouseButton(1);
        if (rotatingView)
        {
            float mX = Input.GetAxisRaw("Mouse X");
            float mY = Input.GetAxisRaw("Mouse Y");

            yaw += mX * mouseSensitivity * Time.deltaTime;
            pitch -= mY * mouseSensitivity * Time.deltaTime;
            pitch = Mathf.Clamp(pitch, pitchMinMax.x, pitchMinMax.y);
        }

        // 平滑
        smoothYaw = Mathf.SmoothDampAngle(smoothYaw, yaw, ref yawSmoothV, rotationSmoothTime);
        smoothPitch = Mathf.SmoothDamp(smoothPitch, pitch, ref pitchSmoothV, rotationSmoothTime);

        // —— 基于“相机朝向”的移动输入 —— 
        Vector2 input = new Vector2(Input.GetAxisRaw("Horizontal"), Input.GetAxisRaw("Vertical"));
        Vector3 camForward = Quaternion.Euler(0f, smoothYaw, 0f) * Vector3.forward; // 只取水平面朝向
        Vector3 camRight = Quaternion.Euler(0f, smoothYaw, 0f) * Vector3.right;
        Vector3 inputDir = (camForward * input.y + camRight * input.x);
        inputDir.y = 0f;
        Vector3 moveDir = inputDir.sqrMagnitude > 0.001f ? inputDir.normalized : Vector3.zero;

        float currentSpeed = (Input.GetKey(KeyCode.LeftShift)) ? runSpeed : walkSpeed;
        Vector3 targetVelocity = moveDir * currentSpeed;
        velocity = Vector3.SmoothDamp(velocity, targetVelocity, ref smoothV, smoothMoveTime);

        // —— 跳跃与重力 —— 
        verticalVelocity -= gravity * Time.deltaTime;
        Vector3 fullVel = new Vector3(velocity.x, verticalVelocity, velocity.z);
        var flags = controller.Move(fullVel * Time.deltaTime);

        if ((flags & CollisionFlags.Below) != 0)
        {
            jumping = false;
            lastGroundedTime = Time.time;
            verticalVelocity = 0f;
        }

        if (Input.GetKeyDown(KeyCode.Space))
        {
            float timeSinceLastTouchedGround = Time.time - lastGroundedTime;
            if (controller.isGrounded || (!jumping && timeSinceLastTouchedGround < 0.15f))
            {
                jumping = true;
                verticalVelocity = jumpForce;
            }
        }

        // —— 角色朝向：有移动输入时，朝向移动方向（水平）——
        if (moveDir.sqrMagnitude > 0.0001f)
        {
            Quaternion targetRot = Quaternion.LookRotation(moveDir, Vector3.up);
            transform.rotation = Quaternion.RotateTowards(transform.rotation, targetRot, turnSpeed * Time.deltaTime * 100f);
        }

        // —— 驱动 cameraPivot 的朝向（提供给相机脚本使用）——
        cameraPivot.rotation = Quaternion.Euler(smoothPitch, smoothYaw, 0f);
    }

    // —— 传送：保持原有逻辑，并同步 yaw 以避免相机/朝向突兀 —— 
    public override void Teleport(Transform fromPortal, Transform toPortal, Vector3 pos, Quaternion rot)
    {
        transform.position = pos;

        // rot 是传送后的角色旋转
        Vector3 eulerRot = rot.eulerAngles;
        float delta = Mathf.DeltaAngle(smoothYaw, eulerRot.y);

        // 同步 yaw，使相机参考方向与角色传送后的面向一致
        yaw += delta;
        smoothYaw += delta;

        transform.eulerAngles = Vector3.up * eulerRot.y;

        // 速度空间变换保持不变
        velocity = toPortal.TransformVector(fromPortal.InverseTransformVector(velocity));

        Physics.SyncTransforms();
    }
}
