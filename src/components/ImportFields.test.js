import { describe, it, expect } from "vitest";
import { mount } from "@vue/test-utils";
import ImportFields from "./ImportFields.vue";

const preview = (importedFields, canApply = true) => ({
  canApply, importedFields, hasLicense: true,
  config: { server: "saved.example.com", port: 9443, ssl: false, readIdleSeconds: 75,
    license: "must-not-render-license", storePassword: "must-not-render-password" },
});
describe("import field provenance", () => {
  it("shows every imported protocol setting with its actual value", () => {
    const fields = ["water-mark", "all-idle-time-seconds", "max-frame-length", "length-field-offset", "length-field-length", "length-adjustment", "initial-bytes-to-strip"];
    const wrapper = mount(ImportFields, { props: { preview: {
      ...preview(fields.map((key) => `neutrino.proxy.protocol.${key}`)),
      config: { waterMark: "32KB/1MB", allIdleSeconds: 17, maxFrameLength: 4194304,
        lengthFieldOffset: 2, lengthFieldLength: 4, lengthAdjustment: -2, initialBytesToStrip: 2 },
    } } });
    expect(wrapper.findAll("dl > div")).toHaveLength(7);
    expect(wrapper.text()).toContain("32KB/1MB");
    expect(wrapper.text()).toContain("17 秒");
    expect(wrapper.text()).toContain("4194304");
    expect(wrapper.text()).toContain("-2");
    wrapper.unmount();
  });
  it("does not present preserved server or license values as file contents", () => {
    const wrapper = mount(ImportFields, { props: { preview: preview(["neutrino.proxy.protocol.read-idle-time"]) } });
    expect(wrapper.text()).toContain("75 秒");
    expect(wrapper.text()).not.toContain("saved.example.com");
    expect(wrapper.text()).not.toContain("License");
    wrapper.unmount();
  });
  it("renders no candidate values when nothing was imported", () => {
    const wrapper = mount(ImportFields, { props: { preview: preview([], false) } });
    expect(wrapper.find("dl").exists()).toBe(false);
    expect(wrapper.text()).toBe("");
    wrapper.unmount();
  });
  it("shows recognized fields while always hiding credential values", () => {
    const wrapper = mount(ImportFields, { props: { preview: preview([
      "neutrino.proxy.tunnel.server-ip", "neutrino.proxy.tunnel.ssl-enable",
      "neutrino.proxy.tunnel.license-key", "neutrino.proxy.tunnel.key-store-password",
    ]) } });
    expect(wrapper.text()).toContain("saved.example.com");
    expect(wrapper.text()).toContain("未启用");
    expect(wrapper.text()).toContain("License");
    expect(wrapper.text()).toContain("证书密码");
    expect(wrapper.text()).not.toContain("must-not-render");
    wrapper.unmount();
  });
});
