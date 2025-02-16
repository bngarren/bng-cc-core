
I am building a networking module in Lua for CC:Tweaked (Minecraft mod) that is built on ECNet2 (https://github.com/migeyel/ecnet). The goal is to provide an easy-to-use, efficient, and modular framework for communication between servers, clients, and peers in a Minecraft ComputerCraft environment.

This module should abstract away low-level networking details, providing a clean, event-driven API for sending and receiving messages. It will support both connection-oriented and packet-based communication, enabling flexible networking setups.

## Key Design Goals
- Abstracted Communication Layer → Simplify the setup of clients, servers, and peer-to-peer messaging.
- Protocol & Schema Support → Enforce structured communication with type-safe schemas and validation.
- Compression → Use LZW compression automatically for large messages.
- Asynchronous Event Handling → Process multiple requests in parallel using coroutines.
- Connection-Oriented & Packet-Based → Support both persistent connections (like TCP) and fire-and-forget messaging (like UDP).
- Broadcasting & Subscriptions → Allow many-to-many messaging with channel-based filtering.
- Message Persistence & Retries → Implement retries for important messages and support logging.
- Modular & Swappable Transport → Design the transport layer to be configurable, with ECNet2 as the default.
- Tight ECNet2 Integration → The module will directly use ECNet2 but expose a higher-level API.

## Roadmap

### 1. Core Messaging System (Basic Client & Server)
Objectives:
- Implement a basic communication framework with servers & clients.
- Ensure event-driven architecture using os.queueEvent.
- Make sure clients send requests and receive responses.

### 2. Message Validation & Schema System
Objectives:
- Add schema validation to ensure structured communication.

### 3. Compression (LZW)
Objectives:
- Implement automatic compression for large messages.

### 4. Broadcasting & Subscriptions
Objectives:
- Implement broadcast messages and subscription handling.

### 5. Retries & Error Handling
Objectives:
- Ensure messages are reliably delivered with retries & error handling.