#!/usr/bin/env bash
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

SET_FLAG=""
SET_NAME="full"
RUN_MODE="paired"
MODE_FLAG=""

for argument in "$@"; do
  case "$argument" in
    --smoke)
      SET_FLAG="-DREFLECTION_SCENARIO_SMOKE"
      SET_NAME="smoke"
      ;;
    --standard)
      SET_FLAG="-DREFLECTION_SCENARIO_STANDARD"
      SET_NAME="standard"
      ;;
    --full)
      SET_FLAG=""
      SET_NAME="full"
      ;;
    --paired)
      RUN_MODE="paired"
      MODE_FLAG=""
      ;;
    --assigned)
      RUN_MODE="assigned"
      MODE_FLAG="-DREFLECTION_SCENARIO_ASSIGNED_ONLY"
      ;;
    *)
      echo "用法: $0 [--smoke|--standard|--full] [--paired|--assigned]" >&2
      exit 2
      ;;
  esac
done

STAMP="$(date '+%Y%m%d-%H%M%S')"
OUTPUT_DIR="$ROOT_DIR/tmp/reflection-scenario-results/$STAMP-$SET_NAME-$RUN_MODE"
RESULT_BUNDLE="$OUTPUT_DIR/scenarios.xcresult"
ATTACHMENT_DIR="$OUTPUT_DIR/reports"
BUILD_LOG="$OUTPUT_DIR/xcodebuild.log"
mkdir -p "$ATTACHMENT_DIR"

SIMULATOR_NAME="iPhone 17 Pro"
INJECTED_ENV_NAMES=()

clear_simulator_test_environment() {
  for variable_name in "${INJECTED_ENV_NAMES[@]}"; do
    xcrun simctl spawn "$SIMULATOR_NAME" \
      launchctl unsetenv "$variable_name" >/dev/null 2>&1 || true
  done
}

inject_simulator_environment() {
  local variable_name="$1"
  local variable_value="$2"
  xcrun simctl spawn "$SIMULATOR_NAME" \
    launchctl setenv "$variable_name" "$variable_value"
  INJECTED_ENV_NAMES+=("$variable_name")
}

trap clear_simulator_test_environment EXIT INT TERM

SWIFT_FLAGS='$(inherited) -DLIVE_REFLECTION_SCENARIOS'
if [[ -n "$SET_FLAG" ]]; then
  SWIFT_FLAGS="$SWIFT_FLAGS $SET_FLAG"
fi
if [[ -n "$MODE_FLAG" ]]; then
  SWIFT_FLAGS="$SWIFT_FLAGS $MODE_FLAG"
fi

echo "案例集: $SET_NAME"
echo "运行模式: $RUN_MODE"
echo "输出目录: $OUTPUT_DIR"
echo "测试会调用 Config.xcconfig 当前配置的正式后端 Planner / Writer。"
if [[ "$RUN_MODE" == "paired" ]]; then
  if [[ -z "${REFLECTION_SCENARIO_CARD_USERNAME:-}" ||
        -z "${REFLECTION_SCENARIO_CARD_PASSWORD:-}" ||
        -z "${REFLECTION_SCENARIO_DIRECT_USERNAME:-}" ||
        -z "${REFLECTION_SCENARIO_DIRECT_PASSWORD:-}" ]]; then
    echo "配对模式需要卡牌组和对照组两个当前有效的测试账号。" >&2
    echo "请设置 REFLECTION_SCENARIO_CARD_* 和 REFLECTION_SCENARIO_DIRECT_* 环境变量。" >&2
    exit 2
  fi
elif [[ -z "${REFLECTION_SCENARIO_USERNAME:-}" ||
        -z "${REFLECTION_SCENARIO_PASSWORD:-}" ]]; then
  echo "未设置单组测试账号；将尝试使用同一模拟器中已登录 App 的会话。"
fi

if [[ "$RUN_MODE" == "paired" ||
      ( -n "${REFLECTION_SCENARIO_USERNAME:-}" &&
        -n "${REFLECTION_SCENARIO_PASSWORD:-}" ) ]]; then
  echo "正在准备测试模拟器的临时登录环境……"
  xcrun simctl boot "$SIMULATOR_NAME" >/dev/null 2>&1 || true
  if ! xcrun simctl bootstatus "$SIMULATOR_NAME" -b; then
    echo "无法启动 $SIMULATOR_NAME 模拟器。" >&2
    exit 2
  fi

  if [[ "$RUN_MODE" == "paired" ]]; then
    inject_simulator_environment \
      REFLECTION_SCENARIO_CARD_USERNAME "$REFLECTION_SCENARIO_CARD_USERNAME"
    inject_simulator_environment \
      REFLECTION_SCENARIO_CARD_PASSWORD "$REFLECTION_SCENARIO_CARD_PASSWORD"
    inject_simulator_environment \
      REFLECTION_SCENARIO_DIRECT_USERNAME "$REFLECTION_SCENARIO_DIRECT_USERNAME"
    inject_simulator_environment \
      REFLECTION_SCENARIO_DIRECT_PASSWORD "$REFLECTION_SCENARIO_DIRECT_PASSWORD"
  else
    inject_simulator_environment \
      REFLECTION_SCENARIO_USERNAME "$REFLECTION_SCENARIO_USERNAME"
    inject_simulator_environment \
      REFLECTION_SCENARIO_PASSWORD "$REFLECTION_SCENARIO_PASSWORD"
  fi
fi

set +e
xcodebuild test \
  -quiet \
  -project BeyondComfort.xcodeproj \
  -scheme BeyondComfort \
  -sdk iphonesimulator \
  -destination "platform=iOS Simulator,name=$SIMULATOR_NAME" \
  -parallel-testing-enabled NO \
  -resultBundlePath "$RESULT_BUNDLE" \
  -only-testing:BeyondComfortTests/ReflectionLiveScenarioTests/testLivePairedScenarioMatrix \
  CODE_SIGNING_ALLOWED=NO \
  "OTHER_SWIFT_FLAGS=$SWIFT_FLAGS" \
  2>&1 | tee "$BUILD_LOG"
TEST_STATUS=${PIPESTATUS[0]}
set -e

if [[ -d "$RESULT_BUNDLE" ]]; then
  xcrun xcresulttool export attachments \
    --path "$RESULT_BUNDLE" \
    --output-path "$ATTACHMENT_DIR" >/dev/null 2>&1 || true
fi

echo
echo "=== 服务器实际实验条件 ==="
ASSIGNMENT_OUTPUT="$(
  {
    grep 'REFLECTION_SCENARIO_ASSIGNMENT' "$BUILD_LOG" 2>/dev/null || true
    grep -R -h 'REFLECTION_SCENARIO_ASSIGNMENT' \
      "$ATTACHMENT_DIR" 2>/dev/null || true
  } | sort -u
)"
if [[ -n "$ASSIGNMENT_OUTPUT" ]]; then
  printf '%s\n' "$ASSIGNMENT_OUTPUT"
else
  echo "未读取到实验条件；请查看测试失败信息或完整日志。"
fi

echo
echo "=== 报告文件 ==="
find "$ATTACHMENT_DIR" -maxdepth 1 -type f \
  \( -name '*.md' -o -name '*.json' \) \
  -print | sort
echo "完整 xcodebuild 日志: $BUILD_LOG"

if [[ "$TEST_STATUS" -ne 0 ]]; then
  echo "部分案例没有完成或违反配对协议；详细原因已写入报告。" >&2
fi
exit "$TEST_STATUS"
