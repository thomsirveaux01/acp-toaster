<p align="center">
    <img src="icon.png" width="160" alt="ACP Toaster app icon">
</p>

<h1 align="center">ACP Toaster</h1>

<p align="center">
    A macOS app that helps connect third-party coding agents to Xcode 27 using OpenCode and Apple's Agent Client Protocol (ACP).
</p>
<p align="center">
    Compatible with Apple Silicon Macs running Xcode 27 on macOS 26 Tahoe or macOS 27 Golden Gate. 
</p>

## How it works

- **Add a server**: Point the app at any OpenAI, Ollama, or LM Studio-compatible endpoint using IP/hostname and port. Works for local models via loopback, or remote models via LAN/Tailscale IP address or hostname.
- **Browse models**: Each model shows its specs (params, quant, format, RAM,
  max context) and capabilities (vision, tool use, reasoning).
- **Toast**: Writes an OpenCode ACP wrapper for the model and merges the
  provider entry into your OpenCode config. Paste the wrapper into Xcode 27's Intelligence settings under "Agents" to use the agent in Xcode. 
- **Leverage Xcode's capabilities**: Models can use Xcode's built-in specialist skills for SwiftUI and more.

ACPToaster is not built by the OpenCode team and is not affiliated with the OpenCode project in any way. 
