#ifndef PIKA_GRIPPER_HARDWARE_PIKA_GRIPPER_PROTOCOL_HPP_
#define PIKA_GRIPPER_HARDWARE_PIKA_GRIPPER_PROTOCOL_HPP_

#include <linux/can.h>

#include <cstdint>
#include <optional>

namespace pika_gripper_hardware::protocol
{

// 0x159: host -> gripper command
constexpr canid_t kGripperCommandCanId = 0x159;
// 0x2A8: gripper -> host feedback
constexpr canid_t kGripperFeedbackCanId = 0x2A8;

enum class GripperMode : std::uint8_t
{
  kWidth = 0x00,
  kAngle = 0x01,
};

struct Command
{
  double position_m{0.0};
  std::uint16_t force_mn{1000};  // 0.001 N per unit (mN)
  std::uint8_t status_code{0x01};
  std::uint8_t set_zero{0x00};
};

struct Feedback
{
  double position_m{0.0};
  double force_n{0.0};
  std::uint8_t status_code{0x00};
  GripperMode mode{GripperMode::kWidth};
  bool voltage_too_low{false};
  bool motor_overheating{false};
  bool driver_overcurrent{false};
  bool driver_overheating{false};
  bool sensor_fault{false};
  bool driver_fault{false};
  bool driver_enabled{false};
  bool homed{false};
};

auto make_command_frame(canid_t can_id, const Command& command) -> can_frame;
auto parse_feedback_frame(const can_frame& frame, canid_t expected_can_id) -> std::optional<Feedback>;

}  // namespace pika_gripper_hardware::protocol

#endif  // PIKA_GRIPPER_HARDWARE_PIKA_GRIPPER_PROTOCOL_HPP_
