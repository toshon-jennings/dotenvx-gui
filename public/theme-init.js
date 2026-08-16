try {
  if (localStorage.getItem('dotenvx-gui-theme') === 'lamplight') {
    document.documentElement.setAttribute('data-theme', 'lamplight');
  }
} catch {
  // Private mode: fall back to daylight.
}
