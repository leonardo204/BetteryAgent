import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";

const API_BASE = process.env.BATTERY_AGENT_API || "http://localhost:18080";

async function apiCall(endpoint, body = {}) {
  const res = await fetch(`${API_BASE}/api/${endpoint}`, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(body),
  });
  return await res.json();
}

const server = new McpServer({
  name: "battery-agent",
  version: "1.0.0",
});

// Tool 1: Get battery status
server.tool(
  "get_battery_status",
  "현재 배터리 상태를 가져옵니다 (충전량, 충전 상태, 건강도, 어댑터 전력 등)",
  {},
  async () => {
    const data = await apiCall("status");
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  }
);

// Tool 2: Set charge limit
server.tool(
  "set_charge_limit",
  "배터리 충전 제한을 설정합니다 (20-100%)",
  { limit: z.number().min(20).max(100).describe("충전 제한 퍼센트 (20-100)") },
  async ({ limit }) => {
    const data = await apiCall("settings", { action: "set", chargeLimit: limit });
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  }
);

// Tool 3: Toggle management
server.tool(
  "toggle_management",
  "배터리 관리(활성화/비활성화)를 제어합니다",
  { enabled: z.boolean().describe("true=활성화, false=비활성화") },
  async ({ enabled }) => {
    const data = await apiCall("control", {
      command: enabled ? "enable-managing" : "disable-managing",
    });
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  }
);

// Tool 4: Get charge history
server.tool(
  "get_charge_history",
  "충전 이력 데이터를 가져옵니다",
  { hours: z.number().min(1).max(168).default(24).describe("조회할 시간 범위 (기본 24시간)") },
  async ({ hours }) => {
    const data = await apiCall("history", { hours });
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  }
);

// Tool 5: Get battery health analysis
server.tool(
  "analyze_battery_health",
  "배터리 건강 상태를 분석합니다 (건강도, 사이클, 용량 손실, 예상 잔여 수명)",
  {},
  async () => {
    const [health, status] = await Promise.all([
      apiCall("health"),
      apiCall("status"),
    ]);
    const analysis = {
      health,
      currentStatus: status,
      summary: `건강도 ${health.healthPercentage}%, 사이클 ${health.cycleCount}회, 용량 손실 ${health.capacityLossMah}mAh, 예상 잔여 사이클 ${health.estimatedCyclesRemaining}회`,
    };
    return { content: [{ type: "text", text: JSON.stringify(analysis, null, 2) }] };
  }
);

// Tool 6: Apply settings (flexible)
server.tool(
  "apply_settings",
  "배터리 관리 설정을 변경합니다 (충전 제한, 방전 하한, 재충전 모드 등)",
  {
    chargeLimit: z.number().min(20).max(100).optional().describe("충전 제한 (20-100%)"),
    dischargeFloor: z.number().min(5).max(50).optional().describe("방전 하한 (5-50%)"),
    rechargeMode: z.enum(["smart", "manual"]).optional().describe("재충전 모드"),
    isManaging: z.boolean().optional().describe("관리 활성화 여부"),
  },
  async (params) => {
    const body = { action: "set" };
    if (params.chargeLimit !== undefined) body.chargeLimit = params.chargeLimit;
    if (params.dischargeFloor !== undefined) body.dischargeFloor = params.dischargeFloor;
    if (params.rechargeMode !== undefined) body.rechargeMode = params.rechargeMode;
    if (params.isManaging !== undefined) body.isManaging = params.isManaging;
    const data = await apiCall("settings", body);
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  }
);

// Tool 7: Force discharge control
server.tool(
  "force_discharge",
  "강제 방전을 시작하거나 중지합니다",
  { enabled: z.boolean().describe("true=강제 방전 시작, false=강제 방전 중지") },
  async ({ enabled }) => {
    const data = await apiCall("control", {
      command: enabled ? "force-discharge" : "stop-discharge",
    });
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  }
);

// Tool 8: Get current settings
server.tool(
  "get_settings",
  "현재 배터리 관리 설정을 조회합니다 (충전 제한, 방전 하한, 재충전 모드 등)",
  {},
  async () => {
    const data = await apiCall("settings", { action: "get" });
    return { content: [{ type: "text", text: JSON.stringify(data, null, 2) }] };
  }
);

const transport = new StdioServerTransport();
await server.connect(transport);
