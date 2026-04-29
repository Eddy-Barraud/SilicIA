# Privacy Policy (SilicIA)

**Effective date:** 29 April 2026

SilicIA is a privacy-focused macOS app that helps you search the web via DuckDuckGo and Wikipedia, optionally fetch and extract web page content for context, analyze PDF documents you provide, and generate concise summaries using Apple’s on-device NaturalLanguage framework.

## Summary

- SilicIA does **not** include analytics/telemetry or tracking (as described in the project README).
- Your searches require network access to DuckDuckGo.
- If you ask SilicIA to use a URL as context, SilicIA will fetch that web page.
- If you attach PDFs for context, SilicIA processes them locally using PDFKit.
- Conversation history is stored locally on your device using SwiftData.

## Information SilicIA Processes

Depending on how you use the app, SilicIA may process:

- **Search queries** you type.
- **Web URLs** you provide (for context-aware chat).
- **Web page content** fetched from those URLs (for summarization / context).
- **PDF files and extracted text** from PDFs you attach.
- **Conversation history** (messages, timestamps, and related metadata) stored locally.

## Network Requests

SilicIA makes network requests when features require it:

- **DuckDuckGo search**: your query is sent to DuckDuckGo to retrieve results.
- **Web content fetching**: if you provide a URL (or if the app fetches result pages for context), SilicIA requests content from the corresponding websites.

SilicIA’s on-device summarization is designed to run locally (NaturalLanguage) rather than sending text to a third-party LLM service.

## Local Storage

SilicIA stores chat/conversation history locally using SwiftData.

If you want to remove local data, you can delete conversations in the app (if available) and/or remove the app and its data from macOS.

## Data Sharing

SilicIA does not sell your data.

SilicIA may share data only in the limited sense that network requests necessarily transmit:

- your **search query** to DuckDuckGo, and
- requested **URLs/content** to the websites you choose to fetch.

## Security

SilicIA is a sandboxed macOS application (see the app entitlements in this repository). Standard macOS protections apply.

## Changes to This Policy

This policy may be updated as the app evolves. The latest version will be available in this repository.

## Contact

For questions about privacy, please open an issue on GitHub:

- https://github.com/Eddy-Barraud/SilicIA/issues
