<script setup>
import { onMounted, reactive, ref } from "vue";
import Icon from "../components/AppIcon.vue";
const props = defineProps({ actions: Object });
const settings = reactive({ autoStart: false, autoConnect: false });
const ready = ref(false), pending = ref(false), error = ref(""), saved = ref(false);
async function load() {
  pending.value = true;
  error.value = "";
  try {
    Object.assign(settings, await props.actions.getAppSettings());
    ready.value = true;
  } catch (e) {
    ready.value = false;
    error.value = String(e.message || e);
  } finally { pending.value = false; }
}
async function toggle(key) {
  if (!ready.value || pending.value) return;
  pending.value = true;
  error.value = "";
  saved.value = false;
  try {
    Object.assign(settings, await props.actions.saveAppSettings({ [key]: !settings[key] }));
    saved.value = true;
  } catch (e) {
    error.value = String(e.message || e);
    // Registration may succeed before an OS read fails. Re-read before showing a state.
    try { Object.assign(settings, await props.actions.getAppSettings()); }
    catch { ready.value = false; }
  } finally { pending.value = false; }
}
onMounted(load);
</script>
<template>
  <section class="application-settings" aria-labelledby="startup-title" :aria-busy="pending">
    <h2 id="startup-title">启动行为</h2>
    <div class="preference-row">
      <div>
        <h3>开机自启</h3>
        <p id="auto-start-description">登录系统后自动启动 Neutrino。</p>
      </div>
      <button type="button" class="switch" role="switch" aria-label="开机自启"
        aria-describedby="auto-start-description" :aria-checked="settings.autoStart"
        :class="{ enabled: settings.autoStart }" :disabled="!ready || pending" @click="toggle('autoStart')"><span /></button>
    </div>
    <div class="preference-row">
      <div>
        <h3>启动后自动连接</h3>
        <p id="auto-connect-description">已保存完整连接配置时，自动尝试连接一次。</p>
      </div>
      <button type="button" class="switch" role="switch" aria-label="启动后自动连接"
        aria-describedby="auto-connect-description" :aria-checked="settings.autoConnect"
        :class="{ enabled: settings.autoConnect }" :disabled="!ready || pending" @click="toggle('autoConnect')"><span /></button>
    </div>
    <p class="preference-hint"><Icon name="info" :size="16" /><span>配置不完整时不会自动连接，可前往「<RouterLink to="/settings" aria-label="前往连接配置">连接配置</RouterLink>」补充。</span></p>
    <div v-if="error" class="preference-error" role="alert">
      <span>{{ error }}</span><button v-if="!ready" class="text-link" :disabled="pending" @click="load">重新读取</button>
    </div>
    <p class="preference-save-status" role="status">{{ pending ? (ready ? '正在保存…' : '正在读取设置…') : saved ? '已自动保存' : '更改后自动保存' }}</p>
  </section>
</template>
