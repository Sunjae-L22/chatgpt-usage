# SNS drafts — review before posting

These are drafts only. No post, reply, repost, or direct message has been sent. The copy reports three live connections verified on the author’s own Mac. It keeps other accounts/devices and beta installation limits separate from that result.

## X · English

My AI subscriptions multiplied lol.

So I built a Mac menu bar app for Codex, Claude and Gemini. Quota left, reset times, and a pace line.

All three work on my Mac now. Early beta; setup needs an unpacked Chrome extension.

https://github.com/Sunjae-L22/chatgpt-usage/tree/feat/multi-provider-usage

Suggested image: the English three-provider screenshot with the DEMO label visible. It contains sample data.

## X · Korean

쓰는 AI가 또 늘었다 ㅋㅋ

Codex 사용량만 보던 Mac 앱에 Claude랑 Gemini도 붙였다. 남은 한도랑 초기화 시간을 한눈에 보고, 시간에 비해 너무 빨리 쓰는지도 비교할 수 있다.

내 Mac에서는 세 개 다 연결 확인! 설치는 아직 손이 가는 베타다.

https://github.com/Sunjae-L22/chatgpt-usage/tree/feat/multi-provider-usage

Suggested image: img/ai-usage-demo-ko.png, keeping the DEMO label visible.

## Longer developer-community post · English

Title: I put my Codex, Claude and Gemini quotas in one Mac menu bar app

I made a small Codex usage tracker for my Mac a while ago. Then Gemini Argon came out, and now I’m using Codex, Claude and Gemini. Keeping three separate usage pages around felt like a good reason to revisit the app.

The part I wanted to keep was the pace line. The bar shows quota left; the line shows time left before the reset. If I have 30% of my weekly quota but only 20% of the week left, I’ve got a bit of room. It’s a reference for even usage, not a prediction or an official daily cap.

I’ve built the three-service view and the connection code. Codex uses the local app-server. Claude has an experimental CLI path, plus a browser connection. Gemini uses the Gemini app’s usage page through a Chrome extension. These are separate from API spending and Antigravity quotas.

The extension keeps the service login in the browser and sends only quota fields to the app on the same Mac. There’s no cloud relay. All three connections now work on my Mac. I compared Claude and Gemini’s quota and reset displays with their official usage pages. It’s still an early beta: other accounts and Macs need testing, setup involves loading an unpacked extension, and the Mac app isn’t notarized yet. The screenshot is demo data.

CodexBar already covers a lot of this space and its public Gemini integration helped with the research. I’m trying a smaller three-service view with a shared pace display and English/Korean UI. Codex helped with the implementation and tests.

Code and current setup: https://github.com/Sunjae-L22/chatgpt-usage/tree/feat/multi-provider-usage

Does the pace line make sense next to the remaining quota, or would you find a separate time bar easier to read?

## Publication notes

- Use the first X draft as a build-in-progress update. It is intentionally short enough for a normal X post when the URL is shortened by X.
- Do not reuse an old filtered Reddit post as evidence of this release's reception. If using a community, check its current promotion rules before posting.
- The verified result is limited to the author’s own Mac and accounts. Leave the demo-data caption intact; do not use private account screenshots.
- No star counts, installation counts, tester testimonials, or performance claims are included.
