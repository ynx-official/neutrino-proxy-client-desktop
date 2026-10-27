<script setup>
defineProps({ name: String, size: { default: 20 } });
const paths = {
  window: "M3 4h18v16H3z M3 9h18",
  exit: "M14 4H4v16h10 M10 12h12 m-4-4 4 4-4 4",
  link: "M10 13a5 5 0 0 0 7 .1l3-3a5 5 0 0 0-7-7l-2 2 M14 11a5 5 0 0 0-7-.1l-3 3a5 5 0 0 0 7 7l2-2",
  logs: "M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z M14 2v6h6 M8 12h8 M8 16h8",
  settings:
    "m9.5 3 .5-1h4l.5 1 .6 2 1.8 1 2-.4 1 .3 2 3.5-.5 1-1.5 1.5v2l1.5 1.5.5 1-2 3.5-1 .3-2-.4-1.8 1-.6 2-.5 1h-4l-.5-1-.6-2-1.8-1-2 .4-1-.3-2-3.5.5-1L4 13v-2L2.5 9.5l-.5-1 2-3.5 1-.3 2 .4 1.8-1z M15.5 12a3.5 3.5 0 1 1-7 0 3.5 3.5 0 0 1 7 0",
  check: "m6 12 4 4 8-8",
  circleCheck: "M22 12a10 10 0 1 1-3-7 M8 12l3 3L22 4",
  info: "M12 8h.01 M12 11v6 M22 12a10 10 0 1 1-20 0 10 10 0 0 1 20 0",
  eye: "M2 12s3.5-7 10-7 10 7 10 7-3.5 7-10 7S2 12 2 12 M15 12a3 3 0 1 1-6 0 3 3 0 0 1 6 0",
  chevron: "m9 5 7 7-7 7",
  down: "m6 9 6 6 6-6",
  alert: "m12 3 10 18H2L12 3 M12 9v5 M12 17h.01",
  refresh: "M20 7v5h-5 M4 17v-5h5 M6 6a8 8 0 0 1 14 6 M18 18a8 8 0 0 1-14-6",
  power: "M12 2v10 M6 5a9 9 0 1 0 12 0",
  upload: "M12 16V3 m-5 5 5-5 5 5 M4 14v6h16v-6",
  download: "M12 3v13 m-5-5 5 5 5-5 M4 16v5h16v-5",
  server:
    "M4 3h16v7H4z M4 14h16v7H4z M8 6.5h.01 M8 17.5h.01 M12 6.5h5 M12 17.5h5",
  shield: "m12 2 8 3v6c0 5-4 8-8 11-4-3-8-6-8-11V5z m-4 10 3 3 5-6",
  key: "M15 14a6 6 0 1 0-5-5 M10 9 2 17v5h5v-3h3v-3l2-2 M17 7h.01",
  search: "M21 21l-5-5 M18 10a8 8 0 1 1-16 0 8 8 0 0 1 16 0",
  pause: "M8 5v14 M16 5v14",
  play: "m7 4 14 8-14 8z",
  arrow: "M4 12h16 m-6-6 6 6-6 6",
};
</script>
<template>
  <svg
    :width="size"
    :height="size"
    viewBox="0 0 24 24"
    fill="none"
    stroke="currentColor"
    stroke-width="1.65"
    stroke-linecap="round"
    stroke-linejoin="round"
    aria-hidden="true"
  >
    <path :d="paths[name] || paths.info" />
  </svg>
</template>
