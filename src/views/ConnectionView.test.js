import { describe, it, expect, vi } from "vitest";
import { mount } from "@vue/test-utils";
import ConnectionView from "./ConnectionView.vue";

describe("connection status", () => {
  it("shows only the latest three events as new records arrive", async () => {
    const event = (id) => ({
      id,
      level: "info",
      time: "2026-10-15T02:24:09Z",
      message: `event-${id}`,
    });
    const logs = [1, 2, 3, 4, 5].map(event);
    const model = { state: "idle", config: { server: "" }, logs };
    const wrapper = mount(ConnectionView, { props: { model, actions: {} } });
    const messages = () =>
      wrapper.findAll(".event-list li > span").map((node) => node.text());
    expect(messages()).toEqual(["event-3", "event-4", "event-5"]);
    await wrapper.setProps({ model: { ...model, logs: [...logs, event(6)] } });
    expect(messages()).toEqual(["event-4", "event-5", "event-6"]);
    expect(logs).toHaveLength(5);
    wrapper.unmount();
  });
  it("does not pretend to be connected on first launch", () => {
    const wrapper = mount(ConnectionView, {
      props: {
        model: {
          state: "idle",
          config: { server: "" },
          logs: [],
          hasLicense: false,
        },
        actions: {},
      },
    });
    expect(wrapper.text()).toContain("尚未连接");
    expect(wrapper.text()).toContain("填写连接信息");
    expect(wrapper.text()).not.toContain("服务器认证通过");
  });
  it("provides a real disconnect action when authenticated", async () => {
    const disconnect = vi.fn();
    const wrapper = mount(ConnectionView, {
      props: {
        model: {
          state: "connected",
          config: { server: "edge.example.com", port: 9002, ssl: true },
          logs: [],
          licenseHint: "•••• 8F2A",
          connectedAt: new Date().toISOString(),
        },
        actions: { disconnect },
      },
    });
    await wrapper.get('[data-testid="disconnect"]').trigger("click");
    expect(disconnect).toHaveBeenCalledOnce();
    expect(wrapper.text()).toContain("已连接");
    expect(wrapper.text()).toContain("edge.example.com");
  });
  it("keeps both immediate retry and stop controls available during reconnect", async () => {
    const connect = vi.fn(),
      disconnect = vi.fn();
    const wrapper = mount(ConnectionView, {
      props: {
        model: {
          state: "reconnecting",
          config: { server: "edge.example.com", port: 9002 },
          detail: "连接中断",
          retryAt: new Date(Date.now() + 9000).toISOString(),
          logs: [],
        },
        actions: { connect, disconnect },
      },
    });
    expect(wrapper.text()).toMatch(/[89] 秒后重试/);
    expect(wrapper.get('[role="status"]').text()).toBe("连接中断");
    await wrapper.get(".hero-actions .primary").trigger("click");
    await wrapper.get('[data-testid="disconnect"]').trigger("click");
    expect(connect).toHaveBeenCalledOnce();
    expect(disconnect).toHaveBeenCalledOnce();
    wrapper.unmount();
  });
  it("shows the active endpoint while saved changes are waiting for reconnect", () => {
    const wrapper = mount(ConnectionView, {
      props: {
        model: {
          state: "connected",
          config: { server: "next.example.com", port: 9003 },
          activeConfig: { server: "active.example.com", port: 9002 },
          pendingConfig: true,
          logs: [],
        },
        actions: {},
      },
    });
    expect(wrapper.get(".hero-endpoint").text()).toContain(
      "active.example.com",
    );
    expect(wrapper.get(".hero-endpoint").text()).not.toContain(
      "next.example.com",
    );
    expect(wrapper.text()).toContain("新配置将在下次连接时生效");
    wrapper.unmount();
  });
});
