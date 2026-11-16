const copyButton = document.querySelector('[data-copy]');
const commands = 'brew tap maxmeis/hypermug https://github.com/maxmeis/HyperMug\nbrew install --cask maxmeis/hypermug/hypermug';
copyButton?.addEventListener('click', async () => {
  try {
    await navigator.clipboard.writeText(commands);
    copyButton.textContent = 'Copied';
    copyButton.setAttribute('aria-label', 'Homebrew installation commands copied');
  } catch {
    copyButton.textContent = 'Select commands above to copy';
    copyButton.setAttribute('aria-label', 'Select the Homebrew installation commands above to copy');
  }
});
