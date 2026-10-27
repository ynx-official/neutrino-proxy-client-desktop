<script setup>
import { computed, ref, watch } from "vue";
import Icon from "../components/AppIcon.vue";
const props = defineProps({ model: Object, actions: Object });
const query = ref(""),
  level = ref("all"),
  paused = ref(false),
  frozen = ref([]);
watch(paused, (value) => {
  if (value) frozen.value = [...(props.model.logs || [])];
});
const filtered = computed(() =>
  (paused.value ? frozen.value : props.model.logs || [])
    .filter(
      (entry) =>
        (level.value === "all" || entry.level === level.value) &&
        `${entry.source} ${entry.message}`
          .toLowerCase()
          .includes(query.value.toLowerCase()),
    )
    .slice(-200),
);
const time = (value) =>
  new Date(value).toLocaleString("zh-CN", { hour12: false });
</script>
<template>
  <section class="logs-page">
    <header class="page-header">
      <h1>日志</h1>
      <button class="button secondary" @click="actions.exportLogs?.()">
        <Icon name="download" :size="17" />导出日志
      </button>
    </header>
    <div class="logs-panel">
      <div class="log-toolbar">
        <div class="search-field">
          <Icon name="search" :size="18" />
          <input v-model="query" aria-label="搜索日志" placeholder="搜索日志" />
        </div>
        <select v-model="level" aria-label="日志级别">
          <option value="all">全部级别</option>
          <option value="info">信息</option>
          <option value="warn">警告</option>
          <option value="error">错误</option></select
        ><button
          class="button secondary"
          :aria-pressed="paused"
          @click="paused = !paused"
        >
          <Icon :name="paused ? 'play' : 'pause'" :size="16" />{{
            paused ? "恢复更新" : "暂停更新"
          }}
        </button>
      </div>
      <p v-if="paused" class="muted log-note">视图已暂停 · 后台继续记录</p>
      <div v-if="!filtered.length" class="empty-log">
        <Icon name="logs" :size="32" />
        <h3>
          {{ query || level !== "all" ? "当前筛选没有日志" : "暂时没有日志" }}
        </h3>
        <button
          v-if="query || level !== 'all'"
          class="text-link"
          @click="
            query = '';
            level = 'all';
          "
        >
          清除筛选
        </button>
      </div>
      <ol v-else class="log-entries">
        <li v-for="entry in filtered" :key="entry.id">
          <time>{{ time(entry.time) }}</time
          ><span :class="['log-level', entry.level]">{{
            { info: "信息", warn: "警告", error: "错误" }[entry.level] ||
            entry.level
          }}</span
          ><span class="log-source">{{ entry.source }}</span
          ><span class="log-message">{{ entry.message }}</span>
        </li>
      </ol>
      <div class="log-footer">
        <span>{{ filtered.length }} 条记录</span><span>最近 200 条</span>
      </div>
    </div>
  </section>
</template>
