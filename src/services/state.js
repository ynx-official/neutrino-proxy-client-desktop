export const defaultConfig = () => ({
  server: "",
  port: 9002,
  ssl: true,
  clientId: "",
  reconnectSeconds: 10,
  unlimited: false,
  udpPortRange: "10000-10500",
  readIdleSeconds: 120,
  heartbeatSeconds: 20,
  allIdleSeconds: 0,
  waterMark: "",
  maxFrameLength: 2097152,
  lengthFieldOffset: 0,
  lengthFieldLength: 4,
  lengthAdjustment: 0,
  initialBytesToStrip: 0,
  certificatePath: "",
});
export const initialModel = () => ({
  config: defaultConfig(),
  state: "idle",
  detail: "填写连接信息，开始第一次连接",
  hasLicense: false,
  licenseHint: "尚未设置",
  logs: [],
  revision: 0,
  connectedAt: null,
  retryAt: null,
  pendingConfig: false,
  version: "0.1.0",
});
export const stateLabels = {
  idle: "尚未连接",
  validating: "正在检查配置",
  connecting: "正在连接",
  authenticating: "正在验证 License",
  connected: "已连接",
  reconnecting: "等待重新连接",
  stopping: "正在断开",
  error: "连接失败",
};
export const isActive = (state) =>
  [
    "connecting",
    "authenticating",
    "connected",
    "reconnecting",
    "stopping",
  ].includes(state);
export function validateForm(config, license, hasLicense) {
  const errors = {};
  if (!config.server?.trim()) errors.server = "请填写服务器地址";
  else if (/[\/\s]/.test(config.server) || config.server.includes("://"))
    errors.server = "请填写域名或 IP，不包含协议和路径";
  if (
    !Number.isInteger(Number(config.port)) ||
    Number(config.port) < 1 ||
    Number(config.port) > 65535
  )
    errors.port = "端口应为 1–65535 的整数";
  if (!hasLicense && !license) errors.license = "请填写 License";
  if (Number(config.reconnectSeconds) < 1)
    errors.reconnectSeconds = "重连间隔至少为 1 秒";
  const parts = /^(\d+)-(\d+)$/.exec(config.udpPortRange || "");
  if (!parts || +parts[1] < 1 || +parts[2] > 65535 || +parts[2] <= +parts[1])
    errors.udpPortRange = "请输入有效范围，例如 10000-10500";
  return errors;
}
