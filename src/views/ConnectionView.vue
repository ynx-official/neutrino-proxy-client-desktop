<script setup>
import { computed, ref, onMounted, onUnmounted } from "vue";
import Icon from "../components/AppIcon.vue";
import { isActive, stateLabels } from "../services/state";
const props = defineProps({ model: Object, actions: Object });
const now = ref(Date.now());
let clock;
onMounted(() => {
  clock = setInterval(() => (now.value = Date.now()), 1000);
});
onUnmounted(() => clearInterval(clock));
const connected = computed(() => props.model.state === "connected");
const config = computed(() => props.model.activeConfig || props.model.config);
const duration = computed(() => {
  if (!props.model.connectedAt) return "—";
  const seconds = Math.max(
    0,
    Math.floor((now.value - new Date(props.model.connectedAt)) / 1000),
  );
  return [
    Math.floor(seconds / 3600),
    Math.floor(seconds / 60) % 60,
    seconds % 60,
  ]
    .map((n) => String(n).padStart(2, "0"))
    .join(":");
});
const remaining = computed(() =>
  props.model.retryAt
    ? Math.max(0, Math.ceil((new Date(props.model.retryAt) - now.value) / 1000))
    : null,
);
const time = (value) =>
  new Date(value).toLocaleTimeString("zh-CN", { hour12: false });
const recent = computed(() => (props.model.logs || []).slice(-3));
</script>
<template>
  <section class="connection-page">
    <section class="connection-status" aria-labelledby="connection-title">
      <div class="status-main">
        <div class="hero-status">
          <span
            :class="[
              'status-indicator',
              {
                online: connected,
                failed: model.state === 'error',
                working: isActive(model.state) && !connected,
              },
            ]"
            aria-hidden="true"
          >
            <Icon v-if="model.state === 'error'" name="alert" :size="17" />
            <Icon
              v-else-if="isActive(model.state) && !connected"
              name="refresh"
              :size="16"
              :class="{
                spinning: ['connecting', 'authenticating'].includes(
                  model.state,
                ),
              }"
            />
          </span>
          <h1 id="connection-title">
            {{ stateLabels[model.state] || "尚未连接" }}
          </h1>
        </div>
        <p
          v-if="config.server"
          class="hero-endpoint"
          :title="config.server + ':' + config.port"
        >
          <span>{{ config.server }}</span
          ><span class="endpoint-port">:{{ config.port }}</span>
        </p>
        <p
          v-if="['error', 'reconnecting'].includes(model.state) && model.detail"
          class="hero-error"
          role="status"
        >
          {{ model.detail }}
        </p>
        <p v-if="remaining !== null" class="retry-note">
          {{ remaining }} 秒后重试
        </p>
        <button
          v-if="model.config.server"
          class="text-link edit-connection"
          @click="actions.navigate?.('/settings')"
        >
          <Icon name="settings" :size="17" />编辑连接
        </button>
      </div>
      <div class="status-side">
        <div class="hero-actions">
          <template v-if="isActive(model.state)">
            <button
              v-if="model.state === 'reconnecting'"
              class="button primary"
              @click="actions.connect?.()"
            >
              <Icon name="refresh" :size="17" />立即重试
            </button>
            <button
              data-testid="disconnect"
              class="button secondary"
              :disabled="model.state === 'stopping'"
              @click="actions.disconnect?.()"
            >
              <Icon name="power" :size="17" />{{
                connected
                  ? "断开连接"
                  : model.state === "reconnecting"
                    ? "停止重连"
                    : "取消连接"
              }}
            </button>
          </template>
          <button
            v-else-if="model.config.server && model.hasLicense"
            class="button primary"
            @click="actions.connect?.()"
          >
            <Icon name="power" :size="17" />{{
              model.state === "error" ? "重新连接" : "连接"
            }}
          </button>
          <template v-else>
            <button
              class="button primary"
              @click="actions.navigate?.('/settings')"
            >
              填写连接信息
            </button>
            <button class="button quiet" @click="actions.importConfig?.()">
              导入配置
            </button>
          </template>
        </div>
        <div v-if="config.server" class="hero-duration">
          <span>本次连接</span><strong>{{ duration }}</strong>
        </div>
      </div>
    </section>
    <dl v-if="model.config.server" class="connection-meta">
      <div>
        <dt>SSL</dt>
        <dd>{{ config.ssl ? "已启用" : "未启用" }}</dd>
      </div>
      <div>
        <dt>License</dt>
        <dd class="license-hint">
          {{ model.licenseHint || (model.hasLicense ? "已保存" : "未配置") }}
        </dd>
      </div>
    </dl>
    <p v-if="model.pendingConfig" class="pending-notice">
      <Icon name="info" :size="16" />新配置将在下次连接时生效
    </p>
    <section class="recent-events" aria-labelledby="events-title">
      <div class="section-heading">
        <h3 id="events-title">最近事件</h3>
        <button class="text-link" @click="actions.navigate?.('/logs')">
          全部日志<Icon name="chevron" :size="16" />
        </button>
      </div>
      <div v-if="!recent.length" class="empty-events">暂无事件</div>
      <ul v-else class="event-list">
        <li v-for="entry in recent" :key="entry.id">
          <Icon
            :name="
              entry.level === 'error' || entry.level === 'warn'
                ? 'alert'
                : 'check'
            "
            :size="17"
            :class="
              entry.level === 'error'
                ? 'danger'
                : entry.level === 'warn'
                  ? 'warning'
                  : 'success'
            "
          />
          <span>{{ entry.message }}</span
          ><time>{{ time(entry.time) }}</time>
        </li>
      </ul>
    </section>
  </section>
</template>
