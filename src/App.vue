<script setup>
import { reactive, ref, onMounted, onUnmounted } from "vue";
import { useRouter } from "vue-router";
import { getCurrentWindow } from "@tauri-apps/api/window";
import Icon from "./components/AppIcon.vue";
import BrandMark from "./components/BrandMark.vue";
import ImportFields from "./components/ImportFields.vue";
import { initialModel } from "./services/state";
import { call, subscribe, subscribeNavigation, inDesktop, confirmAction } from "./services/desktop";
const model = reactive(initialModel()),
  error = ref(""),
  busy = ref(false),
  dirty = ref(false),
  importPreview = ref(null),
  importRevision = ref(0),
  ready = ref(false);
const router = useRouter();
let unlisten, unclose, unnavigate;
async function navigateFromTray() {
  const path = await call("take_navigation");
  if (path) await router.push(path);
}
const apply = (snapshot) => {
  if (snapshot && snapshot.revision >= model.revision)
    Object.assign(model, snapshot);
};
async function run(operation) {
  error.value = "";
  busy.value = true;
  try {
    return await operation();
  } catch (e) {
    error.value = String(e.message || e);
    throw e;
  } finally {
    busy.value = false;
  }
}
const safe = (operation) => run(operation).catch(() => {});
const actions = {
  navigate: (path) => router.push(path),
  setDirty: (value) => (dirty.value = value),
  connect: () => safe(() => call("connect")),
  disconnect: () => safe(() => call("disconnect")),
  getAppSettings: () => call("get_app_settings"),
  saveAppSettings: (request) => call("save_app_settings", { request }),
  save: (request) =>
    run(async () => {
      apply(await call("save_config", { request }));
    }),
  selectCertificate: () => safe(() => call("select_certificate")),
  importConfig: () =>
    safe(async () => {
      if (
        dirty.value &&
        !(await confirmAction("当前有未保存的修改，继续导入将替换这些修改。"))
      )
        return;
      importPreview.value = await call("import_config");
    }),
  exportLogs: () => safe(() => call("export_logs")),
};
async function applyImport() {
  await safe(async () => {
    apply(await call("apply_import", { id: importPreview.value.id }));
    // An explicitly confirmed import replaces the form draft, including hidden protocol fields.
    importRevision.value += 1;
    importPreview.value = null;
    dirty.value = false;
    await router.push("/settings");
  });
}
router.beforeEach(async (to, from) => {
  if (to.path !== from.path && dirty.value) {
    if (!(await confirmAction("当前配置尚未保存，是否放弃修改并离开？")))
      return false;
    dirty.value = false;
  }
});
onMounted(async () => {
  try {
    unlisten = await subscribe(apply);
    unnavigate = await subscribeNavigation(() => safe(navigateFromTray));
    apply(await call("get_snapshot"));
    ready.value = true;
    await navigateFromTray();
    if (inDesktop())
      unclose = await getCurrentWindow().onCloseRequested(async (event) => {
        event.preventDefault();
        if (
          dirty.value &&
          !(await confirmAction("当前配置尚未保存，是否放弃修改并关闭窗口？"))
        )
          return;
        await call("close_to_tray");
      });
  } catch (e) {
    error.value = String(e.message || e);
  }
});
onUnmounted(() => {
  unlisten?.();
  unclose?.();
  unnavigate?.();
});
</script>
<template>
  <div class="desktop-layout" :aria-busy="busy">
    <header class="app-header">
      <div class="wordmark">
        <BrandMark />
        <span>Neutrino</span>
      </div>
      <nav aria-label="主导航">
        <RouterLink to="/" exact-active-class="selected"
          ><span>连接</span></RouterLink
        ><RouterLink to="/logs" active-class="selected"
          ><span>日志</span></RouterLink
        ><RouterLink to="/settings" active-class="selected"
          ><span>设置</span></RouterLink
        >
      </nav>
    </header>
    <main class="main-content">
      <div v-if="error" class="global-error" role="alert">
        <Icon name="alert" :size="18" /><span>{{ error }}</span
        ><button class="text-link" @click="error = ''">关闭</button>
      </div>
      <RouterView v-slot="{ Component }"
        ><component
          :is="Component"
          :model="model"
          :actions="actions"
          :key="`${$route.path}:${importRevision}`"
      /></RouterView>
    </main>
    <footer class="app-footer">
      <span class="version">v{{ model.version }}</span>
    </footer>
    <div
      v-if="importPreview"
      class="modal-backdrop"
      @keydown.esc="importPreview = null"
    >
      <section
        class="modal"
        role="dialog"
        aria-modal="true"
        aria-labelledby="import-title"
      >
        <h2 id="import-title">确认导入配置</h2>
        <ImportFields :preview="importPreview" />
        <ul class="import-notes">
          <li v-for="note in importPreview.notes" :key="note">{{ note }}</li>
        </ul>
        <div class="form-actions">
          <button class="button secondary" @click="importPreview = null">
            取消</button
          ><button
            class="button primary"
            :disabled="!importPreview.canApply || busy"
            @click="applyImport"
          >
            导入并保存
          </button>
        </div>
      </section>
    </div>
  </div>
</template>
