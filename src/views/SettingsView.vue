<script setup>
import { computed, reactive, ref, watch, onUnmounted } from "vue";
import Icon from "../components/AppIcon.vue";
import { defaultConfig, isActive, validateForm } from "../services/state";
const props = defineProps({ model: Object, actions: Object });
const draft = reactive({ ...defaultConfig(), ...props.model.config });
const baseline = ref(JSON.stringify(draft));
const license = ref(""),
  password = ref(""),
  showLicense = ref(false),
  advanced = ref(false),
  pending = ref(false),
  error = ref(""),
  saved = ref(""),
  errors = ref({});
const dirty = computed(
  () =>
    JSON.stringify(draft) !== baseline.value ||
    !!license.value ||
    !!password.value,
);
watch(dirty, (value) => props.actions.setDirty?.(value));
watch(
  () => props.model.config,
  (config) => {
    if (!dirty.value) {
      Object.assign(draft, defaultConfig(), config);
      baseline.value = JSON.stringify(draft);
    }
  },
);
watch(
  [draft, license],
  () => {
    if (Object.keys(errors.value).length)
      errors.value = validateForm(draft, license.value, props.model.hasLicense);
  },
  { deep: true },
);
onUnmounted(() => props.actions.setDirty?.(false));
const jks = computed(() => /\.jks$/i.test(draft.certificatePath || ""));
const active = computed(() => isActive(props.model.state));
async function submit(connect = true) {
  error.value = "";
  saved.value = "";
  errors.value = validateForm(draft, license.value, props.model.hasLicense);
  if (Object.keys(errors.value).length) return;
  pending.value = true;
  try {
    await props.actions.save({
      config: {
        ...draft,
        port: Number(draft.port),
        reconnectSeconds: Number(draft.reconnectSeconds),
        heartbeatSeconds: Number(draft.heartbeatSeconds),
        readIdleSeconds: Number(draft.readIdleSeconds),
      },
      license: license.value || null,
      storePassword: password.value || null,
      connect,
    });
    license.value = "";
    password.value = "";
    baseline.value = JSON.stringify(draft);
    props.actions.setDirty?.(false);
    saved.value = connect ? "已保存，正在连接" : "已保存，下次连接生效";
    if (connect) props.actions.navigate?.("/");
  } catch (e) {
    error.value = String(e.message || e);
  } finally {
    pending.value = false;
  }
}
async function selectCertificate() {
  const path = await props.actions.selectCertificate?.();
  if (path) draft.certificatePath = path;
}
</script>
<template>
  <section class="settings-page">
    <form novalidate @submit.prevent="submit(true)">
      <div class="settings-panel">
        <div class="basic-fields">
          <div class="server-fields">
            <div class="field">
              <label for="server">服务器地址</label
              ><input
                id="server"
                v-model="draft.server"
                autocomplete="off"
                placeholder="edge.example.com"
                spellcheck="false"
                :aria-invalid="!!errors.server"
                :aria-describedby="errors.server ? 'server-error' : undefined"
              />
              <p v-if="errors.server" id="server-error" class="field-error">
                {{ errors.server }}
              </p>
            </div>
            <div class="field">
              <label for="port">端口</label
              ><input
                id="port"
                v-model.number="draft.port"
                type="number"
                min="1"
                max="65535"
                inputmode="numeric"
                :aria-invalid="!!errors.port"
              />
              <p v-if="errors.port" class="field-error">{{ errors.port }}</p>
            </div>
          </div>
          <div class="field license-field">
            <label for="license">License</label>
            <div class="input-with-icon">
              <input
                id="license"
                v-model="license"
                :type="showLicense ? 'text' : 'password'"
                autocomplete="off"
                :placeholder="
                  model.hasLicense ? '已保存 · 留空不修改' : '输入 License'
                "
                :aria-invalid="!!errors.license"
              /><button
                type="button"
                class="icon-button"
                :aria-label="showLicense ? '隐藏 License' : '显示 License'"
                :aria-pressed="showLicense"
                @click="showLicense = !showLicense"
              >
                <Icon name="eye" :size="21" />
              </button>
            </div>
            <p v-if="errors.license" class="field-error">
              {{ errors.license }}
            </p>
          </div>
        </div>
        <div class="transport-fields">
          <div class="ssl-field">
            <Icon name="shield" :size="21" />
            <span class="field-label">SSL 加密</span>
            <button
              type="button"
              role="switch"
              :aria-checked="draft.ssl"
              aria-label="启用 SSL"
              :class="['switch', { enabled: draft.ssl }]"
              @click="draft.ssl = !draft.ssl"
            >
              <span />
            </button>
          </div>
          <div v-if="draft.ssl" class="field certificate-field">
            <span id="certificate-label" class="field-label">信任证书</span>
            <div
              class="certificate-row"
              role="group"
              aria-labelledby="certificate-label"
            >
              <div class="certificate-display">
                <span :title="draft.certificatePath">{{
                  draft.certificatePath
                    ? draft.certificatePath.split(/[\\/]/).pop()
                    : "内置证书"
                }}</span
                ><button
                  v-if="draft.certificatePath"
                  class="text-link"
                  type="button"
                  @click="
                    draft.certificatePath = '';
                    password = '';
                  "
                >
                  使用内置证书</button
                ><Icon v-else name="down" :size="19" />
              </div>
              <button
                type="button"
                class="button secondary"
                @click="selectCertificate"
              >
                选择文件
              </button>
            </div>
            <div v-if="jks" class="field nested-field">
              <label for="store-password">证书库密码</label
              ><input
                id="store-password"
                v-model="password"
                type="password"
                autocomplete="off"
                placeholder="输入 JKS 证书库密码"
              />
            </div>
          </div>
        </div>
        <div class="advanced-section">
          <button
            type="button"
            class="disclosure"
            :aria-expanded="advanced"
            aria-controls="advanced-fields"
            @click="advanced = !advanced"
          >
            <Icon name="settings" :size="19" /><span>高级设置</span>
            <Icon
              name="chevron"
              :class="['disclosure-chevron', { expanded: advanced }]"
              :size="17"
            />
          </button>
          <div v-if="advanced" id="advanced-fields" class="advanced-fields">
            <div class="field">
              <label for="client-id">客户端 ID</label
              ><input
                id="client-id"
                v-model="draft.clientId"
                placeholder="首次保存时自动生成"
              />
            </div>
            <div class="server-fields">
              <div class="field">
                <label for="reconnect">重连间隔（秒）</label
                ><input
                  id="reconnect"
                  v-model.number="draft.reconnectSeconds"
                  type="number"
                  min="1"
                />
                <p v-if="errors.reconnectSeconds" class="field-error">
                  {{ errors.reconnectSeconds }}
                </p>
              </div>
              <div class="field">
                <label for="heartbeat">心跳间隔（秒）</label
                ><input
                  id="heartbeat"
                  v-model.number="draft.heartbeatSeconds"
                  type="number"
                  min="0"
                />
              </div>
            </div>
            <div class="server-fields equal">
              <div class="field">
                <label for="idle-time">读取超时（秒）</label
                ><input
                  id="idle-time"
                  v-model.number="draft.readIdleSeconds"
                  type="number"
                  min="0"
                />
              </div>
              <div class="field">
                <label for="udp-range">UDP 端口范围</label
                ><input id="udp-range" v-model="draft.udpPortRange" />
                <p v-if="errors.udpPortRange" class="field-error">
                  {{ errors.udpPortRange }}
                </p>
              </div>
            </div>
            <label class="checkbox-label"
              ><input v-model="draft.unlimited" type="checkbox" /> License
              验证失败后仍持续重试</label
            >
          </div>
        </div>
      </div>
      <p v-if="error" role="alert" class="form-error">
        <Icon name="alert" :size="18" />{{ error }}
      </p>
      <p v-if="saved" role="status" class="save-notice">{{ saved }}</p>
      <div class="form-actions">
        <span v-if="dirty" class="dirty-indicator"
          ><span class="status-dot" />未保存</span
        >
        <button
          type="button"
          class="button secondary"
          :disabled="pending"
          @click="submit(false)"
        >
          {{ active ? "仅保存，下次生效" : "仅保存" }}</button
        ><button type="submit" class="button primary" :disabled="pending">
          {{ pending ? "正在保存…" : active ? "保存并重连" : "保存并连接" }}
        </button>
      </div>
    </form>
  </section>
</template>
