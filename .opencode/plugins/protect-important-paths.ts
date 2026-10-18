import type { Plugin } from "@opencode-ai/plugin";
import path from "node:path";
// @ts-ignore
import { evaluate } from "../../hooks/protect-important-paths";

export const ProtectImportantPathsPlugin: Plugin = async (ctx) => {
  return {
    "tool.execute.before": async (input, output) => {
      if (input.tool === "bash") {
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

        const result = evaluate(payload);
        if (result && result.hookSpecificOutput?.permissionDecision === "deny") {
          throw new Error(result.hookSpecificOutput.permissionDecisionReason);
        }
      }
    },
  };
};

export default ProtectImportantPathsPlugin;
