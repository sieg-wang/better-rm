import type { HookAPI } from "@oh-my-pi/pi-coding-agent/extensibility/hooks";
import { createRequire } from "node:module";

// The guard runtime is loaded here, inside try/catch, not by a static import:
// a static import that fails (runtime missing, empty or broken) leaves no hook
// at all. A runtime that cannot be loaded, or that has no evaluate(), leaves a
// handler that blocks every bash call.
function loadGuard() {
  try {
    const load = typeof require === "function" ? require : createRequire(import.meta.url);
    const runtime = load("../../../hooks/protect-important-paths.js");
    if (runtime && typeof runtime.evaluate === "function") {
      return { evaluate: runtime.evaluate, failure: "" };
    }
    return { evaluate: null, failure: "it has no evaluate()" };
  } catch (error) {
    return { evaluate: null, failure: String(error) };
  }
}

export default function hook(pi: HookAPI): void {
  const guard = loadGuard();
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "bash") {
      if (!guard.evaluate) {
        return {
          block: true,
          reason: `拒絕刪除：better-rm 的 guard runtime（hooks/protect-important-paths.js）無法使用（${guard.failure}），在它能載入之前每個 bash 呼叫都會被擋下。 / Refused to remove: cannot determine what this bash call deletes, because the better-rm guard runtime hooks/protect-important-paths.js is unusable (${guard.failure}); every bash call is blocked until it loads.`
        };
      }
      const command = event.input.command as string;
      const cwd = (ctx as any)?.cwd || process.cwd();

      const payload = {
        tool_input: { command },
        cwd
      };

      let result;
      try {
        result = guard.evaluate(payload);
      } catch (error) {
        return {
          block: true,
          reason: `拒絕刪除：better-rm 的 guard 判定這次 bash 呼叫時出錯（${String(error)}）。 / Refused to remove: cannot determine what this bash call deletes, because the better-rm guard failed on it (${String(error)}).`
        };
      }
      if (result && result.hookSpecificOutput?.permissionDecision === "deny") {
        return {
          block: true,
          reason: result.hookSpecificOutput.permissionDecisionReason
        };
      }
    }
  });
}
