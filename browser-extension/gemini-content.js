AIUsageContent.start("gemini", async () => AIUsageGemini.parse(
  await AIUsageContent.getText(AIUsageGemini.url(location.href))
));
