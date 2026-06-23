# pika_gripper_hardware

ROS 2 `ros2_control` hardware plugin for **AgileX Pika gripper** over raw SocketCAN, without `pika_sdk`.

## Protocol basis

Based on the AgileX `pyAgxArm` protocol (`ArmMsgGripperCtrl` / `ArmMsgFeedbackGripper`):

- **Command CAN ID**: `0x159` (`ARM_GRIPPER_CTRL`)
- **Feedback CAN ID**: `0x2A8` (`ARM_GRIPPER_FEEDBACK`)
- Frame layout uses **big-endian** encoding:
  - **Command** (8 bytes): `int32 position(µm)` | `uint16 force(mN)` | `uint8 status_code` | `uint8 set_zero`
  - **Feedback** (8 bytes): `int32 position(µm)` | `int16 force(mN)` | `uint8 status_code` | `uint8 mode(0x00=width, 0x01=angle)`

### Status code bits (command)

| Value | Meaning |
|-------|---------|
| `0x00` | Disable, width mode |
| `0x01` | Enable, width mode |
| `0x02` | Disable + clear, width mode |
| `0x03` | Enable + clear, width mode |
| `0x04` | Disable, angle mode |
| `0x05` | Enable, angle mode |
| `0x06` | Disable + clear, angle mode |
| `0x07` | Enable + clear, angle mode |

### Status code bits (feedback)

| Bit | Meaning |
|-----|---------|
| 0 | Voltage too low |
| 1 | Motor overheating |
| 2 | Driver overcurrent |
| 3 | Driver overheating |
| 4 | Sensor fault |
| 5 | Driver fault |
| 6 | Driver enabled |
| 7 | Homed / zeroed |

## Build (Jazzy)

```bash
colcon build --packages-select pika_gripper_hardware
```

## Quick CAN debug helpers

Two helper scripts are included:

- `scripts/can_activate.sh`
  - bring CAN interface up/down with bitrate settings
  - supports classic CAN and CAN-FD mode
- `scripts/pika_gripper_cansend.sh`
  - send basic gripper debug commands via `cansend`
  - includes `monitor` mode (`candump`) for feedback ID filtering
  - supports both width and angle mode commands (`enable-angle`, `move-deg`)

Examples:

```bash
# 1) Bring up can0
./scripts/can_activate.sh --iface can0 --bitrate 1000000

# 2) Enable gripper and clear faults (width mode)
./scripts/pika_gripper_cansend.sh --iface can0 enable-clear

# 3) Move gripper to 30 mm
./scripts/pika_gripper_cansend.sh --iface can0 move --pos-m 0.03

# 4) Enable in angle mode + move to 45 degrees
./scripts/pika_gripper_cansend.sh --iface can0 enable-clear-angle
./scripts/pika_gripper_cansend.sh --iface can0 move-deg --pos-deg 45.0

# 5) Monitor feedback frames (default 0x2A8)
./scripts/pika_gripper_cansend.sh --iface can0 monitor
```

## ros2_control URDF snippet

```xml
<ros2_control name="pika_gripper" type="system">
  <hardware>
    <plugin>pika_gripper_hardware/PikaGripperHardware</plugin>
    <param name="can_interface">can0</param>
    <param name="command_can_id">345</param> <!-- 0x159 -->
    <param name="feedback_can_id">680</param> <!-- 0x2A8 -->
    <param name="min_position_m">0.0</param>
    <param name="max_position_m">0.08</param>
    <param name="initial_position_m">0.0</param>
    <param name="default_force_mn">1000</param>
    <param name="feedback_timeout_ms">1000</param>
    <param name="command_refresh_interval_ms">100</param>
    <param name="publish_debug_commands">false</param>
    <param name="publish_sent_position">false</param>
    <param name="publish_feedback_position">false</param>
    <param name="debug_topic_prefix"></param>
  </hardware>

  <joint name="gripper_joint">
    <command_interface name="position"/>
    <state_interface name="position"/>
    <state_interface name="effort"/>
    <state_interface name="status_code"/>
    <state_interface name="enabled"/>
    <state_interface name="homed"/>
    <state_interface name="fault"/>
  </joint>
</ros2_control>
```

## Runtime behavior

- **Activate** sends `status=0x03` (enable + clear error, width mode), then periodic `status=0x01` commands.
- **Deactivate** sends `status=0x00` (disable).
- Command input is `position` in meters, converted to protocol unit (`1e-6 m` per count).
- Exposes feedback: position, effort (force in N), status_code, enabled, homed, fault.
- Optional debug topics:
  - `~/gripper_command_debug` (UInt8MultiArray)
  - `~/gripper_command_debug_stamped` (StampedUInt8MultiArray)
  - `~/gripper_sent_position_debug` (Float64)
  - `~/gripper_sent_position_debug_stamped` (StampedFloat64)
  - `~/gripper_feedback_debug` (UInt8MultiArray)
  - `~/gripper_feedback_debug_stamped` (StampedUInt8MultiArray)

## Notes and caveats

- In most single-arm setups, only `can_interface` changes (`can0`, `can1`, ...).
- `command_can_id` / `feedback_can_id` are usually fixed defaults:
  - `command_can_id = 0x159`
  - `feedback_can_id = 0x2A8`
- If the arm was configured with master/slave offset command `0x470`, CAN IDs can shift:
  - Control base can shift `15x -> 16x/17x` (gripper command may become `0x169/0x179`)
  - Feedback base can shift `2Ax -> 2Bx/2Cx` (gripper feedback may become `0x2B8/0x2C8`)
- In offset mode, update `command_can_id` and `feedback_can_id` params accordingly.
- Quick check recommendation:
  - sniff bus first (`candump`) and confirm the real gripper TX/RX IDs
  - then align ros2_control params with observed IDs

## Differences from piper_gripper_hardware

This package is derived from `piper_gripper_hardware` but adapted for the Pika gripper:
- **Protocol**: Same CAN IDs (0x159/0x2A8), same byte layout. Pika adds byte 7 `mode` (width/angle) in feedback.
- **`force_mn` replaces `effort_mn`**: The Pika protocol uses "force" in mN rather than "effort" in mN·m.
- **Angle mode support**: Status codes 0x04-0x07 and feedback byte 7 expose the angle mode.
