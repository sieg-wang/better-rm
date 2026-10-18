import type { Plugin } from "@opencode-ai/plugin";
import { createRequire } from "node:module";
import path from "node:path";

// The guard runtime is loaded here, inside try/catch, not by a static import:
// when a static import fails (runtime missing, empty or broken), OpenCode drops
// the plugin and bash runs unguarded. A runtime that cannot be loaded, or that
// has no evaluate(), leaves a handler that refuses every bash call.
function loadGuard() {
  try {
    const load = typeof require === "function" ? require : createRequire(import.meta.url);
    const runtime = load("../../hooks/protect-important-paths.js");
    if (runtime && typeof runtime.evaluate === "function") {
      return { evaluate: runtime.evaluate, failure: "" };
    }
    return { evaluate: null, failure: "it has no evaluate()" };
  } catch (error) {
    return { evaluate: null, failure: String(error) };
  }
}

export const ProtectImportantPathsPlugin: Plugin = async (ctx) => {
  const guard = loadGuard();
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool === "bash") {
        if (!guard.evaluate) {
          throw new Error(`拒絕刪除：better-rm 的 guard runtime（hooks/protect-important-paths.js）無法使用（${guard.failure}），在它能載入之前每個 bash 呼叫都會被拒絕；請重跑 install-hooks.sh -a opencode 後重新啟動 OpenCode。 / Refused to remove: cannot determine what this bash call deletes, because the better-rm guard runtime hooks/protect-important-paths.js is unusable (${guard.failure}); every bash call is refused until it loads. Re-run install-hooks.sh -a opencode, then restart OpenCode.`);
        }
        const command = output.args.command;
        // OpenCode runs a bash call that carries a workdir in
        // path.resolve(directory, workdir), so that is the cwd to judge with.
        const base = (ctx as any)?.directory || process.cwd();
        const workdir = output.args.workdir;
        if (workdir !== undefined && workdir !== null && typeof workdir !== "string") {
          throw new Error("拒絕刪除：無法判定這次 bash 呼叫的工作目錄（workdir 不是字串）。 / Refused to remove: cannot determine the working directory of this bash call (workdir is not a string).");
        }
        const cwd = workdir ? path.resolve(base, workdir) : base;

        const payload = {
          tool_input: { command },
          cwd
        };

        let result;
        try {
          result = guard.evaluate(payload);
        } catch (error) {
          throw new Error(`拒絕刪除：better-rm 的 guard 判定這次 bash 呼叫時出錯（${String(error)}）。 / Refused to remove: cannot determine what this bash call deletes, because the better-rm guard failed on it (${String(error)}).`);
        }
        if (result && result.hookSpecificOutput?.permissionDecision === "deny") {
          throw new Error(result.hookSpecificOutput.permissionDecisionReason);
        }
      }
    },
  };
};

export default ProtectImportantPathsPlugin;
