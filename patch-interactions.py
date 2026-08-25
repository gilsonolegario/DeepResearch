#!/usr/bin/env python3
"""Patch InteractionsClient to add markdown formatting instruction to input."""
import re

with open("Sources/DeepResearch/Core/InteractionsClient.swift", "r") as f:
    content = f.read()

# Patch create() - add formatting instruction to input
old_create = '''    func create(question: String, agent: AgentKind) async throws -> Interaction {
        let body: [String: Any] = [
            "input": question,
            "agent": Self.agentIdentifier(for: agent),
            // Sempre background: o fluxo do app é criar → acompanhar → cancelável.
            "background": true,
            "systemInstruction": [
                "parts": [[
                    "text": "Format your response in Markdown. Use ## headers for sections, - bullet lists for items, **bold** for emphasis, > blockquotes for citations, | tables | for tabular data, and `inline code` for technical terms. Always use Markdown structure, not plain prose."
                ]]
            ],
        ]'''

new_create = '''    func create(question: String, agent: AgentKind) async throws -> Interaction {
        let body: [String: Any] = [
            "input": question,
            "agent": Self.agentIdentifier(for: agent),
            // Sempre background: o fluxo do app é criar → acompanhar → cancelável.
            "background": true,
            "systemInstruction": [
                "parts": [[
                    "text": "Format your entire response in Markdown. Use ## headers for sections, - bullet lists for items, **bold** for emphasis, > blockquotes for citations, | tables | for tabular data, and `inline code` for technical terms. Never use plain prose — always use Markdown structure."
                ]]
            ],
        ]'''

content = content.replace(old_create, new_create)

# Patch createStream()
old_stream = '''    func createStream(question: String, agent: AgentKind) async throws -> AsyncStream<SSEEvent> {
        let body: [String: Any] = [
            "input": question,
            "agent": Self.agentIdentifier(for: agent),
            "stream": true,
            "systemInstruction": [
                "parts": [[
                    "text": "Format your response in Markdown. Use ## headers for sections, - bullet lists for items, **bold** for emphasis, > blockquotes for citations, | tables | for tabular data, and `inline code` for technical terms. Always use Markdown structure, not plain prose."
                ]]
            ],
        ]'''

new_stream = '''    func createStream(question: String, agent: AgentKind) async throws -> AsyncStream<SSEEvent> {
        let body: [String: Any] = [
            "input": question,
            "agent": Self.agentIdentifier(for: agent),
            "stream": true,
            "systemInstruction": [
                "parts": [[
                    "text": "Format your entire response in Markdown. Use ## headers for sections, - bullet lists for items, **bold** for emphasis, > blockquotes for citations, | tables | for tabular data, and `inline code` for technical terms. Never use plain prose — always use Markdown structure."
                ]]
            ],
        ]'''

content = content.replace(old_stream, new_stream)

with open("Sources/DeepResearch/Core/InteractionsClient.swift", "w") as f:
    f.write(content)

print("InteractionsClient patched.")
