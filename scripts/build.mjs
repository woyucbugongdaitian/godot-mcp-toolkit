import { cp, mkdir, rm } from "node:fs/promises";
import { dirname, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const root = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const buildDirectory = resolve(root, "build");

await rm(buildDirectory, { recursive: true, force: true });
await mkdir(resolve(buildDirectory, "godot"), { recursive: true });
await cp(resolve(root, "server", "index.mjs"), resolve(buildDirectory, "index.mjs"));
await cp(resolve(root, "godot", "mcp_operations.gd"), resolve(buildDirectory, "godot", "mcp_operations.gd"));

console.log(`Built Godot MCP Toolkit to ${buildDirectory}`);