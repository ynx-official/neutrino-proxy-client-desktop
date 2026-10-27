<script setup>
import { computed } from "vue";
const props = defineProps({ preview: { type: Object, required: true } });
const fields = computed(() => {
  const config = props.preview.config;
  const selected = new Set(props.preview.importedFields || []);
  const candidates = [
    ["tunnel.server-ip", "服务器地址", config.server],
    ["tunnel.server-port", "端口", config.port],
    ["tunnel.ssl-enable", "SSL", config.ssl ? "已启用" : "未启用"],
    ["tunnel.license-key", "License", "已读取，隐藏明文"],
    ["tunnel.jks-path", "信任证书", config.certificatePath || "内置证书"],
    ["tunnel.key-store-password", "证书密码", "已读取，隐藏明文"],
    ["tunnel.client-id", "客户端 ID", config.clientId],
    ["tunnel.reconnection.interval-seconds", "重连间隔", `${config.reconnectSeconds} 秒`],
    ["tunnel.reconnection.unlimited", "无限重试", config.unlimited ? "已启用" : "未启用"],
    ["client.udp.puppet-port-range", "UDP 端口范围", config.udpPortRange],
    ["protocol.read-idle-time", "读取空闲超时", `${config.readIdleSeconds} 秒`],
    ["protocol.write-idle-time", "写空闲心跳", `${config.heartbeatSeconds} 秒`],
    ["protocol.all-idle-time-seconds", "读写空闲超时", `${config.allIdleSeconds} 秒`],
    ["protocol.water-mark", "写缓冲水位线", config.waterMark || "默认 32KB/64KB"],
    ["protocol.max-frame-length", "最大帧长", config.maxFrameLength],
    ["protocol.length-field-offset", "长度字段偏移", config.lengthFieldOffset],
    ["protocol.length-field-length", "长度字段字节数", config.lengthFieldLength],
    ["protocol.length-adjustment", "帧长调整", config.lengthAdjustment],
    ["protocol.initial-bytes-to-strip", "剥离字节数", config.initialBytesToStrip],
  ];
  return candidates.filter(([key]) => selected.has(`neutrino.proxy.${key}`));
});
</script>

<template>
  <dl v-if="preview.canApply && fields.length" class="import-fields" aria-label="本次识别的配置">
    <div v-for="[key, label, value] in fields" :key="key">
      <dt>{{ label }}</dt><dd>{{ value }}</dd>
    </div>
  </dl>
</template>

<style scoped>
.import-fields { display: grid; gap: 9px; margin: 16px 0; font-size: 14px; }
.import-fields > div { display: grid; grid-template-columns: 100px minmax(0, 1fr); gap: 12px; }
dt { color: var(--muted); }
dd { min-width: 0; margin: 0; overflow-wrap: anywhere; }
</style>
