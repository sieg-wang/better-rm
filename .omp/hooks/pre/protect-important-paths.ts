import type { HookAPI } from "@oh-my-pi/pi-coding-agent/extensibility/hooks";
// @ts-ignore
import { evaluate } from "../../../hooks/protect-important-paths";

export default function hook(pi: HookAPI): void {
  pi.on("tool_call", async (event, ctx) => {
    if (event.toolName === "bash") {
      const command = event.input.command as string;
      const cwd = (ctx as any)?.cwd || process.cwd();

      const payload = {
        tool_input: { command },
        cwd
      };

      const result = evaluate(payload);
      if (result && result.hookSpecificOutput?.permissionDecision === "deny") {
        return {
          block: true,
          reason: result.hookSpecificOutput.permissionDecisionReason
        };
      }
    }
  });
}
