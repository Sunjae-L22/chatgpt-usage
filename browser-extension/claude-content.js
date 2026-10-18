AIUsageContent.start("claude", async () => {
  const organization = AIUsageClaude.organization(await AIUsageContent.getText("https://claude.ai/api/organizations"));
  return AIUsageClaude.parse(await AIUsageContent.getText(`https://claude.ai/api/organizations/${organization}/usage`));
});
