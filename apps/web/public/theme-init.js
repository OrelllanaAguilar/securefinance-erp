(() => {
  try {
    const stored = localStorage.getItem('securefinance.anonymousTheme');
    const saved = ['claro', 'oscuro', 'sistema'].includes(stored) ? stored : 'sistema';
    const dark = saved === 'oscuro' || (saved === 'sistema' && matchMedia('(prefers-color-scheme: dark)').matches);
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    document.documentElement.dataset.themePreference = saved;
    document.querySelector('meta[name="color-scheme"]').content = dark ? 'dark' : 'light';
    document.querySelector('meta[name="theme-color"]').content = dark ? '#141414' : '#f8f7f4';
  } catch {
    document.documentElement.dataset.theme = 'light';
  }
})();
